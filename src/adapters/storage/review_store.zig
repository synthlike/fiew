//! Durable repository-local review storage. Primary and backup files are
//! validated `fiew.review/v1` Markdown; writes use same-directory atomic replace.

const std = @import("std");
const review = @import("../../model/review.zig");

pub const directory_name = ".reviews";
pub const max_review_bytes: usize = 4 << 20;

pub const Error = std.mem.Allocator.Error || error{
    ReadFailed,
    WriteFailed,
    MalformedReview,
    MissingField,
    InvalidSchema,
    FutureSchema,
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
        if (walked.kind != .file or !std.mem.endsWith(u8, walked.basename, ".md")) continue;
        const bytes = dir.readFileAlloc(io, walked.path, allocator, .limited64(max_review_bytes)) catch
            return error.ReadFailed;
        defer allocator.free(bytes);
        var recovered = false;
        var parsed = review.parse(allocator, bytes) catch |primary_err| switch (primary_err) {
            error.FutureSchema => return error.FutureSchema,
            error.OutOfMemory => return error.OutOfMemory,
            else => blk: {
                const backup_name = try std.fmt.allocPrint(allocator, "{s}.bak", .{walked.basename});
                defer allocator.free(backup_name);
                const backup = dir.readFileAlloc(io, backup_name, allocator, .limited64(max_review_bytes)) catch
                    return mapParseError(primary_err);
                defer allocator.free(backup);
                var recovered_review = review.parse(allocator, backup) catch |backup_err| return mapParseError(backup_err);
                errdefer recovered_review.deinit();
                try atomicWrite(io, dir, walked.basename, backup);
                recovered = true;
                break :blk recovered_review;
            },
        };
        errdefer parsed.deinit();
        const filename = try allocator.dupe(u8, walked.basename);
        try entries.append(allocator, .{
            .filename = filename,
            .review = parsed,
            .recovered = recovered,
        });
    }
    return .{ .allocator = allocator, .entries = try entries.toOwnedSlice(allocator) };
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
        const backup_name = try std.fmt.allocPrint(allocator, "{s}.bak", .{filename});
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
    var buffer: [std.fs.max_name_bytes]u8 = undefined;
    const backup = std.fmt.bufPrint(&buffer, "{s}.bak", .{filename}) catch return;
    dir.deleteFile(io, backup) catch {};
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
        .comments = &Static.comments,
    };
    return .{ .allocator = testing.allocator, .base_ref = "HEAD", .base_sha = "abc", .created = "now", .threads = &Static.threads };
}

test "save and load v1 review" {
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try save(testing.allocator, testing.io, tmp.dir, "review.md", sampleReview("first"));
    var loaded = try loadAll(testing.allocator, testing.io, tmp.dir);
    defer loaded.deinit();
    try testing.expectEqual(@as(usize, 1), loaded.entries.len);
    try testing.expectEqualStrings("first", loaded.entries[0].review.threads[0].comments[0].body);
}

test "one validated backup recovers a malformed primary" {
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try save(testing.allocator, testing.io, tmp.dir, "review.md", sampleReview("first"));
    try save(testing.allocator, testing.io, tmp.dir, "review.md", sampleReview("second"));
    var dir = try tmp.dir.openDir(testing.io, directory_name, .{});
    defer dir.close(testing.io);
    try dir.writeFile(testing.io, .{ .sub_path = "review.md", .data = "broken" });
    var loaded = try loadAll(testing.allocator, testing.io, tmp.dir);
    defer loaded.deinit();
    try testing.expectEqualStrings("first", loaded.entries[0].review.threads[0].comments[0].body);
    try testing.expect(loaded.entries[0].recovered);
    const repaired = try dir.readFileAlloc(testing.io, "review.md", testing.allocator, .unlimited);
    defer testing.allocator.free(repaired);
    var validated = try review.parse(testing.allocator, repaired);
    validated.deinit();
}

test "future schema is refused and not overwritten" {
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var dir = try tmp.dir.createDirPathOpen(testing.io, directory_name, .{});
    defer dir.close(testing.io);
    const future = "---\nschema: fiew.review/v2\ncreated: now\nbase: { ref: HEAD, sha: x }\n---\n";
    try dir.writeFile(testing.io, .{ .sub_path = "review.md", .data = future });
    try testing.expectError(error.FutureSchema, loadAll(testing.allocator, testing.io, tmp.dir));
    try testing.expectError(error.FutureSchema, save(testing.allocator, testing.io, tmp.dir, "review.md", sampleReview("no")));
    const after = try dir.readFileAlloc(testing.io, "review.md", testing.allocator, .unlimited);
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(future, after);
}
