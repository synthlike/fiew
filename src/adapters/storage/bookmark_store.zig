//! Durable repository-local private bookmark storage.

const std = @import("std");
const bookmark = @import("../../model/bookmark.zig");

pub const directory_name = ".bookmarks";
pub const filename = "bookmarks.json";
pub const backup_filename = "bookmarks.bak";
pub const max_bytes: usize = 4 << 20;

pub const Error = std.mem.Allocator.Error || error{
    ReadFailed,
    WriteFailed,
    MalformedBookmarks,
    InvalidSchema,
    FutureSchema,
};

pub const Source = enum { primary, backup };

pub const Loaded = struct {
    parsed: bookmark.Parsed,
    source: Source,

    pub fn value(self: *const Loaded) *const bookmark.Stored {
        return self.parsed.value();
    }

    pub fn deinit(self: Loaded) void {
        self.parsed.deinit();
    }
};

pub const LoadResult = union(enum) {
    loaded: Loaded,
    absent,
    future_schema,
    unrecoverable,
};

pub fn load(allocator: std.mem.Allocator, io: std.Io, repo_dir: std.Io.Dir) Error!LoadResult {
    var dir = repo_dir.openDir(io, directory_name, .{}) catch |err| switch (err) {
        error.FileNotFound => return .absent,
        else => return error.ReadFailed,
    };
    defer dir.close(io);
    const primary = dir.readFileAlloc(io, filename, allocator, .limited64(max_bytes)) catch |err| switch (err) {
        error.FileNotFound => return .absent,
        else => return error.ReadFailed,
    };
    defer allocator.free(primary);
    var recovered = false;
    var parsed = bookmark.parse(allocator, primary) catch |primary_err| switch (primary_err) {
        error.FutureSchema => return .future_schema,
        error.OutOfMemory => return error.OutOfMemory,
        else => blk: {
            const backup = dir.readFileAlloc(io, backup_filename, allocator, .limited64(max_bytes)) catch
                return .unrecoverable;
            defer allocator.free(backup);
            const recovered_parsed = bookmark.parse(allocator, backup) catch |backup_err| switch (backup_err) {
                error.FutureSchema => return .future_schema,
                error.OutOfMemory => return error.OutOfMemory,
                else => return .unrecoverable,
            };
            errdefer recovered_parsed.deinit();
            try atomicWrite(io, dir, filename, backup);
            recovered = true;
            break :blk recovered_parsed;
        },
    };
    errdefer parsed.deinit();
    return .{ .loaded = .{ .parsed = parsed, .source = if (recovered) .backup else .primary } };
}

pub fn save(allocator: std.mem.Allocator, io: std.Io, repo_dir: std.Io.Dir, value: bookmark.Stored) Error!void {
    var dir = repo_dir.openDir(io, directory_name, .{}) catch
        repo_dir.createDirPathOpen(io, directory_name, .{}) catch return error.WriteFailed;
    defer dir.close(io);

    const previous = dir.readFileAlloc(io, filename, allocator, .limited64(max_bytes)) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return error.ReadFailed,
    };
    defer if (previous) |bytes| allocator.free(bytes);
    if (previous) |bytes| {
        const validated = bookmark.parse(allocator, bytes) catch |err| return mapParseError(err);
        validated.deinit();
        try atomicWrite(io, dir, backup_filename, bytes);
    }

    const bytes = try bookmark.serialize(allocator, value);
    defer allocator.free(bytes);
    const validated = bookmark.parse(allocator, bytes) catch |err| return mapParseError(err);
    validated.deinit();
    try atomicWrite(io, dir, filename, bytes);
}

fn mapParseError(err: anyerror) Error {
    return switch (err) {
        error.FutureSchema => error.FutureSchema,
        error.InvalidSchema => error.InvalidSchema,
        error.OutOfMemory => error.OutOfMemory,
        else => error.MalformedBookmarks,
    };
}

fn atomicWrite(io: std.Io, dir: std.Io.Dir, name: []const u8, bytes: []const u8) Error!void {
    var atomic = dir.createFileAtomic(io, name, .{ .replace = true }) catch return error.WriteFailed;
    defer atomic.deinit(io);
    var buffer: [4096]u8 = undefined;
    var writer = atomic.file.writer(io, &buffer);
    writer.interface.writeAll(bytes) catch return error.WriteFailed;
    writer.flush() catch return error.WriteFailed;
    atomic.file.sync(io) catch return error.WriteFailed;
    atomic.replace(io) catch return error.WriteFailed;
}

const testing = std.testing;

test "bookmark files are isolated to their repository directory" {
    var first_repo = testing.tmpDir(.{ .iterate = true });
    defer first_repo.cleanup();
    var second_repo = testing.tmpDir(.{ .iterate = true });
    defer second_repo.cleanup();
    try first_repo.dir.writeFile(testing.io, .{ .sub_path = "source.zig", .data = "const value = 1;\n" });
    const items = [_]bookmark.Bookmark{.{ .id = 1, .path = "source.zig", .line = 1, .column = 0, .source_offset = 0, .label = "private" }};
    try save(testing.allocator, testing.io, first_repo.dir, .{ .next_id = 2, .bookmarks = &items });
    const second = try load(testing.allocator, testing.io, second_repo.dir);
    try testing.expectEqual(std.meta.Tag(LoadResult).absent, std.meta.activeTag(second));
    const source = try first_repo.dir.readFileAlloc(testing.io, "source.zig", testing.allocator, .unlimited);
    defer testing.allocator.free(source);
    try testing.expectEqualStrings("const value = 1;\n", source);
    try first_repo.dir.access(testing.io, ".bookmarks/bookmarks.json", .{});
}

test "repository-local bookmark state recovers backup and refuses future schema" {
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    const first = [_]bookmark.Bookmark{.{ .id = 1, .path = "a.zig", .line = 1, .column = 0, .source_offset = 0, .label = "first" }};
    const second = [_]bookmark.Bookmark{.{ .id = 2, .path = "b.zig", .line = 2, .column = 0, .source_offset = 2, .label = "second" }};
    try save(testing.allocator, testing.io, tmp.dir, .{ .next_id = 2, .bookmarks = &first });
    try save(testing.allocator, testing.io, tmp.dir, .{ .next_id = 3, .bookmarks = &second });
    var dir = try tmp.dir.openDir(testing.io, directory_name, .{});
    defer dir.close(testing.io);
    try dir.writeFile(testing.io, .{ .sub_path = filename, .data = "broken" });
    var recovered = try load(testing.allocator, testing.io, tmp.dir);
    switch (recovered) {
        .loaded => |*value| {
            defer value.deinit();
            try testing.expectEqualStrings("first", value.value().bookmarks[0].label);
            try testing.expectEqual(Source.backup, value.source);
        },
        else => return error.TestUnexpectedResult,
    }

    const future = "{\"schema\":\"fiew.bookmark/v2\",\"data\":{}}";
    try dir.writeFile(testing.io, .{ .sub_path = filename, .data = future });
    try testing.expectError(error.FutureSchema, save(testing.allocator, testing.io, tmp.dir, .{}));
    const after = try dir.readFileAlloc(testing.io, filename, testing.allocator, .unlimited);
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(future, after);
}
