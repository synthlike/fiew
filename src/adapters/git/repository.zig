//! Repository discovery for the read-only Git review workflow. Classifies the
//! directory fiew was opened in as a usable work tree (standard or linked
//! worktree, possibly unborn), a non-Git directory, or an unsupported bare
//! repository — all through non-mutating `git rev-parse` calls.

const std = @import("std");
const command = @import("command.zig");
const changes_parser = @import("changes.zig");
const diff_parser = @import("diff.zig");
const git = @import("../../model/git.zig");

pub const Error = command.Error;

/// Upper bound on an untracked file we will render as a textual "all added"
/// diff; larger files are listed but shown as metadata only.
pub const untracked_diff_limit: u64 = 2 << 20;

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

/// Diff flags shared by every invocation: rename detection at 50%, no color,
/// and none of git's pluggable content transforms.
const diff_flags = [_][]const u8{
    "-M50%",         "--find-renames",
    "--no-color",    "--no-ext-diff",
    "--no-textconv",
};

/// Read the full current-working-tree change set: Staged, Unstaged, and
/// Untracked groups, each change paired with its parsed diff.
pub fn loadChanges(
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
) Error!git.ChangeSet {
    var changes: std.ArrayList(git.Change) = .empty;
    var diffs: std.ArrayList(git.FileDiff) = .empty;
    errdefer freePartial(allocator, &changes, &diffs);

    try appendDiffGroup(allocator, io, dir, .staged, true, &changes, &diffs);
    try appendDiffGroup(allocator, io, dir, .unstaged, false, &changes, &diffs);
    try appendUntracked(allocator, io, dir, &changes, &diffs);

    return .{
        .allocator = allocator,
        .changes = try changes.toOwnedSlice(allocator),
        .diffs = try diffs.toOwnedSlice(allocator),
    };
}

fn appendDiffGroup(
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    group: git.Group,
    cached: bool,
    changes: *std.ArrayList(git.Change),
    diffs: *std.ArrayList(git.FileDiff),
) Error!void {
    const cached_flag: []const []const u8 = if (cached) &.{"--cached"} else &.{};

    var raw = try runDiff(allocator, io, dir, cached_flag, &.{ "-z", "--raw" });
    defer raw.deinit();
    var list = try changes_parser.parseRaw(allocator, group, raw.stdout);
    // `list` owns its path strings until they are moved into `changes`.
    errdefer list.deinit();

    var numstat = try runDiff(allocator, io, dir, cached_flag, &.{ "--numstat", "-z" });
    defer numstat.deinit();
    changes_parser.applyBinaryFromNumstat(&list, numstat.stdout);

    var patch = try runDiff(allocator, io, dir, cached_flag, &.{"-U3"});
    defer patch.deinit();

    // Phase 1 (fallible): parse each change's diff into a temporary array. If
    // anything fails, `list` and `group_diffs` are cleaned up independently and
    // no ownership has been shared yet.
    var group_diffs: std.ArrayList(git.FileDiff) = .empty;
    errdefer {
        for (group_diffs.items) |*file_diff| file_diff.deinit();
        group_diffs.deinit(allocator);
    }
    for (list.items) |change| {
        const file_diff = if (change.showsDiff())
            try parseMatchingDiff(allocator, patch.stdout, change.path)
        else
            emptyDiff(allocator);
        try group_diffs.append(allocator, file_diff);
    }

    // Reserve output capacity before any move so the move loop cannot fail.
    try changes.ensureUnusedCapacity(allocator, list.items.len);
    try diffs.ensureUnusedCapacity(allocator, group_diffs.items.len);

    // Phase 2 (infallible): move the changes and diffs into the output.
    for (list.items, group_diffs.items) |change, file_diff| {
        changes.appendAssumeCapacity(change);
        diffs.appendAssumeCapacity(file_diff);
    }
    // Free only the backing arrays; their contents were moved out.
    allocator.free(list.items);
    list.items = &.{};
    group_diffs.deinit(allocator);
}

fn appendUntracked(
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    changes: *std.ArrayList(git.Change),
    diffs: *std.ArrayList(git.FileDiff),
) Error!void {
    var others = try command.run(allocator, io, dir, &.{
        "ls-files", "-z", "--others", "--exclude-standard",
    });
    defer others.deinit();

    var paths = std.mem.splitScalar(u8, others.stdout, 0);
    while (paths.next()) |path| {
        if (path.len == 0) continue;
        const owned = try allocator.dupe(u8, path);
        errdefer allocator.free(owned);

        const content_and_diff = untrackedDiff(allocator, io, dir, path);
        try diffs.append(allocator, content_and_diff.diff);
        try changes.append(allocator, .{
            .group = .untracked,
            .kind = .added,
            .content = content_and_diff.content,
            .path = owned,
        });
    }
}

const UntrackedResult = struct { content: git.ContentKind, diff: git.FileDiff };

fn untrackedDiff(
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    path: []const u8,
) UntrackedResult {
    const bytes = dir.readFileAlloc(io, path, allocator, .limited64(untracked_diff_limit)) catch
        return .{ .content = .binary, .diff = emptyDiff(allocator) };
    defer allocator.free(bytes);
    if (std.mem.indexOfScalar(u8, bytes, 0) != null) {
        return .{ .content = .binary, .diff = emptyDiff(allocator) };
    }
    const diff = syntheticAddedDiff(allocator, bytes) catch
        return .{ .content = .text, .diff = emptyDiff(allocator) };
    return .{ .content = .text, .diff = diff };
}

/// Build an all-additions diff for an untracked file's contents.
fn syntheticAddedDiff(allocator: std.mem.Allocator, bytes: []const u8) !git.FileDiff {
    var text: std.ArrayList(u8) = .empty;
    errdefer text.deinit(allocator);
    var lines: std.ArrayList(git.DiffLine) = .empty;
    errdefer lines.deinit(allocator);

    var new_line: usize = 1;
    var iterator = std.mem.splitScalar(u8, bytes, '\n');
    var pending: ?[]const u8 = iterator.next();
    while (pending) |content| {
        const following = iterator.next();
        // A trailing newline yields a final empty segment; do not emit it.
        if (following == null and content.len == 0) break;
        const start = text.items.len;
        try text.appendSlice(allocator, content);
        try lines.append(allocator, .{
            .kind = .addition,
            .old_line = null,
            .new_line = new_line,
            .text = .{ .start = start, .end = text.items.len },
        });
        new_line += 1;
        pending = following;
    }

    var hunks: std.ArrayList(git.Hunk) = .empty;
    errdefer hunks.deinit(allocator);
    if (lines.items.len != 0) {
        try hunks.append(allocator, .{
            .old_start = 0,
            .old_count = 0,
            .new_start = 1,
            .new_count = lines.items.len,
            .header = .{ .start = 0, .end = 0 },
            .first_line = 0,
            .line_count = lines.items.len,
        });
    }
    return .{
        .allocator = allocator,
        .text = try text.toOwnedSlice(allocator),
        .hunks = try hunks.toOwnedSlice(allocator),
        .lines = try lines.toOwnedSlice(allocator),
    };
}

fn parseMatchingDiff(
    allocator: std.mem.Allocator,
    patch: []const u8,
    path: []const u8,
) !git.FileDiff {
    var files = diff_parser.iterateFiles(patch);
    while (files.next()) |segment| {
        if (diff_parser.segmentPath(segment)) |segment_path| {
            if (std.mem.eql(u8, segment_path, path)) {
                return diff_parser.parseFileDiff(allocator, segment);
            }
        }
    }
    return emptyDiff(allocator);
}

fn emptyDiff(allocator: std.mem.Allocator) git.FileDiff {
    return .{ .allocator = allocator, .text = "", .hunks = &.{}, .lines = &.{} };
}

fn runDiff(
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    cached_flag: []const []const u8,
    tail: []const []const u8,
) Error!command.Output {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);
    try argv.append(allocator, "diff");
    try argv.appendSlice(allocator, cached_flag);
    try argv.appendSlice(allocator, &diff_flags);
    try argv.appendSlice(allocator, tail);
    return command.run(allocator, io, dir, argv.items);
}

fn freePartial(
    allocator: std.mem.Allocator,
    changes: *std.ArrayList(git.Change),
    diffs: *std.ArrayList(git.FileDiff),
) void {
    for (changes.items) |change| git.freeChange(allocator, change);
    changes.deinit(allocator);
    for (diffs.items) |*diff| diff.deinit();
    diffs.deinit(allocator);
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

fn writeFileTo(dir: std.Io.Dir, sub_path: []const u8, data: []const u8) !void {
    try dir.writeFile(std.testing.io, .{ .sub_path = sub_path, .data = data });
}

fn findChange(set: git.ChangeSet, group: git.Group, path: []const u8) ?usize {
    for (set.changes, 0..) |change, index| {
        if (change.group == group and std.mem.eql(u8, change.path, path)) return index;
    }
    return null;
}

test "loadChanges assembles staged, unstaged, and untracked groups" {
    try requireGitIntegration();
    var tmp = std.testing.tmpDir(.{ .iterate = true });
    defer tmp.cleanup();
    try runGit(tmp.dir, &.{ "init", "--quiet" });
    try writeFileTo(tmp.dir, "base.txt", "one\ntwo\nthree\n");
    try runGit(tmp.dir, &.{ "add", "-A" });
    try runGit(tmp.dir, &.{ "-c", "user.email=t@t", "-c", "user.name=t", "commit", "--quiet", "-m", "init" });

    // Unstaged modification, staged addition, and an untracked file.
    try writeFileTo(tmp.dir, "base.txt", "one\nTWO\nthree\n");
    try writeFileTo(tmp.dir, "staged.txt", "fresh\n");
    try runGit(tmp.dir, &.{ "add", "staged.txt" });
    try writeFileTo(tmp.dir, "untracked.txt", "note\nhere\n");

    var status_before = try command.run(std.testing.allocator, std.testing.io, tmp.dir, &.{ "status", "--porcelain=v2", "-z" });
    defer status_before.deinit();

    var set = try loadChanges(std.testing.allocator, std.testing.io, tmp.dir);
    defer set.deinit();

    const unstaged = findChange(set, .unstaged, "base.txt") orelse return error.MissingUnstaged;
    try std.testing.expectEqual(git.ChangeKind.modified, set.changes[unstaged].kind);
    try std.testing.expect(set.diffs[unstaged].changedLineCount() >= 2);

    const staged = findChange(set, .staged, "staged.txt") orelse return error.MissingStaged;
    try std.testing.expectEqual(git.ChangeKind.added, set.changes[staged].kind);

    const untracked = findChange(set, .untracked, "untracked.txt") orelse return error.MissingUntracked;
    try std.testing.expectEqual(git.ContentKind.text, set.changes[untracked].content);
    try std.testing.expectEqual(@as(usize, 2), set.diffs[untracked].changedLineCount());

    // The review must not mutate the repository: status is unchanged.
    var status_after = try command.run(std.testing.allocator, std.testing.io, tmp.dir, &.{ "status", "--porcelain=v2", "-z" });
    defer status_after.deinit();
    try std.testing.expectEqualSlices(u8, status_before.stdout, status_after.stdout);
}
