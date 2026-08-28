//! Read-only enumeration of paths visible to Git: tracked files plus untracked
//! files that are not excluded by standard Git ignore rules.

const std = @import("std");
const command = @import("command.zig");

pub const max_paths: usize = 10_000;

pub const Error = command.Error || error{
    MalformedOutput,
    TooManyPaths,
};

pub const List = struct {
    allocator: std.mem.Allocator,
    paths: [][]u8,

    pub fn deinit(self: *List) void {
        for (self.paths) |path| self.allocator.free(path);
        self.allocator.free(self.paths);
        self.* = undefined;
    }
};

pub fn load(
    allocator: std.mem.Allocator,
    io: std.Io,
    repo_dir: std.Io.Dir,
) Error!List {
    var output = try command.runChecked(allocator, io, repo_dir, &.{
        "ls-files",
        "--cached",
        "--others",
        "--exclude-standard",
        "-z",
    });
    defer output.deinit();
    return parse(allocator, output.stdout);
}

/// Parse Git's NUL-delimited path output. Each path is copied so the result is
/// independent of the bounded subprocess capture buffer.
pub fn parse(allocator: std.mem.Allocator, bytes: []const u8) Error!List {
    if (bytes.len != 0 and bytes[bytes.len - 1] != 0) return error.MalformedOutput;

    var paths: std.ArrayList([]u8) = .empty;
    errdefer {
        for (paths.items) |path| allocator.free(path);
        paths.deinit(allocator);
    }
    var start: usize = 0;
    while (start < bytes.len) {
        const relative_end = std.mem.indexOfScalar(u8, bytes[start..], 0) orelse return error.MalformedOutput;
        const end = start + relative_end;
        const path = bytes[start..end];
        if (path.len == 0) return error.MalformedOutput;
        if (paths.items.len == max_paths) return error.TooManyPaths;
        try paths.append(allocator, try allocator.dupe(u8, path));
        start = end + 1;
    }
    return .{ .allocator = allocator, .paths = try paths.toOwnedSlice(allocator) };
}

test "Git-visible path parser accepts tracked and untracked path forms" {
    var list = try parse(std.testing.allocator, "src/main.zig\x00new file.txt\x00.github/workflows/ci.yml\x00");
    defer list.deinit();

    try std.testing.expectEqual(@as(usize, 3), list.paths.len);
    try std.testing.expectEqualStrings("src/main.zig", list.paths[0]);
    try std.testing.expectEqualStrings("new file.txt", list.paths[1]);
    try std.testing.expectEqualStrings(".github/workflows/ci.yml", list.paths[2]);
}

test "Git-visible path parser rejects malformed and unbounded output" {
    try std.testing.expectError(error.MalformedOutput, parse(std.testing.allocator, "missing terminator"));
    try std.testing.expectError(error.MalformedOutput, parse(std.testing.allocator, "empty\x00\x00record\x00"));

    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(std.testing.allocator);
    for (0..max_paths + 1) |_| try bytes.appendSlice(std.testing.allocator, "a\x00");
    try std.testing.expectError(error.TooManyPaths, parse(std.testing.allocator, bytes.items));
}

const build_options = @import("build_options");

test "Git-visible enumeration includes tracked and eligible untracked files" {
    if (!build_options.git_integration) return error.SkipZigTest;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();

    var init = try command.runChecked(std.testing.allocator, std.testing.io, temporary.dir, &.{ "init", "--quiet" });
    init.deinit();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = ".gitignore", .data = "ignored.txt\n" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "tracked.txt", .data = "tracked\n" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "visible.txt", .data = "visible\n" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "ignored.txt", .data = "ignored\n" });
    var add = try command.runChecked(std.testing.allocator, std.testing.io, temporary.dir, &.{ "add", ".gitignore", "tracked.txt" });
    add.deinit();

    var list = try load(std.testing.allocator, std.testing.io, temporary.dir);
    defer list.deinit();
    try std.testing.expect(contains(list.paths, ".gitignore"));
    try std.testing.expect(contains(list.paths, "tracked.txt"));
    try std.testing.expect(contains(list.paths, "visible.txt"));
    try std.testing.expect(!contains(list.paths, "ignored.txt"));
}

fn contains(paths: []const []u8, expected: []const u8) bool {
    for (paths) |path| if (std.mem.eql(u8, path, expected)) return true;
    return false;
}
