//! fiew-owned review-note model and the `fiew.review/v1` Markdown format
//! (ARP-0006). One `Review` is one file in `.reviews/`. Parsing and serializing
//! are pure and round-trippable so the format stays a stable, agent-readable
//! contract; no filesystem or git access happens here.

const std = @import("std");
const git = @import("git.zig");

pub const schema = "fiew.review/v1";

pub const Side = enum {
    old,
    new,

    pub fn label(self: Side) []const u8 {
        return switch (self) {
            .old => "old",
            .new => "new",
        };
    }
};

pub const Status = enum {
    open,
    resolved,
    /// Reserved for cross-refresh re-anchoring (ISSUE-0023); unused in v1 flows.
    outdated,

    pub fn label(self: Status) []const u8 {
        return @tagName(self);
    }
};

/// A file note anchors to a whole path; a line note anchors to a contiguous
/// range on one side of the diff and carries an excerpt.
pub const Scope = enum { file, line };

pub const Note = struct {
    id: []const u8,
    path: []const u8,
    group: git.Group,
    status: Status,
    /// Present for line notes.
    side: ?Side = null,
    start_line: ?usize = null,
    end_line: ?usize = null,
    /// Side blob SHA when one exists (staged/committed); absent for unstaged.
    blob: ?[]const u8 = null,
    /// The anchored diff excerpt (required for line notes).
    excerpt: ?[]const u8 = null,
    body: []const u8,

    pub fn scope(self: Note) Scope {
        return if (self.side != null) .line else .file;
    }
};

pub const Review = struct {
    allocator: std.mem.Allocator,
    base_ref: []const u8,
    base_sha: []const u8,
    created: []const u8,
    notes: []Note,

    pub fn deinit(self: *Review) void {
        self.allocator.free(self.base_ref);
        self.allocator.free(self.base_sha);
        self.allocator.free(self.created);
        for (self.notes) |note| freeNote(self.allocator, note);
        self.allocator.free(self.notes);
        self.* = undefined;
    }
};

pub const ParseError = error{ MalformedReview, MissingField } || std.mem.Allocator.Error;

/// Serialize a review to the `fiew.review/v1` Markdown format.
pub fn serialize(allocator: std.mem.Allocator, review: Review) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    const writer = &out;

    try writer.appendSlice(allocator, "---\n");
    try appendField(allocator, writer, "schema", schema);
    try appendField(allocator, writer, "created", review.created);
    try printInto(allocator, writer, "base: {{ ref: {s}, sha: {s} }}\n", .{ review.base_ref, review.base_sha });
    try writer.appendSlice(allocator, "---\n");

    for (review.notes) |note| {
        try writer.appendSlice(allocator, "\n## ");
        try appendHeading(allocator, writer, note);
        try writer.append(allocator, '\n');
        try printInto(allocator, writer, "- id: {s}\n", .{note.id});
        try printInto(allocator, writer, "- path: {s}\n", .{note.path});
        try printInto(allocator, writer, "- group: {s}\n", .{@tagName(note.group)});
        if (note.side) |side| try printInto(allocator, writer, "- side: {s}\n", .{side.label()});
        if (note.start_line) |start| {
            if (note.end_line) |end| {
                if (end != start) {
                    try printInto(allocator, writer, "- lines: {d}-{d}\n", .{ start, end });
                } else {
                    try printInto(allocator, writer, "- lines: {d}\n", .{start});
                }
            }
        }
        if (note.blob) |blob| try printInto(allocator, writer, "- blob: {s}\n", .{blob});
        try printInto(allocator, writer, "- status: {s}\n", .{note.status.label()});

        if (note.excerpt) |excerpt| {
            try writer.appendSlice(allocator, "\n```diff\n");
            try writer.appendSlice(allocator, excerpt);
            if (excerpt.len != 0 and excerpt[excerpt.len - 1] != '\n') try writer.append(allocator, '\n');
            try writer.appendSlice(allocator, "```\n");
        }
        try writer.append(allocator, '\n');
        try writer.appendSlice(allocator, note.body);
        if (note.body.len != 0 and note.body[note.body.len - 1] != '\n') try writer.append(allocator, '\n');
    }
    return out.toOwnedSlice(allocator);
}

/// Parse a `fiew.review/v1` Markdown document.
pub fn parse(allocator: std.mem.Allocator, bytes: []const u8) ParseError!Review {
    var rest = bytes;
    if (!consume(&rest, "---\n")) return error.MalformedReview;
    const front_end = std.mem.indexOf(u8, rest, "\n---") orelse return error.MalformedReview;
    const front = rest[0..front_end];
    rest = rest[front_end + 1 ..];
    _ = consume(&rest, "---\n");

    var base_ref: []const u8 = "";
    var base_sha: []const u8 = "";
    var created: []const u8 = "";
    var front_lines = std.mem.splitScalar(u8, front, '\n');
    while (front_lines.next()) |line| {
        if (fieldValue(line, "created:")) |value| created = value;
        if (std.mem.startsWith(u8, std.mem.trimStart(u8, line, " "), "base:")) {
            base_ref = between(line, "ref:", ",") orelse "";
            base_sha = between(line, "sha:", "}") orelse "";
        }
    }

    var notes: std.ArrayList(Note) = .empty;
    errdefer {
        for (notes.items) |note| freeNote(allocator, note);
        notes.deinit(allocator);
    }

    var sections = std.mem.splitSequence(u8, rest, "\n## ");
    _ = sections.next(); // preamble before the first heading
    while (sections.next()) |section| {
        const note = try parseNote(allocator, section);
        try notes.append(allocator, note);
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
        .notes = try notes.toOwnedSlice(allocator),
    };
}

fn parseNote(allocator: std.mem.Allocator, section: []const u8) ParseError!Note {
    // Skip the (decorative) heading line; bullets are authoritative.
    const heading_end = std.mem.indexOfScalar(u8, section, '\n') orelse section.len;
    var cursor = section[@min(heading_end + 1, section.len)..];

    var id: []const u8 = "";
    var path: []const u8 = "";
    var group: ?git.Group = null;
    var side: ?Side = null;
    var start_line: ?usize = null;
    var end_line: ?usize = null;
    var blob: ?[]const u8 = null;
    var status: Status = .open;

    while (true) {
        const line_end = std.mem.indexOfScalar(u8, cursor, '\n') orelse cursor.len;
        const line = cursor[0..line_end];
        if (!std.mem.startsWith(u8, line, "- ")) break;
        const kv = line[2..];
        if (fieldValue(kv, "id:")) |value| id = value;
        if (fieldValue(kv, "path:")) |value| path = value;
        if (fieldValue(kv, "group:")) |value| group = std.meta.stringToEnum(git.Group, value);
        if (fieldValue(kv, "side:")) |value| side = std.meta.stringToEnum(Side, value);
        if (fieldValue(kv, "blob:")) |value| blob = value;
        if (fieldValue(kv, "status:")) |value| status = std.meta.stringToEnum(Status, value) orelse .open;
        if (fieldValue(kv, "lines:")) |value| {
            const range = parseLineRange(value);
            start_line = range.start;
            end_line = range.end;
        }
        if (line_end >= cursor.len) {
            cursor = cursor[cursor.len..];
            break;
        }
        cursor = cursor[line_end + 1 ..];
    }

    // Optional excerpt fenced block, then the body.
    var excerpt: ?[]const u8 = null;
    var body_source = std.mem.trimStart(u8, cursor, "\n");
    if (std.mem.startsWith(u8, body_source, "```diff\n")) {
        const after_open = body_source["```diff\n".len..];
        if (std.mem.indexOf(u8, after_open, "\n```")) |close| {
            excerpt = after_open[0..close];
            body_source = std.mem.trimStart(u8, after_open[close + "\n```".len ..], "\n");
        }
    }
    const body = std.mem.trimEnd(u8, body_source, "\n");

    if (path.len == 0 or group == null) return error.MissingField;

    const owned_id = try allocator.dupe(u8, id);
    errdefer allocator.free(owned_id);
    const owned_path = try allocator.dupe(u8, path);
    errdefer allocator.free(owned_path);
    const owned_blob = if (blob) |value| try allocator.dupe(u8, value) else null;
    errdefer if (owned_blob) |value| allocator.free(value);
    const owned_excerpt = if (excerpt) |value| try allocator.dupe(u8, value) else null;
    errdefer if (owned_excerpt) |value| allocator.free(value);
    const owned_body = try allocator.dupe(u8, body);

    return .{
        .id = owned_id,
        .path = owned_path,
        .group = group.?,
        .status = status,
        .side = side,
        .start_line = start_line,
        .end_line = end_line,
        .blob = owned_blob,
        .excerpt = owned_excerpt,
        .body = owned_body,
    };
}

fn freeNote(allocator: std.mem.Allocator, note: Note) void {
    allocator.free(note.id);
    allocator.free(note.path);
    if (note.blob) |blob| allocator.free(blob);
    if (note.excerpt) |excerpt| allocator.free(excerpt);
    allocator.free(note.body);
}

fn printInto(allocator: std.mem.Allocator, out: *std.ArrayList(u8), comptime fmt: []const u8, args: anytype) !void {
    const rendered = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(rendered);
    try out.appendSlice(allocator, rendered);
}

fn appendField(allocator: std.mem.Allocator, writer: *std.ArrayList(u8), key: []const u8, value: []const u8) !void {
    try printInto(allocator, writer, "{s}: {s}\n", .{ key, value });
}

fn appendHeading(allocator: std.mem.Allocator, writer: *std.ArrayList(u8), note: Note) !void {
    try writer.appendSlice(allocator, note.path);
    if (note.side) |side| {
        try printInto(allocator, writer, " · {s}/{s}", .{ @tagName(note.group), side.label() });
        if (note.start_line) |start| {
            if (note.end_line) |end| {
                if (end != start) {
                    try printInto(allocator, writer, " · L{d}–L{d}", .{ start, end });
                } else {
                    try printInto(allocator, writer, " · L{d}", .{start});
                }
            }
        }
    }
}

const LineRange = struct { start: usize, end: usize };

fn parseLineRange(value: []const u8) LineRange {
    if (std.mem.indexOfScalar(u8, value, '-')) |dash| {
        const start = std.fmt.parseInt(usize, value[0..dash], 10) catch 0;
        const end = std.fmt.parseInt(usize, value[dash + 1 ..], 10) catch start;
        return .{ .start = start, .end = end };
    }
    const single = std.fmt.parseInt(usize, value, 10) catch 0;
    return .{ .start = single, .end = single };
}

fn fieldValue(line: []const u8, key: []const u8) ?[]const u8 {
    const trimmed = std.mem.trimStart(u8, line, " ");
    if (!std.mem.startsWith(u8, trimmed, key)) return null;
    return std.mem.trim(u8, trimmed[key.len..], " ");
}

fn between(haystack: []const u8, open: []const u8, close: []const u8) ?[]const u8 {
    const start = std.mem.indexOf(u8, haystack, open) orelse return null;
    const after = haystack[start + open.len ..];
    const end = std.mem.indexOf(u8, after, close) orelse return null;
    return std.mem.trim(u8, after[0..end], " ");
}

fn consume(rest: *[]const u8, prefix: []const u8) bool {
    if (!std.mem.startsWith(u8, rest.*, prefix)) return false;
    rest.* = rest.*[prefix.len..];
    return true;
}

// --- Tests ---------------------------------------------------------------

const testing = std.testing;

test "a line note round-trips through serialize and parse" {
    const notes = [_]Note{.{
        .id = "n1",
        .path = "src/app/commands.zig",
        .group = .staged,
        .status = .open,
        .side = .new,
        .start_line = 120,
        .end_line = 134,
        .blob = "9f8e7d6",
        .excerpt = "@@ -118,3 +120,4 @@\n+    added line",
        .body = "This branch is doing too much.\n\nSplit it up.",
    }};
    const review: Review = .{
        .allocator = testing.allocator,
        .base_ref = "HEAD",
        .base_sha = "a1b2c3d4",
        .created = "2026-08-27T14:03:00Z",
        .notes = @constCast(&notes),
    };

    const text = try serialize(testing.allocator, review);
    defer testing.allocator.free(text);

    var parsed = try parse(testing.allocator, text);
    defer parsed.deinit();

    try testing.expectEqualStrings("HEAD", parsed.base_ref);
    try testing.expectEqualStrings("a1b2c3d4", parsed.base_sha);
    try testing.expectEqual(@as(usize, 1), parsed.notes.len);
    const note = parsed.notes[0];
    try testing.expectEqualStrings("n1", note.id);
    try testing.expectEqualStrings("src/app/commands.zig", note.path);
    try testing.expectEqual(git.Group.staged, note.group);
    try testing.expectEqual(Side.new, note.side.?);
    try testing.expectEqual(@as(usize, 120), note.start_line.?);
    try testing.expectEqual(@as(usize, 134), note.end_line.?);
    try testing.expectEqualStrings("9f8e7d6", note.blob.?);
    try testing.expectEqualStrings("@@ -118,3 +120,4 @@\n+    added line", note.excerpt.?);
    try testing.expectEqualStrings("This branch is doing too much.\n\nSplit it up.", note.body);
    try testing.expectEqual(Scope.line, note.scope());
}

test "a file note has no side, lines, or excerpt" {
    const notes = [_]Note{.{
        .id = "n2",
        .path = "notes.txt",
        .group = .untracked,
        .status = .resolved,
        .body = "Should this file be committed at all?",
    }};
    const review: Review = .{
        .allocator = testing.allocator,
        .base_ref = "HEAD",
        .base_sha = "",
        .created = "2026-08-27T14:05:00Z",
        .notes = @constCast(&notes),
    };
    const text = try serialize(testing.allocator, review);
    defer testing.allocator.free(text);

    var parsed = try parse(testing.allocator, text);
    defer parsed.deinit();
    const note = parsed.notes[0];
    try testing.expectEqual(Scope.file, note.scope());
    try testing.expect(note.side == null);
    try testing.expect(note.excerpt == null);
    try testing.expectEqual(Status.resolved, note.status);
    try testing.expectEqualStrings("Should this file be committed at all?", note.body);
}

test "a review with no notes round-trips" {
    const review: Review = .{
        .allocator = testing.allocator,
        .base_ref = "HEAD",
        .base_sha = "deadbeef",
        .created = "2026-08-27T00:00:00Z",
        .notes = &.{},
    };
    const text = try serialize(testing.allocator, review);
    defer testing.allocator.free(text);
    var parsed = try parse(testing.allocator, text);
    defer parsed.deinit();
    try testing.expectEqual(@as(usize, 0), parsed.notes.len);
    try testing.expectEqualStrings("deadbeef", parsed.base_sha);
}
