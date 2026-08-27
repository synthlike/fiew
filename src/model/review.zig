//! Reviewer-owned review threads and the public `fiew.review/v1` Markdown
//! format. Structural metadata is line-oriented; comment bodies are byte-counted
//! so arbitrary Markdown headings remain ordinary comment content.

const std = @import("std");
const git = @import("git.zig");

pub const schema = "fiew.review/v1";

pub const Side = enum {
    old,
    new,

    pub fn label(self: Side) []const u8 {
        return @tagName(self);
    }
};

pub const Status = enum {
    open,
    resolved,
    outdated,

    pub fn label(self: Status) []const u8 {
        return @tagName(self);
    }

    pub fn blocksApproval(self: Status) bool {
        return self != .resolved;
    }
};

pub const Scope = enum { file, line };
pub const Author = enum { reviewer, agent };

pub const Comment = struct {
    author: Author,
    body: []const u8,
};

pub const Thread = struct {
    id: []const u8,
    path: []const u8,
    group: git.Group,
    status: Status,
    side: ?Side = null,
    start_line: ?usize = null,
    end_line: ?usize = null,
    blob: ?[]const u8 = null,
    excerpt: ?[]const u8 = null,
    comments: []Comment,

    pub fn scope(self: Thread) Scope {
        return if (self.side == null) .file else .line;
    }

    pub fn lastComment(self: Thread) ?Comment {
        if (self.comments.len == 0) return null;
        return self.comments[self.comments.len - 1];
    }
};

pub const Review = struct {
    allocator: std.mem.Allocator,
    base_ref: []const u8,
    base_sha: []const u8,
    created: []const u8,
    threads: []Thread,

    pub fn deinit(self: *Review) void {
        self.allocator.free(self.base_ref);
        self.allocator.free(self.base_sha);
        self.allocator.free(self.created);
        for (self.threads) |thread| freeThread(self.allocator, thread);
        self.allocator.free(self.threads);
        self.* = undefined;
    }
};

pub const ParseError = error{
    MalformedReview,
    MissingField,
    InvalidSchema,
    FutureSchema,
} || std.mem.Allocator.Error;

pub fn serialize(allocator: std.mem.Allocator, value: Review) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, "---\n");
    try field(allocator, &out, "schema", schema);
    try field(allocator, &out, "created", value.created);
    try print(allocator, &out, "base: {{ ref: {s}, sha: {s} }}\n", .{ value.base_ref, value.base_sha });
    try out.appendSlice(allocator, "---\n");

    for (value.threads) |thread| {
        try print(allocator, &out, "\n## Thread {s}\n", .{thread.id});
        try print(allocator, &out, "- id: {s}\n", .{thread.id});
        try print(allocator, &out, "- path: {s}\n", .{thread.path});
        try print(allocator, &out, "- group: {s}\n", .{@tagName(thread.group)});
        try print(allocator, &out, "- status: {s}\n", .{@tagName(thread.status)});
        if (thread.side) |side| try print(allocator, &out, "- side: {s}\n", .{@tagName(side)});
        if (thread.start_line) |start| {
            const end = thread.end_line orelse start;
            if (start == end)
                try print(allocator, &out, "- lines: {d}\n", .{start})
            else
                try print(allocator, &out, "- lines: {d}-{d}\n", .{ start, end });
        }
        if (thread.blob) |blob| try print(allocator, &out, "- blob: {s}\n", .{blob});
        try out.append(allocator, '\n');
        if (thread.excerpt) |excerpt| {
            try out.appendSlice(allocator, "```diff\n");
            try out.appendSlice(allocator, excerpt);
            if (excerpt.len == 0 or excerpt[excerpt.len - 1] != '\n') try out.append(allocator, '\n');
            try out.appendSlice(allocator, "```\n\n");
        }
        try out.appendSlice(allocator, "### Comments\n");
        for (thread.comments) |comment| {
            try print(allocator, &out, "<!-- fiew-comment {s} {d} -->\n", .{ @tagName(comment.author), comment.body.len });
            try out.appendSlice(allocator, comment.body);
            try out.append(allocator, '\n');
        }
    }
    return out.toOwnedSlice(allocator);
}

pub fn parse(allocator: std.mem.Allocator, bytes: []const u8) ParseError!Review {
    var cursor: usize = 0;
    if (!take(bytes, &cursor, "---\n")) return error.MalformedReview;
    const front_end = std.mem.indexOfPos(u8, bytes, cursor, "\n---\n") orelse return error.MalformedReview;
    const front = bytes[cursor..front_end];
    cursor = front_end + "\n---\n".len;

    var found_schema: []const u8 = "";
    var created: []const u8 = "";
    var base_ref: []const u8 = "";
    var base_sha: []const u8 = "";
    var lines = std.mem.splitScalar(u8, front, '\n');
    while (lines.next()) |line| {
        if (fieldValue(line, "schema:")) |value| found_schema = value;
        if (fieldValue(line, "created:")) |value| created = value;
        if (std.mem.startsWith(u8, line, "base:")) {
            base_ref = between(line, "ref:", ",") orelse "";
            base_sha = between(line, "sha:", "}") orelse "";
        }
    }
    if (found_schema.len == 0) return error.InvalidSchema;
    if (!std.mem.eql(u8, found_schema, schema)) {
        if (std.mem.startsWith(u8, found_schema, "fiew.review/")) return error.FutureSchema;
        return error.InvalidSchema;
    }
    if (created.len == 0) return error.MissingField;

    var threads: std.ArrayList(Thread) = .empty;
    errdefer {
        for (threads.items) |thread| freeThread(allocator, thread);
        threads.deinit(allocator);
    }
    while (true) {
        skipNewlines(bytes, &cursor);
        if (cursor == bytes.len) break;
        if (!take(bytes, &cursor, "## Thread ")) return error.MalformedReview;
        _ = try nextLine(bytes, &cursor); // decorative id
        const thread = try parseThread(allocator, bytes, &cursor);
        try threads.append(allocator, thread);
    }

    const owned_ref = try allocator.dupe(u8, base_ref);
    errdefer allocator.free(owned_ref);
    const owned_sha = try allocator.dupe(u8, base_sha);
    errdefer allocator.free(owned_sha);
    const owned_created = try allocator.dupe(u8, created);
    errdefer allocator.free(owned_created);
    return .{
        .allocator = allocator,
        .base_ref = owned_ref,
        .base_sha = owned_sha,
        .created = owned_created,
        .threads = try threads.toOwnedSlice(allocator),
    };
}

fn parseThread(allocator: std.mem.Allocator, bytes: []const u8, cursor: *usize) ParseError!Thread {
    var id: []const u8 = "";
    var path: []const u8 = "";
    var group: ?git.Group = null;
    var status: ?Status = null;
    var side: ?Side = null;
    var start_line: ?usize = null;
    var end_line: ?usize = null;
    var blob: ?[]const u8 = null;

    while (cursor.* < bytes.len and std.mem.startsWith(u8, bytes[cursor.*..], "- ")) {
        const line = try nextLine(bytes, cursor);
        const kv = line[2..];
        if (fieldValue(kv, "id:")) |value| id = value;
        if (fieldValue(kv, "path:")) |value| path = value;
        if (fieldValue(kv, "group:")) |value| group = std.meta.stringToEnum(git.Group, value) orelse return error.MalformedReview;
        if (fieldValue(kv, "status:")) |value| status = std.meta.stringToEnum(Status, value) orelse return error.MalformedReview;
        if (fieldValue(kv, "side:")) |value| side = std.meta.stringToEnum(Side, value) orelse return error.MalformedReview;
        if (fieldValue(kv, "blob:")) |value| blob = value;
        if (fieldValue(kv, "lines:")) |value| {
            const range = parseLineRange(value);
            start_line = range.start;
            end_line = range.end;
        }
    }
    skipNewlines(bytes, cursor);

    var excerpt: ?[]const u8 = null;
    if (take(bytes, cursor, "```diff\n")) {
        const close = std.mem.indexOfPos(u8, bytes, cursor.*, "\n```\n") orelse return error.MalformedReview;
        excerpt = bytes[cursor.*..close];
        cursor.* = close + "\n```\n".len;
        skipNewlines(bytes, cursor);
    }
    if (!take(bytes, cursor, "### Comments\n")) return error.MalformedReview;

    var comments: std.ArrayList(Comment) = .empty;
    errdefer {
        for (comments.items) |comment| allocator.free(comment.body);
        comments.deinit(allocator);
    }
    while (std.mem.startsWith(u8, bytes[cursor.*..], "<!-- fiew-comment ")) {
        const marker = try nextLine(bytes, cursor);
        const prefix = "<!-- fiew-comment ";
        if (!std.mem.endsWith(u8, marker, " -->")) return error.MalformedReview;
        const fields = marker[prefix.len .. marker.len - " -->".len];
        const space = std.mem.indexOfScalar(u8, fields, ' ') orelse return error.MalformedReview;
        const author = std.meta.stringToEnum(Author, fields[0..space]) orelse return error.MalformedReview;
        const length = std.fmt.parseInt(usize, fields[space + 1 ..], 10) catch return error.MalformedReview;
        if (length > bytes.len - cursor.*) return error.MalformedReview;
        const body = try allocator.dupe(u8, bytes[cursor.* .. cursor.* + length]);
        cursor.* += length;
        if (cursor.* >= bytes.len or bytes[cursor.*] != '\n') {
            allocator.free(body);
            return error.MalformedReview;
        }
        cursor.* += 1;
        try comments.append(allocator, .{ .author = author, .body = body });
    }

    if (id.len == 0 or path.len == 0 or group == null or status == null or comments.items.len == 0)
        return error.MissingField;
    if (side == null and (start_line != null or excerpt != null)) return error.MalformedReview;
    if (side != null and (start_line == null or end_line == null or excerpt == null)) return error.MalformedReview;
    if (start_line) |start| if (start == 0 or (end_line orelse 0) < start) return error.MalformedReview;

    const owned_id = try allocator.dupe(u8, id);
    errdefer allocator.free(owned_id);
    const owned_path = try allocator.dupe(u8, path);
    errdefer allocator.free(owned_path);
    const owned_blob = if (blob) |value| try allocator.dupe(u8, value) else null;
    errdefer if (owned_blob) |value| allocator.free(value);
    const owned_excerpt = if (excerpt) |value| try allocator.dupe(u8, value) else null;
    errdefer if (owned_excerpt) |value| allocator.free(value);
    return .{
        .id = owned_id,
        .path = owned_path,
        .group = group.?,
        .status = status.?,
        .side = side,
        .start_line = start_line,
        .end_line = end_line,
        .blob = owned_blob,
        .excerpt = owned_excerpt,
        .comments = try comments.toOwnedSlice(allocator),
    };
}

pub fn freeThread(allocator: std.mem.Allocator, thread: Thread) void {
    allocator.free(thread.id);
    allocator.free(thread.path);
    if (thread.blob) |blob| allocator.free(blob);
    if (thread.excerpt) |excerpt| allocator.free(excerpt);
    for (thread.comments) |comment| allocator.free(comment.body);
    allocator.free(thread.comments);
}

fn print(allocator: std.mem.Allocator, out: *std.ArrayList(u8), comptime fmt: []const u8, args: anytype) !void {
    const rendered = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(rendered);
    try out.appendSlice(allocator, rendered);
}

fn field(allocator: std.mem.Allocator, out: *std.ArrayList(u8), key: []const u8, value: []const u8) !void {
    try print(allocator, out, "{s}: {s}\n", .{ key, value });
}

fn nextLine(bytes: []const u8, cursor: *usize) ParseError![]const u8 {
    const end = std.mem.indexOfScalarPos(u8, bytes, cursor.*, '\n') orelse return error.MalformedReview;
    const line = bytes[cursor.*..end];
    cursor.* = end + 1;
    return line;
}

fn take(bytes: []const u8, cursor: *usize, prefix: []const u8) bool {
    if (!std.mem.startsWith(u8, bytes[cursor.*..], prefix)) return false;
    cursor.* += prefix.len;
    return true;
}

fn skipNewlines(bytes: []const u8, cursor: *usize) void {
    while (cursor.* < bytes.len and bytes[cursor.*] == '\n') cursor.* += 1;
}

fn fieldValue(line: []const u8, key: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, line, key)) return null;
    return std.mem.trim(u8, line[key.len..], " ");
}

fn between(haystack: []const u8, open: []const u8, close: []const u8) ?[]const u8 {
    const start = std.mem.indexOf(u8, haystack, open) orelse return null;
    const tail = haystack[start + open.len ..];
    const end = std.mem.indexOf(u8, tail, close) orelse return null;
    return std.mem.trim(u8, tail[0..end], " ");
}

const LineRange = struct { start: usize, end: usize };
fn parseLineRange(value: []const u8) LineRange {
    if (std.mem.indexOfScalar(u8, value, '-')) |dash| {
        const start = std.fmt.parseInt(usize, value[0..dash], 10) catch 0;
        const end = std.fmt.parseInt(usize, value[dash + 1 ..], 10) catch start;
        return .{ .start = start, .end = end };
    }
    const line = std.fmt.parseInt(usize, value, 10) catch 0;
    return .{ .start = line, .end = line };
}

const testing = std.testing;

fn sampleReview(comments: []Comment) Review {
    const Static = struct {
        var threads: [1]Thread = undefined;
    };
    Static.threads[0] = .{
        .id = "t1",
        .path = "src/main.zig",
        .group = .unstaged,
        .status = .open,
        .side = .new,
        .start_line = 2,
        .end_line = 3,
        .excerpt = "+one\n+two",
        .comments = comments,
    };
    return .{ .allocator = testing.allocator, .base_ref = "HEAD", .base_sha = "abc", .created = "2026-08-27T00:00:00Z", .threads = &Static.threads };
}

test "threads preserve ordered roles and arbitrary Markdown headings" {
    var comments = [_]Comment{
        .{ .author = .reviewer, .body = "Please revise.\n\n## This is body Markdown" },
        .{ .author = .agent, .body = "Done.\n### Also body" },
    };
    const text = try serialize(testing.allocator, sampleReview(&comments));
    defer testing.allocator.free(text);
    var parsed = try parse(testing.allocator, text);
    defer parsed.deinit();
    try testing.expectEqual(@as(usize, 1), parsed.threads.len);
    try testing.expectEqual(@as(usize, 2), parsed.threads[0].comments.len);
    try testing.expectEqual(Author.reviewer, parsed.threads[0].comments[0].author);
    try testing.expectEqualStrings("Please revise.\n\n## This is body Markdown", parsed.threads[0].comments[0].body);
    try testing.expectEqual(Author.agent, parsed.threads[0].comments[1].author);
}

test "file thread round trips without line anchor" {
    var comments = [_]Comment{.{ .author = .reviewer, .body = "Why is this file needed?" }};
    var value = sampleReview(&comments);
    value.threads[0].side = null;
    value.threads[0].start_line = null;
    value.threads[0].end_line = null;
    value.threads[0].excerpt = null;
    const text = try serialize(testing.allocator, value);
    defer testing.allocator.free(text);
    var parsed = try parse(testing.allocator, text);
    defer parsed.deinit();
    try testing.expectEqual(Scope.file, parsed.threads[0].scope());
}

test "thread format is v1 and future schemas are refused" {
    var comments = [_]Comment{.{ .author = .reviewer, .body = "body" }};
    const text = try serialize(testing.allocator, sampleReview(&comments));
    defer testing.allocator.free(text);
    try testing.expect(std.mem.indexOf(u8, text, "schema: fiew.review/v1") != null);

    const future = "---\nschema: fiew.review/v2\ncreated: now\nbase: { ref: HEAD, sha: x }\n---\n";
    try testing.expectError(error.FutureSchema, parse(testing.allocator, future));
    const superseded_layout =
        "---\nschema: fiew.review/v1\ncreated: now\nbase: { ref: HEAD, sha: x }\n---\n" ++
        "\n## old note\n- id: n1\n- path: a.zig\n- group: unstaged\n- status: open\n\nbody\n";
    try testing.expectError(error.MalformedReview, parse(testing.allocator, superseded_layout));
}
