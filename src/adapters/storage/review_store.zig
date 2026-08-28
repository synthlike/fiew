//! Durable repository-local review storage. Primary and backup files are
//! validated private `fiew.review/v1` JSON; writes use atomic replacement.

const std = @import("std");
const review = @import("../../model/review.zig");

pub const directory_name = ".reviews";
pub const current_filename = "current";
pub const max_review_bytes: usize = 4 << 20;

pub const Error = std.mem.Allocator.Error || error{
    ReadFailed,
    WriteFailed,
    MalformedReview,
    MissingField,
    InvalidSchema,
    FutureSchema,
    UnsupportedLegacyReview,
    CurrentReviewMissing,
    CurrentReviewMalformed,
    CurrentReviewDangling,
};

pub const Entry = struct {
    filename: []u8,
    review: review.Review,
    recovered: bool = false,
};

pub const Loaded = struct {
    allocator: std.mem.Allocator,
    entries: []Entry,

    pub const empty: Loaded = .{ .allocator = undefined, .entries = &.{} };

    pub fn deinit(self: *Loaded) void {
        for (self.entries) |*entry| {
            self.allocator.free(entry.filename);
            entry.review.deinit();
        }
        self.allocator.free(self.entries);
        self.* = undefined;
    }
};

pub fn loadOne(
    allocator: std.mem.Allocator,
    io: std.Io,
    repo_dir: std.Io.Dir,
    filename: []const u8,
) Error!Loaded {
    var dir = repo_dir.openDir(io, directory_name, .{}) catch return error.ReadFailed;
    defer dir.close(io);
    const entries = try allocator.alloc(Entry, 1);
    errdefer allocator.free(entries);
    entries[0] = loadEntry(allocator, io, dir, filename) catch |err| {
        if (err == error.ReadFailed and std.mem.endsWith(u8, filename, ".json")) {
            const legacy = try std.fmt.allocPrint(allocator, "{s}.md", .{filename[0 .. filename.len - ".json".len]});
            defer allocator.free(legacy);
            dir.access(io, legacy, .{}) catch return err;
            return error.UnsupportedLegacyReview;
        }
        return err;
    };
    return .{ .allocator = allocator, .entries = entries };
}

pub fn loadAll(allocator: std.mem.Allocator, io: std.Io, repo_dir: std.Io.Dir) Error!Loaded {
    var dir = repo_dir.openDir(io, directory_name, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return .{ .allocator = allocator, .entries = &.{} },
        else => return error.ReadFailed,
    };
    defer dir.close(io);

    var entries: std.ArrayList(Entry) = .empty;
    errdefer {
        for (entries.items) |*entry| {
            allocator.free(entry.filename);
            entry.review.deinit();
        }
        entries.deinit(allocator);
    }
    var walker = dir.walk(allocator) catch return error.ReadFailed;
    defer walker.deinit();
    while (walker.next(io) catch return error.ReadFailed) |walked| {
        if (walked.kind != .file) continue;
        if (std.mem.endsWith(u8, walked.basename, ".md")) return error.UnsupportedLegacyReview;
        if (!std.mem.endsWith(u8, walked.basename, ".json")) continue;
        var entry = try loadEntry(allocator, io, dir, walked.basename);
        entries.append(allocator, entry) catch |err| {
            allocator.free(entry.filename);
            entry.review.deinit();
            return err;
        };
    }
    return .{ .allocator = allocator, .entries = try entries.toOwnedSlice(allocator) };
}

fn loadEntry(allocator: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, filename: []const u8) Error!Entry {
    const bytes = dir.readFileAlloc(io, filename, allocator, .limited64(max_review_bytes)) catch
        return error.ReadFailed;
    defer allocator.free(bytes);
    var recovered = false;
    var parsed = review.parse(allocator, bytes) catch |primary_err| switch (primary_err) {
        error.FutureSchema => return error.FutureSchema,
        error.OutOfMemory => return error.OutOfMemory,
        else => blk: {
            const backup_name = try backupFilenameAlloc(allocator, filename);
            defer allocator.free(backup_name);
            const backup = dir.readFileAlloc(io, backup_name, allocator, .limited64(max_review_bytes)) catch
                return mapParseError(primary_err);
            defer allocator.free(backup);
            var recovered_review = review.parse(allocator, backup) catch |backup_err| return mapParseError(backup_err);
            errdefer recovered_review.deinit();
            try atomicWrite(io, dir, filename, backup);
            recovered = true;
            break :blk recovered_review;
        },
    };
    errdefer parsed.deinit();
    return .{
        .filename = try allocator.dupe(u8, filename),
        .review = parsed,
        .recovered = recovered,
    };
}

fn mapParseError(err: anyerror) Error {
    return switch (err) {
        error.MalformedReview => error.MalformedReview,
        error.MissingField => error.MissingField,
        error.InvalidSchema => error.InvalidSchema,
        error.FutureSchema => error.FutureSchema,
        error.OutOfMemory => error.OutOfMemory,
        else => error.MalformedReview,
    };
}

pub fn setCurrent(
    allocator: std.mem.Allocator,
    io: std.Io,
    repo_dir: std.Io.Dir,
    id: []const u8,
) Error!void {
    if (!validCurrentId(id)) return error.CurrentReviewMalformed;
    var dir = try openOrCreateDir(io, repo_dir);
    defer dir.close(io);
    const target = try std.fmt.allocPrint(allocator, "{s}.json", .{id});
    defer allocator.free(target);
    dir.access(io, target, .{}) catch |err| switch (err) {
        error.FileNotFound => return error.CurrentReviewDangling,
        else => return error.ReadFailed,
    };
    const contents = try std.fmt.allocPrint(allocator, "{s}\n", .{id});
    defer allocator.free(contents);
    try atomicWrite(io, dir, current_filename, contents);
}

pub fn currentId(
    allocator: std.mem.Allocator,
    io: std.Io,
    repo_dir: std.Io.Dir,
) Error![]u8 {
    var dir = repo_dir.openDir(io, directory_name, .{}) catch |err| switch (err) {
        error.FileNotFound => return error.CurrentReviewMissing,
        else => return error.ReadFailed,
    };
    defer dir.close(io);
    const bytes = dir.readFileAlloc(io, current_filename, allocator, .limited64(256)) catch |err| switch (err) {
        error.FileNotFound => return error.CurrentReviewMissing,
        else => return error.ReadFailed,
    };
    defer allocator.free(bytes);
    if (bytes.len < 2 or bytes[bytes.len - 1] != '\n' or std.mem.indexOfScalar(u8, bytes[0 .. bytes.len - 1], '\n') != null)
        return error.CurrentReviewMalformed;
    const id = bytes[0 .. bytes.len - 1];
    if (!validCurrentId(id)) return error.CurrentReviewMalformed;
    const target = try std.fmt.allocPrint(allocator, "{s}.json", .{id});
    defer allocator.free(target);
    dir.access(io, target, .{}) catch |err| switch (err) {
        error.FileNotFound => return error.CurrentReviewDangling,
        else => return error.ReadFailed,
    };
    return allocator.dupe(u8, id);
}

fn validCurrentId(id: []const u8) bool {
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

pub fn exists(io: std.Io, repo_dir: std.Io.Dir, filename: []const u8) Error!bool {
    var dir = repo_dir.openDir(io, directory_name, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return error.ReadFailed,
    };
    defer dir.close(io);
    dir.access(io, filename, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return error.ReadFailed,
    };
    return true;
}

pub fn save(
    allocator: std.mem.Allocator,
    io: std.Io,
    repo_dir: std.Io.Dir,
    filename: []const u8,
    value: review.Review,
) Error!void {
    var dir = try openOrCreateDir(io, repo_dir);
    defer dir.close(io);

    // Never overwrite an unknown or invalid primary. A validated previous value
    // becomes the one retained backup before replacement.
    const previous = dir.readFileAlloc(io, filename, allocator, .limited64(max_review_bytes)) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return error.ReadFailed,
    };
    defer if (previous) |bytes| allocator.free(bytes);
    if (previous) |bytes| {
        var validated = review.parse(allocator, bytes) catch |err| return mapParseError(err);
        validated.deinit();
        const backup_name = try backupFilenameAlloc(allocator, filename);
        defer allocator.free(backup_name);
        try atomicWrite(io, dir, backup_name, bytes);
    }

    const bytes = try review.serialize(allocator, value);
    defer allocator.free(bytes);
    // Validate our exact serialized bytes before replacing durable state.
    var validated_new = review.parse(allocator, bytes) catch |err| return mapParseError(err);
    validated_new.deinit();
    try atomicWrite(io, dir, filename, bytes);
}

fn atomicWrite(io: std.Io, dir: std.Io.Dir, filename: []const u8, bytes: []const u8) Error!void {
    var atomic = dir.createFileAtomic(io, filename, .{ .replace = true }) catch return error.WriteFailed;
    defer atomic.deinit(io);
    var buffer: [4096]u8 = undefined;
    var writer = atomic.file.writer(io, &buffer);
    writer.interface.writeAll(bytes) catch return error.WriteFailed;
    writer.flush() catch return error.WriteFailed;
    atomic.file.sync(io) catch return error.WriteFailed;
    atomic.replace(io) catch return error.WriteFailed;
}

pub fn remove(io: std.Io, repo_dir: std.Io.Dir, filename: []const u8) Error!void {
    var dir = repo_dir.openDir(io, directory_name, .{}) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return error.WriteFailed,
    };
    defer dir.close(io);
    dir.deleteFile(io, filename) catch |err| switch (err) {
        error.FileNotFound => {},
        else => return error.WriteFailed,
    };
    const backup = backupFilenameAlloc(std.heap.page_allocator, filename) catch return;
    defer std.heap.page_allocator.free(backup);
    dir.deleteFile(io, backup) catch {};
}

fn backupFilenameAlloc(allocator: std.mem.Allocator, filename: []const u8) ![]u8 {
    const base = if (std.mem.endsWith(u8, filename, ".json")) filename[0 .. filename.len - ".json".len] else filename;
    return std.fmt.allocPrint(allocator, "{s}.bak", .{base});
}

fn openOrCreateDir(io: std.Io, repo_dir: std.Io.Dir) Error!std.Io.Dir {
    return repo_dir.openDir(io, directory_name, .{}) catch
        repo_dir.createDirPathOpen(io, directory_name, .{}) catch error.WriteFailed;
}

const testing = std.testing;

fn sampleReview(body: []const u8) review.Review {
    const Static = struct {
        var comments: [1]review.Comment = undefined;
        var threads: [1]review.Thread = undefined;
    };
    Static.comments[0] = .{ .author = .reviewer, .body = body };
    Static.threads[0] = .{
        .id = "t1",
        .path = "src/main.zig",
        .group = .staged,
        .status = .open,
        .lifecycle = .open,
        .validity = .current,
        .context = .{ .bytes = "change\n", .original_start = 0, .target_start = 0, .target_end = 6 },
        .comments = &Static.comments,
    };
    return .{ .allocator = testing.allocator, .base_ref = "HEAD", .base_sha = "abc", .created = "now", .threads = &Static.threads };
}

test "save and load v1 review" {
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try save(testing.allocator, testing.io, tmp.dir, "review.json", sampleReview("first"));
    var loaded = try loadAll(testing.allocator, testing.io, tmp.dir);
    defer loaded.deinit();
    try testing.expectEqual(@as(usize, 1), loaded.entries.len);
    try testing.expectEqualStrings("first", loaded.entries[0].review.threads[0].comments[0].body);
}

test "loadOne ignores unrelated review files" {
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try save(testing.allocator, testing.io, tmp.dir, "wanted.json", sampleReview("wanted"));
    var dir = try tmp.dir.openDir(testing.io, directory_name, .{});
    defer dir.close(testing.io);
    try dir.writeFile(testing.io, .{
        .sub_path = "unrelated.json",
        .data = "{\"schema\":\"fiew.review/v2\",\"data\":{}}",
    });
    var loaded = try loadOne(testing.allocator, testing.io, tmp.dir, "wanted.json");
    defer loaded.deinit();
    try testing.expectEqualStrings("wanted", loaded.entries[0].review.threads[0].comments[0].body);
}

test "current review pointer is explicit atomic and validated" {
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try testing.expectError(error.CurrentReviewMissing, currentId(testing.allocator, testing.io, tmp.dir));
    const first = "20260828-120000-first";
    const second = "20260828-120001-second";
    try save(testing.allocator, testing.io, tmp.dir, "20260828-120000-first.json", sampleReview("first"));
    try save(testing.allocator, testing.io, tmp.dir, "20260828-120001-second.json", sampleReview("second"));
    try setCurrent(testing.allocator, testing.io, tmp.dir, first);
    const current_first = try currentId(testing.allocator, testing.io, tmp.dir);
    defer testing.allocator.free(current_first);
    try testing.expectEqualStrings(first, current_first);
    try setCurrent(testing.allocator, testing.io, tmp.dir, second);
    const current_second = try currentId(testing.allocator, testing.io, tmp.dir);
    defer testing.allocator.free(current_second);
    try testing.expectEqualStrings(second, current_second);

    var dir = try tmp.dir.openDir(testing.io, directory_name, .{});
    defer dir.close(testing.io);
    try dir.writeFile(testing.io, .{ .sub_path = current_filename, .data = "not-an-id\n" });
    try testing.expectError(error.CurrentReviewMalformed, currentId(testing.allocator, testing.io, tmp.dir));
    try dir.writeFile(testing.io, .{ .sub_path = current_filename, .data = "20260828-120002-missing\n" });
    try testing.expectError(error.CurrentReviewDangling, currentId(testing.allocator, testing.io, tmp.dir));
    try testing.expectError(error.CurrentReviewDangling, setCurrent(testing.allocator, testing.io, tmp.dir, "20260828-120002-missing"));
}

test "one validated backup recovers a malformed primary" {
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try save(testing.allocator, testing.io, tmp.dir, "review.json", sampleReview("first"));
    try save(testing.allocator, testing.io, tmp.dir, "review.json", sampleReview("second"));
    var dir = try tmp.dir.openDir(testing.io, directory_name, .{});
    defer dir.close(testing.io);
    try dir.writeFile(testing.io, .{ .sub_path = "review.json", .data = "broken" });
    var loaded = try loadAll(testing.allocator, testing.io, tmp.dir);
    defer loaded.deinit();
    try testing.expectEqualStrings("first", loaded.entries[0].review.threads[0].comments[0].body);
    try testing.expect(loaded.entries[0].recovered);
    const repaired = try dir.readFileAlloc(testing.io, "review.json", testing.allocator, .unlimited);
    defer testing.allocator.free(repaired);
    var validated = try review.parse(testing.allocator, repaired);
    validated.deinit();
}

test "legacy Markdown reviews are rejected" {
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var dir = try tmp.dir.createDirPathOpen(testing.io, directory_name, .{});
    defer dir.close(testing.io);
    try dir.writeFile(testing.io, .{ .sub_path = "legacy.md", .data = "---\nschema: fiew.review/v1\n---\n" });
    try testing.expectError(error.UnsupportedLegacyReview, loadAll(testing.allocator, testing.io, tmp.dir));
    try testing.expectError(error.UnsupportedLegacyReview, loadOne(testing.allocator, testing.io, tmp.dir, "legacy.json"));
}

test "future schema is refused and not overwritten" {
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var dir = try tmp.dir.createDirPathOpen(testing.io, directory_name, .{});
    defer dir.close(testing.io);
    const future = "{\"schema\":\"fiew.review/v2\",\"data\":{}}";
    try dir.writeFile(testing.io, .{ .sub_path = "review.json", .data = future });
    try testing.expectError(error.FutureSchema, loadAll(testing.allocator, testing.io, tmp.dir));
    try testing.expectError(error.FutureSchema, loadOne(testing.allocator, testing.io, tmp.dir, "review.json"));
    try testing.expectError(error.FutureSchema, save(testing.allocator, testing.io, tmp.dir, "review.json", sampleReview("no")));
    const after = try dir.readFileAlloc(testing.io, "review.json", testing.allocator, .unlimited);
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(future, after);
}
