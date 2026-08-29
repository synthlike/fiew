//! Durable review-keyed private Trail companion storage under `.reviews/`.

const std = @import("std");
const trail = @import("../../model/trail.zig");

pub const max_bytes: usize = 4 << 20;
pub const Error = std.mem.Allocator.Error || error{ ReadFailed, WriteFailed, MalformedTrails, InvalidSchema, FutureSchema, InvalidReview };
pub const Source = enum { primary, backup };
pub const Loaded = struct {
    parsed: trail.Parsed,
    source: Source,
    pub fn value(self: *const Loaded) *const trail.Stored {
        return self.parsed.value();
    }
    pub fn deinit(self: Loaded) void {
        self.parsed.deinit();
    }
};
pub const LoadResult = union(enum) { loaded: Loaded, absent, future_schema, unrecoverable };

fn names(allocator: std.mem.Allocator, review: []const u8) Error!struct { primary: []u8, backup: []u8 } {
    if (review.len == 0 or !std.mem.eql(u8, std.fs.path.basename(review), review)) return error.InvalidReview;
    const primary = try std.fmt.allocPrint(allocator, "{s}.trails", .{review});
    errdefer allocator.free(primary);
    return .{ .primary = primary, .backup = try std.fmt.allocPrint(allocator, "{s}.trails.bak", .{review}) };
}

pub fn load(allocator: std.mem.Allocator, io: std.Io, repo_dir: std.Io.Dir, review: []const u8) Error!LoadResult {
    const file_names = try names(allocator, review);
    defer allocator.free(file_names.primary);
    defer allocator.free(file_names.backup);
    var dir = repo_dir.openDir(io, ".reviews", .{}) catch |err| switch (err) {
        error.FileNotFound => return .absent,
        else => return error.ReadFailed,
    };
    defer dir.close(io);
    const primary = dir.readFileAlloc(io, file_names.primary, allocator, .limited64(max_bytes)) catch |err| switch (err) {
        error.FileNotFound => return .absent,
        else => return error.ReadFailed,
    };
    defer allocator.free(primary);
    var recovered = false;
    var parsed = trail.parse(allocator, primary) catch |primary_err| switch (primary_err) {
        error.FutureSchema => return .future_schema,
        error.OutOfMemory => return error.OutOfMemory,
        else => blk: {
            const backup = dir.readFileAlloc(io, file_names.backup, allocator, .limited64(max_bytes)) catch return .unrecoverable;
            defer allocator.free(backup);
            const recovered_parsed = trail.parse(allocator, backup) catch |backup_err| switch (backup_err) {
                error.FutureSchema => return .future_schema,
                error.OutOfMemory => return error.OutOfMemory,
                else => return .unrecoverable,
            };
            errdefer recovered_parsed.deinit();
            if (!std.mem.eql(u8, recovered_parsed.value().review, review)) {
                recovered_parsed.deinit();
                return .unrecoverable;
            }
            try atomicWrite(io, dir, file_names.primary, backup);
            recovered = true;
            break :blk recovered_parsed;
        },
    };
    errdefer parsed.deinit();
    if (!std.mem.eql(u8, parsed.value().review, review)) {
        parsed.deinit();
        return .unrecoverable;
    }
    return .{ .loaded = .{ .parsed = parsed, .source = if (recovered) .backup else .primary } };
}

pub fn save(allocator: std.mem.Allocator, io: std.Io, repo_dir: std.Io.Dir, review: []const u8, value: trail.Stored) Error!void {
    if (!std.mem.eql(u8, review, value.review)) return error.InvalidReview;
    const file_names = try names(allocator, review);
    defer allocator.free(file_names.primary);
    defer allocator.free(file_names.backup);
    var dir = repo_dir.openDir(io, ".reviews", .{}) catch repo_dir.createDirPathOpen(io, ".reviews", .{}) catch return error.WriteFailed;
    defer dir.close(io);
    const previous = dir.readFileAlloc(io, file_names.primary, allocator, .limited64(max_bytes)) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return error.ReadFailed,
    };
    defer if (previous) |bytes| allocator.free(bytes);
    if (previous) |bytes| {
        const validated = trail.parse(allocator, bytes) catch |err| return mapParse(err);
        if (!std.mem.eql(u8, validated.value().review, review)) {
            validated.deinit();
            return error.InvalidReview;
        }
        validated.deinit();
        try atomicWrite(io, dir, file_names.backup, bytes);
    }
    const bytes = try trail.serialize(allocator, value);
    defer allocator.free(bytes);
    const validated = trail.parse(allocator, bytes) catch |err| return mapParse(err);
    validated.deinit();
    try atomicWrite(io, dir, file_names.primary, bytes);
}

fn mapParse(err: anyerror) Error {
    return switch (err) {
        error.FutureSchema => error.FutureSchema,
        error.InvalidSchema => error.InvalidSchema,
        error.OutOfMemory => error.OutOfMemory,
        else => error.MalformedTrails,
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

test "Trail companions remain outside canonical review projections" {
    const review = @import("../../model/review.zig");
    const review_store = @import("review_store.zig");
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    const canonical = try review.serialize(std.testing.allocator, .{ .allocator = undefined, .base_ref = "HEAD", .base_sha = "abc", .created = "2026-08-29T00:00:00Z", .threads = &.{} });
    defer std.testing.allocator.free(canonical);
    var reviews = try tmp.dir.createDirPathOpen(std.testing.io, ".reviews", .{});
    defer reviews.close(std.testing.io);
    try reviews.writeFile(std.testing.io, .{ .sub_path = "20260829-120000-review.json", .data = canonical });
    const points = [_]trail.Point{
        .{ .path = "a", .line = 1, .source_offset = 0, .line_offset = 0, .content = "a", .context = .{ .bytes = "a\n", .original_start = 0, .target_start = 0, .target_end = 1 } },
        .{ .path = "b", .line = 1, .source_offset = 0, .line_offset = 0, .content = "b", .context = .{ .bytes = "b\n", .original_start = 0, .target_start = 0, .target_end = 1 } },
    };
    const items = [_]trail.Trail{.{ .id = 1, .title = "Private path", .points = &points }};
    try save(std.testing.allocator, std.testing.io, tmp.dir, "20260829-120000-review.json", .{ .review = "20260829-120000-review.json", .next_id = 2, .trails = &items });
    var projected = try review_store.loadAll(std.testing.allocator, std.testing.io, tmp.dir);
    defer projected.deinit();
    try std.testing.expectEqual(@as(usize, 1), projected.entries.len);
    try std.testing.expectEqual(@as(usize, 0), projected.entries[0].review.threads.len);
}

test "Trail companion is review keyed, recoverable, and does not change review JSON" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var reviews = try tmp.dir.createDirPathOpen(std.testing.io, ".reviews", .{});
    reviews.close(std.testing.io);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = ".reviews/review.json", .data = "review bytes" });
    const points = [_]trail.Point{
        .{ .path = "a", .line = 1, .source_offset = 0, .line_offset = 0, .content = "a", .context = .{ .bytes = "a\n", .original_start = 0, .target_start = 0, .target_end = 1 } },
        .{ .path = "b", .line = 1, .source_offset = 0, .line_offset = 0, .content = "b", .context = .{ .bytes = "b\n", .original_start = 0, .target_start = 0, .target_end = 1 } },
    };
    const items = [_]trail.Trail{.{ .id = 1, .title = "Path", .points = &points }};
    try save(std.testing.allocator, std.testing.io, tmp.dir, "review.json", .{ .review = "review.json", .next_id = 2, .trails = &items });
    var loaded = try load(std.testing.allocator, std.testing.io, tmp.dir, "review.json");
    switch (loaded) {
        .loaded => |*value| {
            defer value.deinit();
            try std.testing.expectEqualStrings("Path", value.value().trails[0].title);
        },
        else => return error.TestUnexpectedResult,
    }
    const original = try tmp.dir.readFileAlloc(std.testing.io, ".reviews/review.json", std.testing.allocator, .unlimited);
    defer std.testing.allocator.free(original);
    try std.testing.expectEqualStrings("review bytes", original);

    const replacement = [_]trail.Trail{.{ .id = 2, .title = "Other path", .points = &points }};
    try save(std.testing.allocator, std.testing.io, tmp.dir, "review.json", .{ .review = "review.json", .next_id = 3, .trails = &replacement });
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = ".reviews/review.json.trails", .data = "broken" });
    var recovered = try load(std.testing.allocator, std.testing.io, tmp.dir, "review.json");
    switch (recovered) {
        .loaded => |*value| {
            defer value.deinit();
            try std.testing.expectEqual(Source.backup, value.source);
            try std.testing.expectEqualStrings("Path", value.value().trails[0].title);
        },
        else => return error.TestUnexpectedResult,
    }

    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = ".reviews/review.json.trails", .data = "{\"schema\":\"fiew.trail/v2\",\"data\":{}}" });
    try std.testing.expectEqual(std.meta.Tag(LoadResult).future_schema, std.meta.activeTag(try load(std.testing.allocator, std.testing.io, tmp.dir, "review.json")));
}
