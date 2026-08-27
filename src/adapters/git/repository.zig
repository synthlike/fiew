//! Repository discovery for the read-only Git review workflow. Classifies the
//! directory fiew was opened in as a usable work tree (standard or linked
//! worktree, possibly unborn), a non-Git directory, or an unsupported bare
//! repository — all through non-mutating `git rev-parse` calls.

const std = @import("std");
const command = @import("command.zig");

pub const Error = command.Error;

/// A usable repository context. Owns its path strings.
pub const Context = struct {
    allocator: std.mem.Allocator,
    /// Absolute work-tree root.
    toplevel: []const u8,
    /// Absolute git directory (per-worktree for linked worktrees).
    git_dir: []const u8,
    /// True when HEAD has no commit yet; changes compare against the empty tree.
    unborn: bool,

    pub fn deinit(self: *Context) void {
        self.allocator.free(self.toplevel);
        self.allocator.free(self.git_dir);
        self.* = undefined;
    }
};

pub const Discovery = union(enum) {
    ready: Context,
    /// Browsable, but Git and Review contexts are disabled.
    not_a_repository,
    /// Bare repositories are out of scope for v0.1.
    bare_unsupported,
};

/// Classify `dir` (the directory fiew is browsing).
pub fn discover(
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
) Error!Discovery {
    var probe = try command.run(allocator, io, dir, &.{
        "rev-parse",
        "--is-bare-repository",
        "--is-inside-work-tree",
    });
    defer probe.deinit();
    if (!probe.succeeded()) return .not_a_repository;

    var lines = std.mem.tokenizeScalar(u8, probe.stdout, '\n');
    const bare = trim(lines.next() orelse "");
    const inside_work_tree = trim(lines.next() orelse "");
    if (std.mem.eql(u8, bare, "true")) return .bare_unsupported;
    if (!std.mem.eql(u8, inside_work_tree, "true")) return .not_a_repository;

    var paths = try command.run(allocator, io, dir, &.{
        "rev-parse",
        "--show-toplevel",
        "--absolute-git-dir",
    });
    defer paths.deinit();
    if (!paths.succeeded()) return .not_a_repository;
    var path_lines = std.mem.tokenizeScalar(u8, paths.stdout, '\n');
    const toplevel = trim(path_lines.next() orelse "");
    const git_dir = trim(path_lines.next() orelse "");
    if (toplevel.len == 0 or git_dir.len == 0) return .not_a_repository;

    var head = try command.run(allocator, io, dir, &.{ "rev-parse", "--verify", "--quiet", "HEAD" });
    defer head.deinit();

    const owned_toplevel = try allocator.dupe(u8, toplevel);
    errdefer allocator.free(owned_toplevel);
    const owned_git_dir = try allocator.dupe(u8, git_dir);

    return .{ .ready = .{
        .allocator = allocator,
        .toplevel = owned_toplevel,
        .git_dir = owned_git_dir,
        .unborn = !head.succeeded(),
    } };
}

fn trim(line: []const u8) []const u8 {
    return std.mem.trimEnd(u8, line, "\r");
}

// --- Integration tests (opt-in: `-Dgit-integration`) ---------------------

const build_options = @import("build_options");

fn requireGitIntegration() !void {
    if (!build_options.git_integration) return error.SkipZigTest;
}

fn runGit(dir: std.Io.Dir, args: []const []const u8) !void {
    var output = try command.run(std.testing.allocator, std.testing.io, dir, args);
    defer output.deinit();
    if (!output.succeeded()) return error.GitCommandFailed;
}

test "discover classifies a fresh work tree as ready and unborn" {
    try requireGitIntegration();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();

    // `git init` makes the temp directory its own (innermost) repository, so
    // discovery reports it even though the temp dir is nested under fiew's repo.
    try runGit(tmp.dir, &.{ "init", "--quiet" });
    var discovery = try discover(std.testing.allocator, std.testing.io, tmp.dir);
    switch (discovery) {
        .ready => |*context| {
            defer context.deinit();
            try std.testing.expect(context.unborn);
            try std.testing.expect(context.toplevel.len != 0);
        },
        else => return error.TestUnexpectedResult,
    }

    // After a commit the repository is no longer unborn.
    try runGit(tmp.dir, &.{ "-c", "user.email=t@t", "-c", "user.name=t", "commit", "--allow-empty", "--quiet", "-m", "init" });
    var born = try discover(std.testing.allocator, std.testing.io, tmp.dir);
    switch (born) {
        .ready => |*context| {
            defer context.deinit();
            try std.testing.expect(!context.unborn);
        },
        else => return error.TestUnexpectedResult,
    }
}
