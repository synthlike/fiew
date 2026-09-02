//! Parse `git diff --raw -z` and `--numstat -z` output into Skaut-owned changes.
//! Kept free of any git invocation so it is exhaustively fixture-tested.

const std = @import("std");
const git = @import("../../model/git.zig");

/// Parse one group's `git diff [--cached] -M50% -z --raw` output.
///
/// Records look like `:<omode> <nmode> <osha> <nsha> <status>\0<path>\0`, with a
/// second path for renames and copies. `-z` NUL-separates the paths.
pub fn parseRaw(
    allocator: std.mem.Allocator,
    group: git.Group,
    bytes: []const u8,
) !git.ChangeList {
    var items: std.ArrayList(git.Change) = .empty;
    errdefer freeChanges(allocator, &items);

    var fields = std.mem.splitScalar(u8, bytes, 0);
    while (fields.next()) |meta| {
        if (meta.len == 0 or meta[0] != ':') continue;

        var columns = std.mem.tokenizeScalar(u8, meta[1..], ' ');
        const old_mode = parseMode(columns.next() orelse continue);
        const new_mode = parseMode(columns.next() orelse continue);
        const old_sha = columns.next() orelse continue;
        const new_sha = columns.next() orelse continue;
        const status = columns.next() orelse continue;
        const letter = status[0];
        const two_paths = letter == 'R' or letter == 'C';

        const first_path = fields.next() orelse break;
        const second_path = if (two_paths) (fields.next() orelse break) else null;

        var kind = mapStatus(letter);
        // A modify that only flips the mode bits (same blob) is a mode change.
        if (kind == .modified and old_mode != new_mode and std.mem.eql(u8, old_sha, new_sha)) {
            kind = .mode_changed;
        }
        const content: git.ContentKind = if (old_mode == git.submodule_mode or new_mode == git.submodule_mode)
            .submodule
        else
            .text;

        const path = try allocator.dupe(u8, second_path orelse first_path);
        errdefer allocator.free(path);
        const old_path = if (two_paths) try allocator.dupe(u8, first_path) else null;
        errdefer if (old_path) |value| allocator.free(value);
        const old_blob = try blobOrNull(allocator, old_sha);
        errdefer if (old_blob) |value| allocator.free(value);
        const new_blob = try blobOrNull(allocator, new_sha);

        try items.append(allocator, .{
            .group = group,
            .kind = kind,
            .content = content,
            .path = path,
            .old_path = old_path,
            .similarity = if (two_paths) parseScore(status[1..]) else null,
            .old_mode = old_mode,
            .new_mode = new_mode,
            .old_blob = old_blob,
            .new_blob = new_blob,
        });
    }

    return .{ .allocator = allocator, .items = try items.toOwnedSlice(allocator) };
}

/// Mark changes binary using `git diff [--cached] --numstat -z` output, where a
/// binary file reports `-\t-` instead of counts. Submodules stay submodules.
pub fn applyBinaryFromNumstat(changes: *git.ChangeList, numstat: []const u8) void {
    var fields = std.mem.splitScalar(u8, numstat, 0);
    while (fields.next()) |record| {
        if (record.len == 0) continue;
        var columns = std.mem.splitScalar(u8, record, '\t');
        const added = columns.next() orelse continue;
        const deleted = columns.next() orelse continue;
        const binary = std.mem.eql(u8, added, "-") and std.mem.eql(u8, deleted, "-");
        // The path is either the tail of this record or the next NUL field
        // (renames emit the old and new path as two extra fields).
        var path = std.mem.trimStart(u8, columns.rest(), "\t");
        if (path.len == 0) {
            _ = fields.next() orelse break; // old path (rename)
            path = fields.next() orelse break; // new path
        }
        if (!binary) continue;
        for (changes.items) |*change| {
            if (change.content == .submodule) continue;
            if (std.mem.eql(u8, change.path, path)) change.content = .binary;
        }
    }
}

fn mapStatus(letter: u8) git.ChangeKind {
    return switch (letter) {
        'A' => .added,
        'D' => .deleted,
        'R' => .renamed,
        'C' => .copied,
        'T' => .type_changed,
        'U' => .unmerged,
        else => .modified,
    };
}

fn parseMode(text: []const u8) u32 {
    return std.fmt.parseInt(u32, text, 8) catch 0;
}

fn parseScore(text: []const u8) ?u8 {
    return std.fmt.parseInt(u8, text, 10) catch null;
}

/// Dupe a blob SHA, treating git's all-zero placeholder as "no blob".
fn blobOrNull(allocator: std.mem.Allocator, sha: []const u8) !?[]const u8 {
    for (sha) |character| {
        if (character != '0') return try allocator.dupe(u8, sha);
    }
    return null;
}

fn freeChanges(allocator: std.mem.Allocator, items: *std.ArrayList(git.Change)) void {
    for (items.items) |change| git.freeChange(allocator, change);
    items.deinit(allocator);
}

// --- Tests ---------------------------------------------------------------

const testing = std.testing;

test "raw output parses every ordinary change kind" {
    const raw =
        ":000000 100644 0000000 1111111 A\x00added.zig\x00" ++
        ":100644 100644 2222222 3333333 M\x00changed.zig\x00" ++
        ":100644 000000 4444444 0000000 D\x00gone.zig\x00" ++
        ":100644 100755 5555555 5555555 M\x00script.sh\x00" ++
        ":100644 120000 6666666 7777777 T\x00link\x00" ++
        ":160000 160000 8888888 9999999 M\x00submodule\x00";
    var changes = try parseRaw(testing.allocator, .unstaged, raw);
    defer changes.deinit();

    try testing.expectEqual(@as(usize, 6), changes.items.len);
    try testing.expectEqual(git.ChangeKind.added, changes.items[0].kind);
    try testing.expectEqual(git.ChangeKind.modified, changes.items[1].kind);
    try testing.expectEqual(git.ChangeKind.deleted, changes.items[2].kind);
    // Same blob, different mode -> mode change, no textual diff.
    try testing.expectEqual(git.ChangeKind.mode_changed, changes.items[3].kind);
    try testing.expect(!changes.items[3].showsDiff());
    try testing.expectEqual(git.ChangeKind.type_changed, changes.items[4].kind);
    // 160000 gitlink -> submodule content.
    try testing.expectEqual(git.ContentKind.submodule, changes.items[5].content);
    try testing.expect(!changes.items[5].showsDiff());
}

test "renames carry both paths and a similarity score" {
    const raw = ":100644 100644 aaaaaaa bbbbbbb R087\x00old/name.zig\x00new/name.zig\x00";
    var changes = try parseRaw(testing.allocator, .staged, raw);
    defer changes.deinit();

    try testing.expectEqual(@as(usize, 1), changes.items.len);
    const change = changes.items[0];
    try testing.expectEqual(git.ChangeKind.renamed, change.kind);
    try testing.expectEqualStrings("new/name.zig", change.path);
    try testing.expectEqualStrings("old/name.zig", change.old_path.?);
    try testing.expectEqual(@as(u8, 87), change.similarity.?);
}

test "numstat marks binary files without disturbing text or submodules" {
    const raw =
        ":100644 100644 1111111 2222222 M\x00image.png\x00" ++
        ":100644 100644 3333333 4444444 M\x00main.zig\x00" ++
        ":160000 160000 5555555 6666666 M\x00vendored\x00";
    var changes = try parseRaw(testing.allocator, .unstaged, raw);
    defer changes.deinit();

    const numstat = "-\t-\timage.png\x00" ++ "3\t1\tmain.zig\x00" ++ "-\t-\tvendored\x00";
    applyBinaryFromNumstat(&changes, numstat);

    try testing.expectEqual(git.ContentKind.binary, changes.items[0].content);
    try testing.expectEqual(git.ContentKind.text, changes.items[1].content);
    try testing.expectEqual(git.ContentKind.submodule, changes.items[2].content);
}

test "empty diff output yields no changes" {
    var changes = try parseRaw(testing.allocator, .staged, "");
    defer changes.deinit();
    try testing.expectEqual(@as(usize, 0), changes.items.len);
}
