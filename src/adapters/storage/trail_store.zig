//! Durable one-file-per-Trail private storage under `.trails/`.

const std = @import("std");
const trail = @import("../../model/trail.zig");

pub const directory_name = ".trails";
pub const max_bytes: usize = 4 << 20;
pub const max_artifacts: usize = 4096;
pub const Error = std.mem.Allocator.Error || error{ ReadFailed, WriteFailed, MalformedTrail, InvalidSchema, FutureSchema, InvalidTrail, InvalidReview, TooManyTrails };

pub const Entry = struct {
    parsed: trail.Parsed,
    recovered: bool,
};

pub const Loaded = struct {
    allocator: std.mem.Allocator,
    entries: []Entry,
    future_count: usize = 0,
    unrecoverable_count: usize = 0,

    pub fn deinit(self: *Loaded) void {
        for (self.entries) |entry| entry.parsed.deinit();
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
        for (entries.items) |entry| entry.parsed.deinit();
        entries.deinit(allocator);
    }
    var future_count: usize = 0;
    var unrecoverable_count: usize = 0;
    var walker = dir.walk(allocator) catch return error.ReadFailed;
    defer walker.deinit();
    while (walker.next(io) catch return error.ReadFailed) |walked| {
        if (walked.kind != .file or !std.mem.endsWith(u8, walked.basename, ".json")) continue;
        if (entries.items.len + future_count + unrecoverable_count >= max_artifacts) return error.TooManyTrails;
        var entry = loadEntry(allocator, io, dir, walked.basename) catch |err| switch (err) {
            error.FutureSchema => {
                future_count += 1;
                continue;
            },
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                unrecoverable_count += 1;
                continue;
            },
        };
        entries.append(allocator, entry) catch |err| {
            entry.parsed.deinit();
            return err;
        };
    }
    return .{ .allocator = allocator, .entries = try entries.toOwnedSlice(allocator), .future_count = future_count, .unrecoverable_count = unrecoverable_count };
}

fn loadEntry(allocator: std.mem.Allocator, io: std.Io, dir: std.Io.Dir, filename: []const u8) Error!Entry {
    const primary = dir.readFileAlloc(io, filename, allocator, .limited64(max_bytes)) catch return error.ReadFailed;
    defer allocator.free(primary);
    var recovered = false;
    var parsed = trail.parse(allocator, primary) catch |primary_err| switch (primary_err) {
        error.FutureSchema => return error.FutureSchema,
        error.OutOfMemory => return error.OutOfMemory,
        else => blk: {
            const backup_name = try std.fmt.allocPrint(allocator, "{s}.bak", .{filename});
            defer allocator.free(backup_name);
            const backup = dir.readFileAlloc(io, backup_name, allocator, .limited64(max_bytes)) catch return mapParse(primary_err);
            defer allocator.free(backup);
            const recovered_parsed = trail.parse(allocator, backup) catch |backup_err| return mapParse(backup_err);
            errdefer recovered_parsed.deinit();
            if (!filenameMatches(filename, recovered_parsed.value().id)) return error.InvalidTrail;
            try atomicWrite(io, dir, filename, backup);
            recovered = true;
            break :blk recovered_parsed;
        },
    };
    errdefer parsed.deinit();
    if (!filenameMatches(filename, parsed.value().id)) return error.InvalidTrail;
    return .{ .parsed = parsed, .recovered = recovered };
}

pub fn save(allocator: std.mem.Allocator, io: std.Io, repo_dir: std.Io.Dir, value: trail.Trail) Error!void {
    if (!trail.validId(value.id)) return error.InvalidTrail;
    const filename = try filenameAlloc(allocator, value.id);
    defer allocator.free(filename);
    const backup_name = try std.fmt.allocPrint(allocator, "{s}.bak", .{filename});
    defer allocator.free(backup_name);
    const bytes = try trail.serialize(allocator, value);
    defer allocator.free(bytes);
    const serialized = trail.parse(allocator, bytes) catch |err| return mapParse(err);
    serialized.deinit();

    var dir = repo_dir.openDir(io, directory_name, .{}) catch repo_dir.createDirPathOpen(io, directory_name, .{}) catch return error.WriteFailed;
    defer dir.close(io);

    const previous = dir.readFileAlloc(io, filename, allocator, .limited64(max_bytes)) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return error.ReadFailed,
    };
    defer if (previous) |previous_bytes| allocator.free(previous_bytes);
    if (previous) |previous_bytes| {
        const validated = trail.parse(allocator, previous_bytes) catch |err| return mapParse(err);
        defer validated.deinit();
        if (!std.mem.eql(u8, validated.value().id, value.id)) return error.InvalidTrail;
        if (!std.mem.eql(u8, validated.value().owner.review, value.owner.review)) return error.InvalidReview;
        try atomicWrite(io, dir, backup_name, previous_bytes);
    }

    try atomicWrite(io, dir, filename, bytes);
}

pub fn delete(allocator: std.mem.Allocator, io: std.Io, repo_dir: std.Io.Dir, id: []const u8, review: []const u8) Error!void {
    if (!trail.validId(id)) return error.InvalidTrail;
    const filename = try filenameAlloc(allocator, id);
    defer allocator.free(filename);
    const backup_name = try std.fmt.allocPrint(allocator, "{s}.bak", .{filename});
    defer allocator.free(backup_name);
    var dir = repo_dir.openDir(io, directory_name, .{}) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return error.ReadFailed,
    };
    defer dir.close(io);
    const bytes = dir.readFileAlloc(io, filename, allocator, .limited64(max_bytes)) catch |err| switch (err) {
        error.FileNotFound => return,
        else => return error.ReadFailed,
    };
    defer allocator.free(bytes);
    const parsed = trail.parse(allocator, bytes) catch |err| return mapParse(err);
    defer parsed.deinit();
    if (!std.mem.eql(u8, parsed.value().id, id)) return error.InvalidTrail;
    if (!std.mem.eql(u8, parsed.value().owner.review, review)) return error.InvalidReview;
    // Remove the optional backup first so a partial failure always leaves the
    // canonical artifact visible and retryable.
    dir.deleteFile(io, backup_name) catch |err| if (err != error.FileNotFound) return error.WriteFailed;
    dir.deleteFile(io, filename) catch return error.WriteFailed;
}

fn filenameAlloc(allocator: std.mem.Allocator, id: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}.json", .{id});
}

fn filenameMatches(filename: []const u8, id: []const u8) bool {
    return filename.len == id.len + ".json".len and std.mem.eql(u8, filename[0..id.len], id) and std.mem.eql(u8, filename[id.len..], ".json");
}

fn mapParse(err: anyerror) Error {
    return switch (err) {
        error.FutureSchema => error.FutureSchema,
        error.InvalidSchema => error.InvalidSchema,
        error.OutOfMemory => error.OutOfMemory,
        else => error.MalformedTrail,
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
const test_id = "0123456789abcdef0123456789abcdef";
const other_id = "fedcba9876543210fedcba9876543210";

fn testTrail(id: []const u8, review: []const u8, title: []const u8) trail.Trail {
    const points = &[_]trail.Point{
        .{ .path = "a", .line = 1, .source_offset = 0, .line_offset = 0, .content = "a", .context = .{ .bytes = "a\n", .original_start = 0, .target_start = 0, .target_end = 1 } },
        .{ .path = "b", .line = 1, .source_offset = 0, .line_offset = 0, .content = "b", .context = .{ .bytes = "b\n", .original_start = 0, .target_start = 0, .target_end = 1 } },
    };
    return .{ .id = id, .owner = .{ .review = review }, .title = title, .points = points };
}

test "standalone Trails isolate reviews, corruption, update, recovery, and deletion" {
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try save(testing.allocator, testing.io, tmp.dir, testTrail(test_id, "review-a.json", "First"));
    try save(testing.allocator, testing.io, tmp.dir, testTrail(other_id, "review-b.json", "Other"));
    try save(testing.allocator, testing.io, tmp.dir, testTrail(other_id, "review-b.json", "Other updated"));
    try save(testing.allocator, testing.io, tmp.dir, testTrail(test_id, "review-a.json", "Updated"));
    try tmp.dir.writeFile(testing.io, .{ .sub_path = ".trails/fedcba9876543210fedcba9876543210.json", .data = "broken" });
    var loaded = try loadAll(testing.allocator, testing.io, tmp.dir);
    defer loaded.deinit();
    try testing.expectEqual(@as(usize, 2), loaded.entries.len);
    try testing.expectEqual(@as(usize, 0), loaded.unrecoverable_count);
    var recovered = false;
    for (loaded.entries) |entry| {
        if (std.mem.eql(u8, entry.parsed.value().id, other_id)) recovered = entry.recovered;
    }
    try testing.expect(recovered);
    try delete(testing.allocator, testing.io, tmp.dir, test_id, "review-a.json");
    try testing.expectError(error.FileNotFound, tmp.dir.access(testing.io, ".trails/0123456789abcdef0123456789abcdef.json", .{}));
}

test "standalone Trails do not change canonical Review bytes or projections" {
    const review = @import("../../model/review.zig");
    const review_store = @import("review_store.zig");
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    const canonical = try review.serialize(testing.allocator, .{ .allocator = undefined, .base_ref = "HEAD", .base_sha = "abc", .created = "2026-08-29T00:00:00Z", .threads = &.{} });
    defer testing.allocator.free(canonical);
    try tmp.dir.createDirPath(testing.io, ".reviews");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = ".reviews/review.json", .data = canonical });
    try save(testing.allocator, testing.io, tmp.dir, testTrail(test_id, "review.json", "Private"));
    const after = try tmp.dir.readFileAlloc(testing.io, ".reviews/review.json", testing.allocator, .unlimited);
    defer testing.allocator.free(after);
    try testing.expectEqualStrings(canonical, after);
    var projected = try review_store.loadAll(testing.allocator, testing.io, tmp.dir);
    defer projected.deinit();
    try testing.expectEqual(@as(usize, 1), projected.entries.len);
    try testing.expectEqual(@as(usize, 0), projected.entries[0].review.threads.len);
}

test "malformed and future standalone Trails do not hide valid artifacts or inspect companions" {
    var tmp = testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try save(testing.allocator, testing.io, tmp.dir, testTrail(test_id, "review.json", "Valid"));
    var dir = try tmp.dir.openDir(testing.io, directory_name, .{});
    defer dir.close(testing.io);
    try dir.writeFile(testing.io, .{ .sub_path = "11111111111111111111111111111111.json", .data = "broken" });
    try dir.writeFile(testing.io, .{ .sub_path = "22222222222222222222222222222222.json", .data = "{\"schema\":\"skaut.trail/v2\",\"data\":{}}" });
    try tmp.dir.createDirPath(testing.io, ".reviews");
    try tmp.dir.writeFile(testing.io, .{ .sub_path = ".reviews/review.json.trails", .data = "legacy development companion" });
    var loaded = try loadAll(testing.allocator, testing.io, tmp.dir);
    defer loaded.deinit();
    try testing.expectEqual(@as(usize, 1), loaded.entries.len);
    try testing.expectEqual(@as(usize, 1), loaded.unrecoverable_count);
    try testing.expectEqual(@as(usize, 1), loaded.future_count);
}
