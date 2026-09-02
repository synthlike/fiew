//! Parse git's unified diff output into Skaut-owned `FileDiff` values. No git is
//! invoked here; the parser is driven entirely by fixture text.

const std = @import("std");
const git = @import("../../model/git.zig");

/// Iterates the per-file segments of a multi-file patch. Each segment begins
/// with a `diff --git ...` line and runs to the next one.
pub const FileIterator = struct {
    rest: []const u8,

    pub fn next(self: *FileIterator) ?[]const u8 {
        if (self.rest.len == 0) return null;
        std.debug.assert(std.mem.startsWith(u8, self.rest, "diff --git "));
        const marker = "\ndiff --git ";
        if (std.mem.indexOf(u8, self.rest, marker)) |index| {
            const segment = self.rest[0 .. index + 1];
            self.rest = self.rest[index + 1 ..];
            return segment;
        }
        const segment = self.rest;
        self.rest = self.rest[self.rest.len..];
        return segment;
    }
};

pub fn iterateFiles(patch: []const u8) FileIterator {
    const start = std.mem.indexOf(u8, patch, "diff --git ") orelse patch.len;
    return .{ .rest = patch[start..] };
}

/// The new-side path a file segment applies to, preferring `+++ b/…` and
/// falling back to `--- a/…` for deletions.
pub fn segmentPath(segment: []const u8) ?[]const u8 {
    var lines = std.mem.splitScalar(u8, segment, '\n');
    var old_path: ?[]const u8 = null;
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "+++ ")) {
            const target = line[4..];
            if (std.mem.startsWith(u8, target, "b/")) return target[2..];
        } else if (std.mem.startsWith(u8, line, "--- ")) {
            const target = line[4..];
            if (std.mem.startsWith(u8, target, "a/")) old_path = target[2..];
        }
    }
    return old_path;
}

/// Parse the hunks of a single file's diff segment into an owned `FileDiff`.
/// Header and metadata lines before the first `@@` are ignored; segments with
/// no hunks (binary, mode-only) produce an empty diff.
pub fn parseFileDiff(allocator: std.mem.Allocator, segment: []const u8) !git.FileDiff {
    var text: std.ArrayList(u8) = .empty;
    errdefer text.deinit(allocator);
    var lines: std.ArrayList(git.DiffLine) = .empty;
    errdefer lines.deinit(allocator);
    var hunks: std.ArrayList(git.Hunk) = .empty;
    errdefer hunks.deinit(allocator);

    var old_line: usize = 0;
    var new_line: usize = 0;
    var in_hunk = false;

    var iterator = std.mem.splitScalar(u8, segment, '\n');
    while (iterator.next()) |line| {
        if (std.mem.startsWith(u8, line, "@@")) {
            // git's headers are well-formed; a malformed one is ignored rather
            // than failing the whole parse.
            const header = parseHunkHeader(line) catch {
                in_hunk = false;
                continue;
            };
            if (hunks.items.len != 0) {
                hunks.items[hunks.items.len - 1].line_count =
                    lines.items.len - hunks.items[hunks.items.len - 1].first_line;
            }
            const heading_start = text.items.len;
            try text.appendSlice(allocator, header.heading);
            try hunks.append(allocator, .{
                .old_start = header.old_start,
                .old_count = header.old_count,
                .new_start = header.new_start,
                .new_count = header.new_count,
                .header = .{ .start = heading_start, .end = text.items.len },
                .first_line = lines.items.len,
                .line_count = 0,
            });
            old_line = header.old_start;
            new_line = header.new_start;
            in_hunk = true;
            continue;
        }
        if (!in_hunk or line.len == 0) continue;
        if (line[0] == '\\') continue; // "\ No newline at end of file"

        const kind: git.LineKind = switch (line[0]) {
            ' ' => .context,
            '+' => .addition,
            '-' => .deletion,
            else => {
                in_hunk = false;
                continue;
            },
        };
        const start = text.items.len;
        try text.appendSlice(allocator, line[1..]);
        try lines.append(allocator, .{
            .kind = kind,
            .old_line = if (kind == .addition) null else old_line,
            .new_line = if (kind == .deletion) null else new_line,
            .text = .{ .start = start, .end = text.items.len },
        });
        if (kind != .addition) old_line += 1;
        if (kind != .deletion) new_line += 1;
    }
    if (hunks.items.len != 0) {
        hunks.items[hunks.items.len - 1].line_count =
            lines.items.len - hunks.items[hunks.items.len - 1].first_line;
    }

    return .{
        .allocator = allocator,
        .text = try text.toOwnedSlice(allocator),
        .hunks = try hunks.toOwnedSlice(allocator),
        .lines = try lines.toOwnedSlice(allocator),
    };
}

const HunkHeader = struct {
    old_start: usize,
    old_count: usize,
    new_start: usize,
    new_count: usize,
    heading: []const u8,
};

/// Parse `@@ -old_start,old_count +new_start,new_count @@ heading`.
fn parseHunkHeader(line: []const u8) !HunkHeader {
    const open = std.mem.indexOf(u8, line, "@@ ") orelse return error.BadHunkHeader;
    const after = line[open + 3 ..];
    const close = std.mem.indexOf(u8, after, " @@") orelse return error.BadHunkHeader;
    const ranges = after[0..close];
    var heading = after[close + 3 ..];
    if (heading.len != 0 and heading[0] == ' ') heading = heading[1..];

    var parts = std.mem.tokenizeScalar(u8, ranges, ' ');
    const old = try parseRange(parts.next() orelse return error.BadHunkHeader, '-');
    const new = try parseRange(parts.next() orelse return error.BadHunkHeader, '+');
    return .{
        .old_start = old.start,
        .old_count = old.count,
        .new_start = new.start,
        .new_count = new.count,
        .heading = heading,
    };
}

fn parseRange(field: []const u8, sign: u8) !struct { start: usize, count: usize } {
    if (field.len == 0 or field[0] != sign) return error.BadHunkHeader;
    var numbers = std.mem.splitScalar(u8, field[1..], ',');
    const start = std.fmt.parseInt(usize, numbers.next() orelse return error.BadHunkHeader, 10) catch
        return error.BadHunkHeader;
    const count = if (numbers.next()) |value|
        std.fmt.parseInt(usize, value, 10) catch return error.BadHunkHeader
    else
        1;
    return .{ .start = start, .count = count };
}

// --- Tests ---------------------------------------------------------------

const testing = std.testing;

const two_file_patch =
    "diff --git a/a.txt b/a.txt\n" ++
    "index b3c5a95..4dfc79e 100644\n" ++
    "--- a/a.txt\n" ++
    "+++ b/a.txt\n" ++
    "@@ -1,5 +1,6 @@ fn header\n" ++
    " line1\n" ++
    "-line2\n" ++
    "+CHANGED\n" ++
    " line3\n" ++
    " line4\n" ++
    " line5\n" ++
    "+line6added\n" ++
    "diff --git a/new.txt b/new.txt\n" ++
    "new file mode 100644\n" ++
    "index 0000000..39963cd\n" ++
    "--- /dev/null\n" ++
    "+++ b/new.txt\n" ++
    "@@ -0,0 +1,2 @@\n" ++
    "+brand new\n" ++
    "+file\n";

test "iterate splits a patch into per-file segments with paths" {
    var iterator = iterateFiles(two_file_patch);
    const first = iterator.next().?;
    try testing.expectEqualStrings("a.txt", segmentPath(first).?);
    const second = iterator.next().?;
    try testing.expectEqualStrings("new.txt", segmentPath(second).?);
    try testing.expect(iterator.next() == null);
}

test "parse a hunk with context, deletion, and addition line numbers" {
    var iterator = iterateFiles(two_file_patch);
    var file = try parseFileDiff(testing.allocator, iterator.next().?);
    defer file.deinit();

    try testing.expectEqual(@as(usize, 1), file.hunks.len);
    const hunk = file.hunks[0];
    try testing.expectEqual(@as(usize, 1), hunk.old_start);
    try testing.expectEqual(@as(usize, 6), hunk.new_count);
    try testing.expectEqualStrings("fn header", file.text[hunk.header.start..hunk.header.end]);
    try testing.expectEqual(@as(usize, 7), hunk.line_count);

    // ` line1` context: both sides line 1.
    try testing.expectEqual(git.LineKind.context, file.lines[0].kind);
    try testing.expectEqual(@as(usize, 1), file.lines[0].old_line.?);
    try testing.expectEqual(@as(usize, 1), file.lines[0].new_line.?);
    // `-line2` deletion: old line 2, no new line.
    try testing.expectEqual(git.LineKind.deletion, file.lines[1].kind);
    try testing.expectEqual(@as(usize, 2), file.lines[1].old_line.?);
    try testing.expect(file.lines[1].new_line == null);
    try testing.expectEqualStrings("line2", file.text[file.lines[1].text.start..file.lines[1].text.end]);
    // `+CHANGED` addition: new line 2, no old line.
    try testing.expectEqual(git.LineKind.addition, file.lines[2].kind);
    try testing.expect(file.lines[2].old_line == null);
    try testing.expectEqual(@as(usize, 2), file.lines[2].new_line.?);
    // Trailing `+line6added` is new line 6.
    const last = file.lines[file.lines.len - 1];
    try testing.expectEqual(@as(usize, 6), last.new_line.?);
    // One deletion plus two additions.
    try testing.expectEqual(@as(usize, 3), file.changedLineCount());
}

test "a metadata-only segment parses to an empty diff" {
    const mode_only =
        "diff --git a/mode.txt b/mode.txt\n" ++
        "old mode 100644\n" ++
        "new mode 100755\n";
    var file = try parseFileDiff(testing.allocator, mode_only);
    defer file.deinit();
    try testing.expectEqual(@as(usize, 0), file.hunks.len);
    try testing.expectEqual(@as(usize, 0), file.lines.len);
}

test "multi-hunk line counts are recorded per hunk" {
    const patch =
        "diff --git a/x b/x\n" ++
        "--- a/x\n" ++
        "+++ b/x\n" ++
        "@@ -1,2 +1,2 @@\n" ++
        " a\n" ++
        "-b\n" ++
        "+B\n" ++
        "@@ -10,2 +10,3 @@\n" ++
        " j\n" ++
        "+k\n" ++
        " l\n";
    var file = try parseFileDiff(testing.allocator, patch);
    defer file.deinit();
    try testing.expectEqual(@as(usize, 2), file.hunks.len);
    try testing.expectEqual(@as(usize, 3), file.hunks[0].line_count);
    try testing.expectEqual(@as(usize, 3), file.hunks[1].line_count);
    try testing.expectEqual(@as(usize, 10), file.lines[file.hunks[1].first_line].old_line.?);
}
