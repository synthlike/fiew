//! `fiew review` command contract and non-interactive review operations.
//! Parsing and rendering are terminal-independent so agents never need to
//! scrape or mutate the interactive TUI.

const std = @import("std");
const review = @import("../model/review.zig");
const store = @import("../adapters/storage/review_store.zig");

pub const Format = enum { json, markdown };

pub const Command = union(enum) {
    start: struct { name: ?[]const u8 = null, repo: []const u8 = "." },
    open: struct { id: []const u8, repo: []const u8 = "." },
    show: struct { id: []const u8, repo: []const u8 = ".", format: Format = .json },
    reply: struct { id: []const u8, thread_id: []const u8, body_file: []const u8, repo: []const u8 = "." },
};

pub const ParseError = error{
    MissingCommand,
    UnknownCommand,
    MissingOperand,
    UnexpectedOperand,
    MissingOptionValue,
    DuplicateOption,
    UnknownOption,
    InvalidIdentifier,
    InvalidFormat,
};

pub fn parse(args: []const []const u8) ParseError!Command {
    if (args.len == 0) return error.MissingCommand;
    if (std.mem.eql(u8, args[0], "start")) return parseStart(args[1..]);
    if (std.mem.eql(u8, args[0], "open")) return parseOpen(args[1..]);
    if (std.mem.eql(u8, args[0], "show")) return parseShow(args[1..]);
    if (std.mem.eql(u8, args[0], "reply")) return parseReply(args[1..]);
    return error.UnknownCommand;
}

fn parseStart(args: []const []const u8) ParseError!Command {
    var name: ?[]const u8 = null;
    var repo: ?[]const u8 = null;
    var index: usize = 0;
    while (index < args.len) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--name")) {
            if (name != null) return error.DuplicateOption;
            name = try optionValue(args, &index);
        } else if (std.mem.eql(u8, arg, "--repo")) {
            if (repo != null) return error.DuplicateOption;
            repo = try optionValue(args, &index);
        } else if (std.mem.startsWith(u8, arg, "--")) {
            return error.UnknownOption;
        } else return error.UnexpectedOperand;
        index += 1;
    }
    return .{ .start = .{ .name = name, .repo = repo orelse "." } };
}

fn parseOpen(args: []const []const u8) ParseError!Command {
    var id: ?[]const u8 = null;
    var repo: ?[]const u8 = null;
    var index: usize = 0;
    while (index < args.len) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--repo")) {
            if (repo != null) return error.DuplicateOption;
            repo = try optionValue(args, &index);
        } else if (std.mem.startsWith(u8, arg, "--")) {
            return error.UnknownOption;
        } else if (id == null) id = arg else return error.UnexpectedOperand;
        index += 1;
    }
    const value = id orelse return error.MissingOperand;
    if (!validIdentifier(value)) return error.InvalidIdentifier;
    return .{ .open = .{ .id = value, .repo = repo orelse "." } };
}

fn parseShow(args: []const []const u8) ParseError!Command {
    var id: ?[]const u8 = null;
    var repo: ?[]const u8 = null;
    var format: ?Format = null;
    var index: usize = 0;
    while (index < args.len) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--repo")) {
            if (repo != null) return error.DuplicateOption;
            repo = try optionValue(args, &index);
        } else if (std.mem.eql(u8, arg, "--format")) {
            if (format != null) return error.DuplicateOption;
            const value = try optionValue(args, &index);
            format = std.meta.stringToEnum(Format, value) orelse return error.InvalidFormat;
        } else if (std.mem.startsWith(u8, arg, "--")) {
            return error.UnknownOption;
        } else if (id == null) id = arg else return error.UnexpectedOperand;
        index += 1;
    }
    const value = id orelse return error.MissingOperand;
    if (!validIdentifier(value)) return error.InvalidIdentifier;
    return .{ .show = .{ .id = value, .repo = repo orelse ".", .format = format orelse .json } };
}

fn parseReply(args: []const []const u8) ParseError!Command {
    var operands: [2]?[]const u8 = .{ null, null };
    var operand_count: usize = 0;
    var repo: ?[]const u8 = null;
    var body_file: ?[]const u8 = null;
    var index: usize = 0;
    while (index < args.len) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--repo")) {
            if (repo != null) return error.DuplicateOption;
            repo = try optionValue(args, &index);
        } else if (std.mem.eql(u8, arg, "--body-file")) {
            if (body_file != null) return error.DuplicateOption;
            body_file = try optionValue(args, &index);
        } else if (std.mem.startsWith(u8, arg, "--")) {
            return error.UnknownOption;
        } else {
            if (operand_count == operands.len) return error.UnexpectedOperand;
            operands[operand_count] = arg;
            operand_count += 1;
        }
        index += 1;
    }
    const id = operands[0] orelse return error.MissingOperand;
    const thread_id = operands[1] orelse return error.MissingOperand;
    const body = body_file orelse return error.MissingOperand;
    if (!validIdentifier(id) or !validThreadId(thread_id)) return error.InvalidIdentifier;
    return .{ .reply = .{ .id = id, .thread_id = thread_id, .body_file = body, .repo = repo orelse "." } };
}

fn optionValue(args: []const []const u8, index: *usize) ParseError![]const u8 {
    index.* += 1;
    if (index.* >= args.len or std.mem.startsWith(u8, args[index.*], "--")) return error.MissingOptionValue;
    return args[index.*];
}

pub fn validIdentifier(id: []const u8) bool {
    // Canonical IDs are YYYYMMDD-HHMMSS-slug. Keeping this shape strict avoids
    // turning the command into arbitrary basename access under `.reviews/`.
    if (id.len < 17 or id.len > 128 or id[8] != '-' or id[15] != '-' or id[16] == '-' or id[id.len - 1] == '-') return false;
    for (id[0..8]) |byte| if (!std.ascii.isDigit(byte)) return false;
    for (id[9..15]) |byte| if (!std.ascii.isDigit(byte)) return false;
    const month = std.fmt.parseInt(u8, id[4..6], 10) catch return false;
    const day = std.fmt.parseInt(u8, id[6..8], 10) catch return false;
    const hour = std.fmt.parseInt(u8, id[9..11], 10) catch return false;
    const minute = std.fmt.parseInt(u8, id[11..13], 10) catch return false;
    const second = std.fmt.parseInt(u8, id[13..15], 10) catch return false;
    if (month == 0 or month > 12 or day == 0 or day > 31 or hour > 23 or minute > 59 or second > 59) return false;
    var previous_hyphen = false;
    for (id[16..]) |byte| {
        if (!std.ascii.isLower(byte) and !std.ascii.isDigit(byte) and byte != '-') return false;
        if (byte == '-' and previous_hyphen) return false;
        previous_hyphen = byte == '-';
    }
    return true;
}

fn validThreadId(id: []const u8) bool {
    if (id.len == 0 or id.len > 64) return false;
    for (id) |byte| if (!std.ascii.isAlphanumeric(byte) and byte != '-' and byte != '_') return false;
    return true;
}

pub fn filenameForId(allocator: std.mem.Allocator, id: []const u8) (std.mem.Allocator.Error || error{InvalidIdentifier})![]u8 {
    if (!validIdentifier(id)) return error.InvalidIdentifier;
    return std.fmt.allocPrint(allocator, "{s}.md", .{id});
}

pub const Created = struct {
    allocator: std.mem.Allocator,
    id: []u8,
    filename: []u8,

    pub fn deinit(self: *Created) void {
        self.allocator.free(self.id);
        self.allocator.free(self.filename);
        self.* = undefined;
    }
};

const adjectives = [_][]const u8{ "brisk", "calm", "clear", "curious", "gentle", "keen", "quiet", "steady" };
const nouns = [_][]const u8{ "badger", "falcon", "heron", "lynx", "otter", "raven", "stoat", "wren" };

pub fn create(
    allocator: std.mem.Allocator,
    io: std.Io,
    repo_dir: std.Io.Dir,
    unix_seconds: u64,
    requested_name: ?[]const u8,
    base_sha: []const u8,
) !Created {
    var prefix_buffer: [32]u8 = undefined;
    const prefix = formatIdPrefix(&prefix_buffer, unix_seconds);
    const slug = if (requested_name) |name|
        try sanitizeSlug(allocator, name)
    else
        try generatedSlug(allocator, unix_seconds);
    defer allocator.free(slug);
    const base_id = try std.fmt.allocPrint(allocator, "{s}-{s}", .{ prefix, slug });
    defer allocator.free(base_id);

    var suffix: usize = 1;
    while (true) : (suffix += 1) {
        const id = if (suffix == 1)
            try allocator.dupe(u8, base_id)
        else
            try std.fmt.allocPrint(allocator, "{s}-{d}", .{ base_id, suffix });
        errdefer allocator.free(id);
        const filename = try filenameForId(allocator, id);
        errdefer allocator.free(filename);
        if (try store.exists(io, repo_dir, filename)) {
            allocator.free(filename);
            allocator.free(id);
            continue;
        }
        var created_buffer: [32]u8 = undefined;
        const created = formatCreated(&created_buffer, unix_seconds);
        const empty: review.Review = .{
            .allocator = undefined,
            .base_ref = "HEAD",
            .base_sha = base_sha,
            .created = created,
            .threads = &.{},
        };
        try store.save(allocator, io, repo_dir, filename, empty);
        return .{ .allocator = allocator, .id = id, .filename = filename };
    }
}

fn sanitizeSlug(allocator: std.mem.Allocator, input: []const u8) ![]u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);
    var separator = false;
    for (input) |byte| {
        if (std.ascii.isAlphanumeric(byte)) {
            if (separator and result.items.len != 0) try result.append(allocator, '-');
            try result.append(allocator, std.ascii.toLower(byte));
            separator = false;
        } else {
            separator = true;
        }
    }
    if (result.items.len == 0) return error.InvalidIdentifier;
    return result.toOwnedSlice(allocator);
}

fn generatedSlug(allocator: std.mem.Allocator, seed: u64) ![]u8 {
    var bytes = seed;
    const mixed = std.hash.Wyhash.hash(0, std.mem.asBytes(&bytes));
    const adjective = adjectives[mixed % adjectives.len];
    const noun = nouns[(mixed / adjectives.len) % nouns.len];
    return std.fmt.allocPrint(allocator, "{s}-{s}", .{ adjective, noun });
}

pub fn load(allocator: std.mem.Allocator, io: std.Io, repo_dir: std.Io.Dir, id: []const u8) !store.Loaded {
    const filename = try filenameForId(allocator, id);
    defer allocator.free(filename);
    return store.loadOne(allocator, io, repo_dir, filename);
}

pub fn render(allocator: std.mem.Allocator, id: []const u8, value: review.Review, format: Format) ![]u8 {
    return switch (format) {
        .markdown => review.serialize(allocator, value),
        .json => blk: {
            const JsonReview = struct {
                id: []const u8,
                schema: []const u8,
                created: []const u8,
                base: struct { ref: []const u8, sha: []const u8 },
                threads: []const review.Thread,
            };
            const output: JsonReview = .{
                .id = id,
                .schema = review.schema,
                .created = value.created,
                .base = .{ .ref = value.base_ref, .sha = value.base_sha },
                .threads = value.threads,
            };
            const bytes = try std.json.Stringify.valueAlloc(allocator, output, .{ .whitespace = .indent_2 });
            const with_newline = try allocator.realloc(bytes, bytes.len + 1);
            with_newline[with_newline.len - 1] = '\n';
            break :blk with_newline;
        },
    };
}

pub fn appendAgentReply(
    allocator: std.mem.Allocator,
    io: std.Io,
    repo_dir: std.Io.Dir,
    id: []const u8,
    thread_id: []const u8,
    body: []const u8,
) !void {
    if (!validThreadId(thread_id)) return error.InvalidIdentifier;
    const filename = try filenameForId(allocator, id);
    defer allocator.free(filename);
    var loaded = try store.loadOne(allocator, io, repo_dir, filename);
    defer loaded.deinit();
    var target: ?*review.Thread = null;
    for (loaded.entries[0].review.threads) |*thread| {
        if (std.mem.eql(u8, thread.id, thread_id)) {
            target = thread;
            break;
        }
    }
    const thread = target orelse return error.ThreadNotFound;
    const owned_body = try allocator.dupe(u8, body);
    thread.comments = allocator.realloc(thread.comments, thread.comments.len + 1) catch |err| {
        allocator.free(owned_body);
        return err;
    };
    thread.comments[thread.comments.len - 1] = .{ .author = .agent, .body = owned_body };
    try store.save(allocator, io, repo_dir, filename, loaded.entries[0].review);
}

/// Run the interactive session to completion before publishing its canonical
/// ID. The interactive callback owns terminal restoration on return.
pub fn afterInteractive(
    context: anytype,
    id: []const u8,
    interactive: anytype,
    output: anytype,
) !u8 {
    const code = try interactive(context);
    try output(context, id);
    return code;
}

pub fn approved(value: review.Review) bool {
    for (value.threads) |thread| if (thread.status.blocksApproval()) return false;
    return true;
}

fn formatIdPrefix(buffer: []u8, unix_seconds: u64) []const u8 {
    const parts = dateParts(unix_seconds);
    return std.fmt.bufPrint(buffer, "{d:0>4}{d:0>2}{d:0>2}-{d:0>2}{d:0>2}{d:0>2}", .{
        parts.year, parts.month, parts.day, parts.hour, parts.minute, parts.second,
    }) catch unreachable;
}

fn formatCreated(buffer: []u8, unix_seconds: u64) []const u8 {
    const parts = dateParts(unix_seconds);
    return std.fmt.bufPrint(buffer, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
        parts.year, parts.month, parts.day, parts.hour, parts.minute, parts.second,
    }) catch unreachable;
}

const DateParts = struct { year: u16, month: u4, day: u5, hour: u5, minute: u6, second: u6 };

fn dateParts(unix_seconds: u64) DateParts {
    const epoch: std.time.epoch.EpochSeconds = .{ .secs = unix_seconds };
    const year_day = epoch.getEpochDay().calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = epoch.getDaySeconds();
    return .{
        .year = year_day.year,
        .month = month_day.month.numeric(),
        .day = month_day.day_index + 1,
        .hour = day_seconds.getHoursIntoDay(),
        .minute = day_seconds.getMinutesIntoHour(),
        .second = day_seconds.getSecondsIntoMinute(),
    };
}

const testing = std.testing;

test "interactive start publishes ID only after restoration returns" {
    const Probe = struct {
        restored: bool = false,
        published: bool = false,

        fn interactive(self: *@This()) !u8 {
            self.restored = true;
            return 1;
        }

        fn output(self: *@This(), id: []const u8) !void {
            try testing.expect(self.restored);
            try testing.expectEqualStrings("id", id);
            self.published = true;
        }
    };
    var probe: Probe = .{};
    const code = try afterInteractive(&probe, "id", Probe.interactive, Probe.output);
    try testing.expectEqual(@as(u8, 1), code);
    try testing.expect(probe.published);
}

test "command parsing defaults repo and rejects malformed operands" {
    const start = try parse(&.{ "start", "--name", "My Review" });
    try testing.expectEqualStrings(".", start.start.repo);
    const show = try parse(&.{ "show", "20260828-120000-keen-wren", "--repo", "repo", "--format", "markdown" });
    try testing.expectEqual(Format.markdown, show.show.format);
    const reply = try parse(&.{ "reply", "20260828-120000-keen-wren", "t1", "--body-file", "reply.md" });
    try testing.expectEqualStrings("reply.md", reply.reply.body_file);
    try testing.expectError(error.InvalidIdentifier, parse(&.{ "open", "../review" }));
    try testing.expectError(error.InvalidIdentifier, parse(&.{ "open", "review.md" }));
    try testing.expectError(error.MissingOperand, parse(&.{ "reply", "20260828-000000-valid", "t1" }));
    try testing.expectError(error.UnknownCommand, parse(&.{"nope"}));
    try testing.expectError(error.DuplicateOption, parse(&.{ "show", "20260828-000000-valid", "--repo", "a", "--repo", "b" }));
}

test "new IDs sanitize names and add collision suffixes" {
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var first = try create(testing.allocator, testing.io, tmp.dir, 0, "My Review!", "abc");
    defer first.deinit();
    try testing.expectEqualStrings("19700101-000000-my-review", first.id);
    var second = try create(testing.allocator, testing.io, tmp.dir, 0, "My Review!", "abc");
    defer second.deinit();
    try testing.expectEqualStrings("19700101-000000-my-review-2", second.id);
    var generated = try create(testing.allocator, testing.io, tmp.dir, 1, null, "abc");
    defer generated.deinit();
    try testing.expect(std.mem.startsWith(u8, generated.id, "19700101-000001-"));
    try testing.expect(std.mem.endsWith(u8, generated.filename, ".md"));
}

test "new review creation reports persistence failure" {
    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(testing.io, .{ .sub_path = store.directory_name, .data = "not a directory" });
    try testing.expectError(
        error.ReadFailed,
        create(testing.allocator, testing.io, tmp.dir, 0, "review", "abc"),
    );
}

test "agent reply appends one comment and stable output includes history" {
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var created = try create(testing.allocator, testing.io, tmp.dir, 0, "review", "abc");
    defer created.deinit();
    var loaded = try load(testing.allocator, testing.io, tmp.dir, created.id);
    var value = &loaded.entries[0].review;
    const comments = try testing.allocator.alloc(review.Comment, 1);
    comments[0] = .{ .author = .reviewer, .body = try testing.allocator.dupe(u8, "please fix") };
    const threads = try testing.allocator.alloc(review.Thread, 1);
    threads[0] = .{ .id = try testing.allocator.dupe(u8, "t1"), .path = try testing.allocator.dupe(u8, "a.zig"), .group = .unstaged, .status = .open, .comments = comments };
    testing.allocator.free(value.threads);
    value.threads = threads;
    try store.save(testing.allocator, testing.io, tmp.dir, created.filename, value.*);
    loaded.deinit();

    try appendAgentReply(testing.allocator, testing.io, tmp.dir, created.id, "t1", "done");
    var after = try load(testing.allocator, testing.io, tmp.dir, created.id);
    defer after.deinit();
    const thread = after.entries[0].review.threads[0];
    try testing.expectEqual(@as(usize, 2), thread.comments.len);
    try testing.expectEqual(review.Author.reviewer, thread.comments[0].author);
    try testing.expectEqual(review.Author.agent, thread.comments[1].author);
    try testing.expectEqual(review.Status.open, thread.status);
    try testing.expect(!approved(after.entries[0].review));
    const json = try render(testing.allocator, created.id, after.entries[0].review, .json);
    defer testing.allocator.free(json);
    const json_again = try render(testing.allocator, created.id, after.entries[0].review, .json);
    defer testing.allocator.free(json_again);
    try testing.expectEqualStrings(json, json_again);
    try testing.expect(std.mem.indexOf(u8, json, created.id) != null);
    try testing.expect(std.mem.indexOf(u8, json, "please fix") != null);
    try testing.expect(std.mem.indexOf(u8, json, "done") != null);
    const markdown = try render(testing.allocator, created.id, after.entries[0].review, .markdown);
    defer testing.allocator.free(markdown);
    try testing.expect(std.mem.indexOf(u8, markdown, "fiew-comment agent 4") != null);
    try testing.expectError(error.ThreadNotFound, appendAgentReply(testing.allocator, testing.io, tmp.dir, created.id, "missing", "no"));
}
