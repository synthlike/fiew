//! Reads and writes review files under the repository's `.reviews/` directory
//! (ARP-0006). This is the only place fiew writes inside a repository, and it
//! writes nowhere else: never `.gitignore`, tracked files, or Git metadata.
//! Writes are atomic (same-directory temp + rename).

const std = @import("std");
const review = @import("../../model/review.zig");

pub const directory_name = ".reviews";
/// Upper bound on a single review file we will read.
pub const max_review_bytes: usize = 4 << 20;

pub const Error = std.mem.Allocator.Error || error{WriteFailed};

/// One loaded review paired with the file it came from.
pub const Entry = struct {
    filename: []u8,
    review: review.Review,
};

/// All reviews loaded from `.reviews/`, owned together.
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

/// Read and parse every `*.md` file in `<repo>/.reviews/`. A missing directory
/// yields no entries; a malformed file is skipped rather than failing the load.
pub fn loadAll(
    allocator: std.mem.Allocator,
    io: std.Io,
    repo_dir: std.Io.Dir,
) !Loaded {
    var dir = repo_dir.openDir(io, directory_name, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return .{ .allocator = allocator, .entries = &.{} },
        else => return error.OutOfMemory,
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

    var walker = try dir.walk(allocator);
    defer walker.deinit();
    while (walker.next(io) catch null) |walked| {
        if (walked.kind != .file) continue;
        if (!std.mem.endsWith(u8, walked.basename, ".md")) continue;
        const bytes = dir.readFileAlloc(io, walked.path, allocator, .limited64(max_review_bytes)) catch continue;
        defer allocator.free(bytes);
        var parsed = review.parse(allocator, bytes) catch continue;
        errdefer parsed.deinit();
        const filename = try allocator.dupe(u8, walked.basename);
        try entries.append(allocator, .{ .filename = filename, .review = parsed });
    }

    return .{ .allocator = allocator, .entries = try entries.toOwnedSlice(allocator) };
}

/// Atomically write one review to `<repo>/.reviews/<filename>`, creating the
/// directory on first use.
pub fn save(
    allocator: std.mem.Allocator,
    io: std.Io,
    repo_dir: std.Io.Dir,
    filename: []const u8,
    value: review.Review,
) Error!void {
    var dir = try openOrCreateDir(io, repo_dir);
    defer dir.close(io);

    const bytes = try review.serialize(allocator, value);
    defer allocator.free(bytes);

    var atomic = dir.createFileAtomic(io, filename, .{ .replace = true }) catch return error.WriteFailed;
    defer atomic.deinit(io);
    var buffer: [4096]u8 = undefined;
    var writer = atomic.file.writer(io, &buffer);
    writer.interface.writeAll(bytes) catch return error.WriteFailed;
    writer.flush() catch return error.WriteFailed;
    atomic.file.sync(io) catch {};
    atomic.replace(io) catch return error.WriteFailed;
}

/// Remove a review file. A missing file is not an error.
pub fn remove(io: std.Io, repo_dir: std.Io.Dir, filename: []const u8) void {
    var dir = repo_dir.openDir(io, directory_name, .{}) catch return;
    defer dir.close(io);
    dir.deleteFile(io, filename) catch {};
}

fn openOrCreateDir(io: std.Io, repo_dir: std.Io.Dir) Error!std.Io.Dir {
    return repo_dir.openDir(io, directory_name, .{}) catch
        repo_dir.createDirPathOpen(io, directory_name, .{}) catch error.WriteFailed;
}

// --- Tests ---------------------------------------------------------------

const testing = std.testing;

fn sampleReview() review.Review {
    const Static = struct {
        var notes = [_]review.Note{.{
            .id = "n1",
            .path = "src/main.zig",
            .group = .staged,
            .status = .open,
            .side = .new,
            .start_line = 3,
            .end_line = 3,
            .blob = "abc123",
            .excerpt = "@@ -2,1 +3,1 @@\n+const x = 1;",
            .body = "Consider a comptime constant here.",
        }};
    };
    return .{
        .allocator = testing.allocator,
        .base_ref = "HEAD",
        .base_sha = "0f1e2d3",
        .created = "2026-08-27T12:00:00Z",
        .notes = &Static.notes,
    };
}

test "save writes into .reviews and load reads it back" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    try save(testing.allocator, std.testing.io, tmp.dir, "review-1.md", sampleReview());

    // The file lands under .reviews/, nowhere else.
    var reviews_dir = try tmp.dir.openDir(std.testing.io, directory_name, .{});
    reviews_dir.close(std.testing.io);

    var loaded = try loadAll(testing.allocator, std.testing.io, tmp.dir);
    defer loaded.deinit();
    try testing.expectEqual(@as(usize, 1), loaded.entries.len);
    try testing.expectEqualStrings("review-1.md", loaded.entries[0].filename);
    const note = loaded.entries[0].review.notes[0];
    try testing.expectEqualStrings("src/main.zig", note.path);
    try testing.expectEqualStrings("abc123", note.blob.?);
    try testing.expectEqualStrings("Consider a comptime constant here.", note.body);
}

test "loadAll on a repo without .reviews yields nothing" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    var loaded = try loadAll(testing.allocator, std.testing.io, tmp.dir);
    defer loaded.deinit();
    try testing.expectEqual(@as(usize, 0), loaded.entries.len);
}

test "remove deletes a review file" {
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try save(testing.allocator, std.testing.io, tmp.dir, "review-1.md", sampleReview());
    remove(std.testing.io, tmp.dir, "review-1.md");
    var loaded = try loadAll(testing.allocator, std.testing.io, tmp.dir);
    defer loaded.deinit();
    try testing.expectEqual(@as(usize, 0), loaded.entries.len);
}
