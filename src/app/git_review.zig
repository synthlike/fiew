//! State for the Git review context: the grouped change list shown in the
//! sidebar and the cursor used to navigate the selected change's diff. Pure and
//! fiew-owned; it takes ownership of a loaded `ChangeSet` and never touches git.

const std = @import("std");
const git = @import("../model/git.zig");

/// One visible sidebar row: a group heading or a change within it.
pub const Row = union(enum) {
    header: git.Group,
    change: usize, // index into `changeset.changes`
};

pub const Review = struct {
    allocator: std.mem.Allocator,
    changeset: git.ChangeSet,
    rows: []Row,
    /// Index into `rows`; kept on a change row whenever any change exists.
    selected: usize = 0,
    scroll: usize = 0,
    /// Cursor within the selected change's diff (index into its `FileDiff.lines`).
    diff_line: usize = 0,
    diff_scroll: usize = 0,

    /// The group order shown in the sidebar.
    const group_order = [_]git.Group{ .staged, .unstaged, .untracked };

    /// Build a review from a loaded change set, taking ownership of it.
    pub fn init(allocator: std.mem.Allocator, changeset: git.ChangeSet) !Review {
        var rows: std.ArrayList(Row) = .empty;
        errdefer rows.deinit(allocator);
        for (group_order) |group| {
            if (changeset.groupCount(group) == 0) continue;
            try rows.append(allocator, .{ .header = group });
            for (changeset.changes, 0..) |change, index| {
                if (change.group == group) try rows.append(allocator, .{ .change = index });
            }
        }
        var review: Review = .{
            .allocator = allocator,
            .changeset = changeset,
            .rows = try rows.toOwnedSlice(allocator),
        };
        review.selected = review.firstChangeRow() orelse 0;
        return review;
    }

    pub fn deinit(self: *Review) void {
        self.allocator.free(self.rows);
        self.changeset.deinit();
        self.* = undefined;
    }

    pub fn isEmpty(self: Review) bool {
        return self.changeset.isEmpty();
    }

    /// The change index the selection is on, if it is on a change row.
    pub fn selectedChange(self: Review) ?usize {
        if (self.selected >= self.rows.len) return null;
        return switch (self.rows[self.selected]) {
            .change => |index| index,
            .header => null,
        };
    }

    /// The diff for the selected change, if any.
    pub fn selectedDiff(self: Review) ?*const git.FileDiff {
        const index = self.selectedChange() orelse return null;
        return &self.changeset.diffs[index];
    }

    pub fn selectedGroup(self: Review) ?git.Group {
        if (self.selected >= self.rows.len) return null;
        return switch (self.rows[self.selected]) {
            .header => |group| group,
            .change => |index| self.changeset.changes[index].group,
        };
    }

    /// Move the selection by whole rows, skipping headers, and keep it visible.
    pub fn moveSelection(self: *Review, delta: isize, viewport_rows: usize) void {
        if (self.rows.len == 0) return;
        var current: isize = @intCast(self.selected);
        const last: isize = @intCast(self.rows.len - 1);
        const step: isize = if (delta < 0) -1 else 1;
        var remaining = @abs(delta);
        while (remaining > 0) : (remaining -= 1) {
            var probe = current + step;
            while (probe >= 0 and probe <= last and self.rows[@intCast(probe)] == .header) probe += step;
            if (probe < 0 or probe > last) break;
            current = probe;
        }
        self.selected = @intCast(current);
        self.resetDiffCursor();
        self.ensureVisible(viewport_rows);
    }

    /// Select the change at visible row `visible_index` (for mouse clicks).
    pub fn selectRow(self: *Review, row_index: usize, viewport_rows: usize) void {
        if (row_index >= self.rows.len) return;
        if (self.rows[row_index] == .header) return;
        self.selected = row_index;
        self.resetDiffCursor();
        self.ensureVisible(viewport_rows);
    }

    /// `[ f` / `] f`: move among change files within the active group.
    /// Returns false at a group boundary (the caller may report it).
    pub fn moveFile(self: *Review, forward: bool, viewport_rows: usize) bool {
        const group = self.selectedGroup() orelse return false;
        const step: isize = if (forward) 1 else -1;
        var probe: isize = @as(isize, @intCast(self.selected)) + step;
        const last: isize = @intCast(self.rows.len - 1);
        while (probe >= 0 and probe <= last) : (probe += step) {
            switch (self.rows[@intCast(probe)]) {
                .change => |index| {
                    if (self.changeset.changes[index].group != group) return false;
                    self.selected = @intCast(probe);
                    self.resetDiffCursor();
                    self.ensureVisible(viewport_rows);
                    return true;
                },
                .header => return false,
            }
        }
        return false;
    }

    /// `[ h` / `] h`: move the diff cursor to the next/previous hunk.
    pub fn moveHunk(self: *Review, forward: bool) bool {
        const diff = self.selectedDiff() orelse return false;
        if (diff.hunks.len == 0) return false;
        // Find the hunk currently containing the cursor.
        var current_hunk: usize = 0;
        for (diff.hunks, 0..) |hunk, index| {
            if (self.diff_line >= hunk.first_line and self.diff_line < hunk.first_line + hunk.line_count) {
                current_hunk = index;
                break;
            }
        }
        if (forward) {
            if (current_hunk + 1 >= diff.hunks.len) return false;
            self.diff_line = diff.hunks[current_hunk + 1].first_line;
        } else {
            if (current_hunk == 0) return false;
            self.diff_line = diff.hunks[current_hunk - 1].first_line;
        }
        return true;
    }

    /// `[ c` / `] c`: move the diff cursor to the next/previous changed line.
    pub fn moveChangedLine(self: *Review, forward: bool) bool {
        const diff = self.selectedDiff() orelse return false;
        if (diff.lines.len == 0) return false;
        const step: isize = if (forward) 1 else -1;
        var probe: isize = @as(isize, @intCast(self.diff_line)) + step;
        const last: isize = @intCast(diff.lines.len - 1);
        while (probe >= 0 and probe <= last) : (probe += step) {
            if (diff.lines[@intCast(probe)].kind != .context) {
                self.diff_line = @intCast(probe);
                return true;
            }
        }
        return false;
    }

    /// The source location (path, one-based line) the diff cursor points at, for
    /// opening the file in context. Uses the new side when present, else old.
    pub const SourceTarget = struct { path: []const u8, line: usize };

    pub fn sourceTarget(self: Review) ?SourceTarget {
        const change_index = self.selectedChange() orelse return null;
        const change = self.changeset.changes[change_index];
        const diff = &self.changeset.diffs[change_index];
        if (diff.lines.len == 0) return null;
        const line = diff.lines[@min(self.diff_line, diff.lines.len - 1)];
        if (line.new_line) |new_line| return .{ .path = change.path, .line = new_line };
        if (line.old_line) |old_line| {
            return .{ .path = change.old_path orelse change.path, .line = old_line };
        }
        return null;
    }

    /// Move the diff cursor by whole lines (for `j`/`k` in the diff view).
    pub fn moveDiffLine(self: *Review, delta: isize, viewport_rows: usize) void {
        const diff = self.selectedDiff() orelse return;
        if (diff.lines.len == 0) return;
        const current: isize = @intCast(self.diff_line);
        const last: isize = @intCast(diff.lines.len - 1);
        self.diff_line = @intCast(std.math.clamp(current + delta, 0, last));
        self.ensureDiffVisible(viewport_rows);
    }

    /// Keep the diff cursor within the visible window.
    pub fn ensureDiffVisible(self: *Review, viewport_rows: usize) void {
        if (viewport_rows == 0) return;
        if (self.diff_line < self.diff_scroll) self.diff_scroll = self.diff_line;
        if (self.diff_line >= self.diff_scroll + viewport_rows) {
            self.diff_scroll = self.diff_line - viewport_rows + 1;
        }
    }

    fn firstChangeRow(self: Review) ?usize {
        for (self.rows, 0..) |row, index| {
            if (row == .change) return index;
        }
        return null;
    }

    fn resetDiffCursor(self: *Review) void {
        self.diff_line = 0;
        self.diff_scroll = 0;
    }

    fn ensureVisible(self: *Review, viewport_rows: usize) void {
        if (viewport_rows == 0) return;
        if (self.selected < self.scroll) self.scroll = self.selected;
        if (self.selected >= self.scroll + viewport_rows) self.scroll = self.selected - viewport_rows + 1;
    }
};

// --- Tests ---------------------------------------------------------------

const testing = std.testing;

fn dupeLines(allocator: std.mem.Allocator, lines: []const git.DiffLine) ![]git.DiffLine {
    return allocator.dupe(git.DiffLine, lines);
}

fn buildChangeSet(allocator: std.mem.Allocator) !git.ChangeSet {
    var changes = try allocator.alloc(git.Change, 3);
    changes[0] = .{ .group = .staged, .kind = .added, .content = .text, .path = try allocator.dupe(u8, "a.zig") };
    changes[1] = .{ .group = .unstaged, .kind = .modified, .content = .text, .path = try allocator.dupe(u8, "b.zig") };
    changes[2] = .{ .group = .untracked, .kind = .added, .content = .text, .path = try allocator.dupe(u8, "c.txt") };

    var diffs = try allocator.alloc(git.FileDiff, 3);
    diffs[0] = .{ .allocator = allocator, .text = "", .hunks = &.{}, .lines = &.{} };
    // b.zig: one hunk with a context, a deletion, and an addition line.
    const b_lines = try dupeLines(allocator, &.{
        .{ .kind = .context, .old_line = 1, .new_line = 1, .text = .{ .start = 0, .end = 0 } },
        .{ .kind = .deletion, .old_line = 2, .new_line = null, .text = .{ .start = 0, .end = 0 } },
        .{ .kind = .addition, .old_line = null, .new_line = 2, .text = .{ .start = 0, .end = 0 } },
    });
    const b_hunks = try allocator.dupe(git.Hunk, &.{
        .{ .old_start = 1, .old_count = 2, .new_start = 1, .new_count = 2, .header = .{ .start = 0, .end = 0 }, .first_line = 0, .line_count = 3 },
    });
    diffs[1] = .{ .allocator = allocator, .text = "", .hunks = b_hunks, .lines = b_lines };
    diffs[2] = .{ .allocator = allocator, .text = "", .hunks = &.{}, .lines = &.{} };

    return .{ .allocator = allocator, .changes = changes, .diffs = diffs };
}

test "review builds grouped rows and selects the first change" {
    var review = try Review.init(testing.allocator, try buildChangeSet(testing.allocator));
    defer review.deinit();

    // 3 headers + 3 changes.
    try testing.expectEqual(@as(usize, 6), review.rows.len);
    try testing.expect(review.rows[0] == .header);
    try testing.expectEqual(git.Group.staged, review.rows[0].header);
    // Selection lands on the first change row, not the header.
    try testing.expectEqual(@as(usize, 1), review.selected);
    try testing.expectEqualStrings("a.zig", review.changeset.changes[review.selectedChange().?].path);
}

test "selection movement skips headers" {
    var review = try Review.init(testing.allocator, try buildChangeSet(testing.allocator));
    defer review.deinit();

    review.moveSelection(1, 20); // a.zig -> b.zig (skipping the Unstaged header)
    try testing.expectEqualStrings("b.zig", review.changeset.changes[review.selectedChange().?].path);
    review.moveSelection(1, 20); // b.zig -> c.txt (skipping the Untracked header)
    try testing.expectEqualStrings("c.txt", review.changeset.changes[review.selectedChange().?].path);
    review.moveSelection(-2, 20);
    try testing.expectEqualStrings("a.zig", review.changeset.changes[review.selectedChange().?].path);
}

test "file navigation stays within the active group" {
    var review = try Review.init(testing.allocator, try buildChangeSet(testing.allocator));
    defer review.deinit();
    // Only one change in the staged group, so ] f reports a boundary.
    try testing.expect(!review.moveFile(true, 20));
    try testing.expectEqualStrings("a.zig", review.changeset.changes[review.selectedChange().?].path);
}

test "hunk and changed-line cursors move through the selected diff" {
    var review = try Review.init(testing.allocator, try buildChangeSet(testing.allocator));
    defer review.deinit();
    review.moveSelection(1, 20); // select b.zig, which has a diff

    try testing.expectEqual(@as(usize, 0), review.diff_line);
    try testing.expect(review.moveChangedLine(true)); // context(0) -> deletion(1)
    try testing.expectEqual(@as(usize, 1), review.diff_line);
    try testing.expect(review.moveChangedLine(true)); // -> addition(2)
    try testing.expectEqual(@as(usize, 2), review.diff_line);
    try testing.expect(!review.moveChangedLine(true)); // no more changed lines

    const target = review.sourceTarget().?;
    try testing.expectEqualStrings("b.zig", target.path);
    try testing.expectEqual(@as(usize, 2), target.line); // addition -> new side line 2
}
