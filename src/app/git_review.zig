//! State for the Git review context: the grouped change list shown in the
//! sidebar and the cursor used to navigate the selected change's diff. Pure and
//! Skaut-owned; it takes ownership of a loaded `ChangeSet` and never touches git.

const std = @import("std");
const git = @import("../model/git.zig");
const review_model = @import("../model/review.zig");
const anchor_model = @import("../model/anchor.zig");

/// One sidebar tree row: a Git group, a repository directory, or a change.
pub const Row = union(enum) {
    header: git.Group,
    directory: Directory,
    change: usize, // index into `changeset.changes`

    pub const Directory = struct {
        group: git.Group,
        /// Repository-relative path borrowed from one of the owned changes.
        path: []const u8,
        /// Zero-based nesting below the Git group.
        depth: usize,
    };
};

pub const Review = struct {
    allocator: std.mem.Allocator,
    changeset: git.ChangeSet,
    /// Complete tree in display order. `visible` indexes this slice.
    rows: []Row,
    visible: std.ArrayListUnmanaged(usize) = .empty,
    /// Expansion state aligned with `rows`; only directory entries use it.
    expanded: []bool,
    /// Index into `visible`.
    selected: usize = 0,
    scroll: usize = 0,
    /// Cursor within the selected change's diff (index into its `FileDiff.lines`).
    diff_line: usize = 0,
    diff_scroll: usize = 0,
    /// Additional visual-row offset from `diff_scroll`, used to page through
    /// wrapped inline comments without changing the selected diff line.
    diff_visual_scroll: usize = 0,
    /// Selection anchor in the diff (for a multi-line note); null = single line.
    diff_anchor: ?usize = null,

    /// The group order shown in the sidebar.
    const group_order = [_]git.Group{ .staged, .unstaged, .untracked };

    /// Build a review from a loaded change set, taking ownership of it.
    pub fn init(allocator: std.mem.Allocator, changeset: git.ChangeSet) !Review {
        var rows: std.ArrayList(Row) = .empty;
        errdefer rows.deinit(allocator);
        for (group_order) |group| {
            if (changeset.groupCount(group) == 0) continue;
            try rows.append(allocator, .{ .header = group });

            var indices: std.ArrayList(usize) = .empty;
            defer indices.deinit(allocator);
            for (changeset.changes, 0..) |change, index| {
                if (change.group == group) try indices.append(allocator, index);
            }
            std.mem.sort(usize, indices.items, changeset.changes, struct {
                fn lessThan(items: []git.Change, left: usize, right: usize) bool {
                    return std.mem.lessThan(u8, items[left].path, items[right].path);
                }
            }.lessThan);

            var directories = std.StringHashMap(void).init(allocator);
            defer directories.deinit();
            for (indices.items) |index| {
                const path = changeset.changes[index].path;
                var cursor: usize = 0;
                var depth: usize = 0;
                while (std.mem.indexOfScalarPos(u8, path, cursor, std.fs.path.sep)) |separator| {
                    const directory_path = path[0..separator];
                    if (!directories.contains(directory_path)) {
                        try directories.put(directory_path, {});
                        try rows.append(allocator, .{ .directory = .{
                            .group = group,
                            .path = directory_path,
                            .depth = depth,
                        } });
                    }
                    cursor = separator + 1;
                    depth += 1;
                }
                try rows.append(allocator, .{ .change = index });
            }
        }
        const owned_rows = try rows.toOwnedSlice(allocator);
        errdefer allocator.free(owned_rows);
        const expanded = try allocator.alloc(bool, owned_rows.len);
        errdefer allocator.free(expanded);
        @memset(expanded, true);
        var review: Review = .{
            .allocator = allocator,
            .changeset = changeset,
            .rows = owned_rows,
            .expanded = expanded,
        };
        errdefer review.visible.deinit(allocator);
        try review.rebuildVisible(null);
        review.selected = review.firstChangeRow() orelse 0;
        return review;
    }

    pub fn deinit(self: *Review) void {
        self.visible.deinit(self.allocator);
        self.allocator.free(self.expanded);
        self.allocator.free(self.rows);
        self.changeset.deinit();
        self.* = undefined;
    }

    /// Carry stable VCS navigation state into a replacement snapshot. Selection
    /// follows the same Git group and repository-relative path when it remains;
    /// otherwise the replacement keeps its normal first-change fallback.
    pub fn restorePosition(self: *Review, previous: Review) void {
        // Restore directory state by stable Git group and repository path. New
        // directories retain the expanded default.
        var old_expansion = [_]std.StringHashMap(bool){
            std.StringHashMap(bool).init(self.allocator),
            std.StringHashMap(bool).init(self.allocator),
            std.StringHashMap(bool).init(self.allocator),
        };
        defer for (&old_expansion) |*map| map.deinit();
        for (previous.rows, 0..) |row, row_index| switch (row) {
            .directory => |directory| old_expansion[groupIndex(directory.group)].put(directory.path, previous.expanded[row_index]) catch return,
            else => {},
        };
        for (self.rows, 0..) |row, row_index| switch (row) {
            .directory => |directory| if (old_expansion[groupIndex(directory.group)].get(directory.path)) |expanded| {
                self.expanded[row_index] = expanded;
            },
            else => {},
        };
        self.rebuildVisible(null) catch return;

        const previous_row_index = previous.selectedRowIndex() orelse return;
        const previous_row = previous.rows[previous_row_index];
        for (self.visible.items, 0..) |row_index, visible_index| {
            const matches = switch (self.rows[row_index]) {
                .header => false,
                .directory => |directory| switch (previous_row) {
                    .directory => |old| directory.group == old.group and std.mem.eql(u8, directory.path, old.path),
                    else => false,
                },
                .change => |change_index| switch (previous_row) {
                    .change => |previous_change_index| blk: {
                        const change = self.changeset.changes[change_index];
                        const old = previous.changeset.changes[previous_change_index];
                        break :blk change.group == old.group and std.mem.eql(u8, change.path, old.path);
                    },
                    else => false,
                },
            };
            if (!matches) continue;
            self.selected = visible_index;
            self.scroll = @min(previous.scroll, self.visible.items.len -| 1);
            if (self.rows[row_index] == .change) {
                const change_index = self.rows[row_index].change;
                const diff = &self.changeset.diffs[change_index];
                self.diff_line = @min(previous.diff_line, diff.lines.len -| 1);
                self.diff_scroll = @min(previous.diff_scroll, diff.lines.len -| 1);
                self.diff_visual_scroll = previous.diff_visual_scroll;
            }
            return;
        }
    }

    pub fn isEmpty(self: Review) bool {
        return self.changeset.isEmpty();
    }

    /// The change index the selection is on, if it is on a change row.
    pub fn selectedChange(self: Review) ?usize {
        const row_index = self.selectedRowIndex() orelse return null;
        return switch (self.rows[row_index]) {
            .change => |index| index,
            else => null,
        };
    }

    /// The diff for the selected change, if any.
    pub fn selectedDiff(self: Review) ?*const git.FileDiff {
        const index = self.selectedChange() orelse return null;
        return &self.changeset.diffs[index];
    }

    pub fn selectedGroup(self: Review) ?git.Group {
        const row_index = self.selectedRowIndex() orelse return null;
        return switch (self.rows[row_index]) {
            .header => |group| group,
            .directory => |directory| directory.group,
            .change => |index| self.changeset.changes[index].group,
        };
    }

    /// Move through visible directory and change rows, skipping group headers.
    pub fn moveSelection(self: *Review, delta: isize, viewport_rows: usize) void {
        if (self.visible.items.len == 0) return;
        var current: isize = @intCast(self.selected);
        const last: isize = @intCast(self.visible.items.len - 1);
        const step: isize = if (delta < 0) -1 else 1;
        var remaining = @abs(delta);
        while (remaining > 0) : (remaining -= 1) {
            var probe = current + step;
            while (probe >= 0 and probe <= last and self.rows[self.visible.items[@intCast(probe)]] == .header) probe += step;
            if (probe < 0 or probe > last) break;
            current = probe;
        }
        self.selected = @intCast(current);
        self.resetDiffCursor();
        self.ensureVisible(viewport_rows);
    }

    /// Select a visible directory or change row (for mouse clicks).
    pub fn selectRow(self: *Review, visible_index: usize, viewport_rows: usize) void {
        if (visible_index >= self.visible.items.len) return;
        if (self.rows[self.visible.items[visible_index]] == .header) return;
        self.selected = visible_index;
        self.resetDiffCursor();
        self.ensureVisible(viewport_rows);
    }

    /// Select a changed file and, when available, its anchored diff line.
    pub fn selectThreadAnchor(
        self: *Review,
        group: git.Group,
        path: []const u8,
        side: ?review_model.Side,
        start_line: ?usize,
        viewport_rows: usize,
    ) bool {
        for (self.rows, 0..) |row, row_index| switch (row) {
            .header, .directory => {},
            .change => |change_index| {
                const change = self.changeset.changes[change_index];
                if (change.group != group or !std.mem.eql(u8, change.path, path)) continue;
                // A thread may target a file below a directory the reviewer
                // collapsed after creating it. Reveal all of its ancestors.
                for (self.rows, 0..) |candidate, candidate_index| switch (candidate) {
                    .directory => |directory| if (directory.group == group and
                        change.path.len > directory.path.len and
                        std.mem.startsWith(u8, change.path, directory.path) and
                        change.path[directory.path.len] == std.fs.path.sep)
                    {
                        self.expanded[candidate_index] = true;
                    },
                    else => {},
                };
                self.rebuildVisible(row_index) catch return false;
                self.resetDiffCursor();
                if (side) |anchor_side| if (start_line) |line_number| {
                    const diff = &self.changeset.diffs[change_index];
                    for (diff.lines, 0..) |line, line_index| {
                        const number = if (anchor_side == .new) line.new_line else line.old_line;
                        if (number != null and number.? == line_number) {
                            self.diff_line = line_index;
                            break;
                        }
                    }
                };
                self.ensureVisible(viewport_rows);
                self.ensureDiffVisible(viewport_rows);
                return true;
            },
        };
        return false;
    }

    /// `[ f` / `] f`: move among change files within the active group.
    /// Returns false at a group boundary (the caller may report it).
    pub fn moveFile(self: *Review, forward: bool, viewport_rows: usize) bool {
        const group = self.selectedGroup() orelse return false;
        const step: isize = if (forward) 1 else -1;
        var probe: isize = @as(isize, @intCast(self.selected)) + step;
        const last: isize = @intCast(self.visible.items.len - 1);
        while (probe >= 0 and probe <= last) : (probe += step) {
            switch (self.rows[self.visible.items[@intCast(probe)]]) {
                .change => |index| {
                    if (self.changeset.changes[index].group != group) return false;
                    self.selected = @intCast(probe);
                    self.resetDiffCursor();
                    self.ensureVisible(viewport_rows);
                    return true;
                },
                .header => return false,
                .directory => {},
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

    /// Map the selected diff line to the current source file. Deletions have no
    /// new-side line, so use the nearest surviving new-side position rather
    /// than reopening a historical old path.
    pub fn bookmarkTarget(self: Review) ?SourceTarget {
        const change_index = self.selectedChange() orelse return null;
        const change = self.changeset.changes[change_index];
        if (change.kind == .deleted) return null;
        const diff = &self.changeset.diffs[change_index];
        if (diff.lines.len == 0) return null;
        const selected = @min(self.diff_line, diff.lines.len - 1);
        if (diff.lines[selected].new_line) |line| return .{ .path = change.path, .line = line };
        var forward = selected + 1;
        while (forward < diff.lines.len) : (forward += 1) {
            if (diff.lines[forward].new_line) |line| return .{ .path = change.path, .line = line };
        }
        var backward = selected;
        while (backward > 0) {
            backward -= 1;
            if (diff.lines[backward].new_line) |line| return .{ .path = change.path, .line = line + 1 };
        }
        return .{ .path = change.path, .line = 1 };
    }

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
        self.diff_visual_scroll = 0;
        self.ensureDiffVisible(viewport_rows);
    }

    pub fn scrollDiffVisual(self: *Review, delta: isize) void {
        if (delta < 0) {
            self.diff_visual_scroll -|= @abs(delta);
        } else {
            self.diff_visual_scroll +|= @intCast(delta);
        }
    }

    /// Keep the diff cursor within the visible window.
    pub fn ensureDiffVisible(self: *Review, viewport_rows: usize) void {
        self.diff_visual_scroll = 0;
        if (viewport_rows == 0) return;
        if (self.diff_line < self.diff_scroll) self.diff_scroll = self.diff_line;
        if (self.diff_line >= self.diff_scroll + viewport_rows) {
            self.diff_scroll = self.diff_line - viewport_rows + 1;
        }
    }

    fn selectedRowIndex(self: Review) ?usize {
        if (self.selected >= self.visible.items.len) return null;
        return self.visible.items[self.selected];
    }

    fn firstChangeRow(self: Review) ?usize {
        for (self.visible.items, 0..) |row_index, visible_index| {
            if (self.rows[row_index] == .change) return visible_index;
        }
        return null;
    }

    /// Collapse the selected directory, or move to its parent directory.
    pub fn collapseOrParent(self: *Review, viewport_rows: usize) !void {
        const row_index = self.selectedRowIndex() orelse return;
        const selected_row = self.rows[row_index];
        if (selected_row == .directory and self.expanded[row_index]) {
            self.expanded[row_index] = false;
            try self.rebuildVisible(row_index);
            self.ensureVisible(viewport_rows);
            return;
        }
        const group = self.selectedGroup() orelse return;
        const depth = rowDepth(self, selected_row);
        if (depth == 0) return;
        var probe = row_index;
        while (probe > 0) {
            probe -= 1;
            switch (self.rows[probe]) {
                .directory => |directory| if (directory.group == group and directory.depth + 1 == depth) {
                    self.selectVisibleRow(probe);
                    self.ensureVisible(viewport_rows);
                    return;
                },
                .header => return,
                .change => {},
            }
        }
    }

    /// Expand the selected directory, or move to its first visible child.
    pub fn expandOrChild(self: *Review, viewport_rows: usize) !void {
        const row_index = self.selectedRowIndex() orelse return;
        const directory = switch (self.rows[row_index]) {
            .directory => |value| value,
            else => return,
        };
        if (!self.expanded[row_index]) {
            self.expanded[row_index] = true;
            try self.rebuildVisible(row_index);
        } else if (self.selected + 1 < self.visible.items.len) {
            const child_index = self.visible.items[self.selected + 1];
            if (rowDepth(self, self.rows[child_index]) == directory.depth + 1) self.selected += 1;
        }
        self.ensureVisible(viewport_rows);
    }

    fn rebuildVisible(self: *Review, preserve_row: ?usize) !void {
        self.visible.clearRetainingCapacity();
        var collapsed_group: ?git.Group = null;
        var collapsed_depth: usize = 0;
        for (self.rows, 0..) |row, row_index| {
            switch (row) {
                .header => {
                    collapsed_group = null;
                    try self.visible.append(self.allocator, row_index);
                },
                .directory => |directory| {
                    if (collapsed_group) |group| {
                        if (group == directory.group and directory.depth > collapsed_depth) continue;
                        collapsed_group = null;
                    }
                    try self.visible.append(self.allocator, row_index);
                    if (!self.expanded[row_index]) {
                        collapsed_group = directory.group;
                        collapsed_depth = directory.depth;
                    }
                },
                .change => |change_index| {
                    if (collapsed_group) |group| {
                        const change = self.changeset.changes[change_index];
                        if (group == change.group and pathDepth(change.path) > collapsed_depth) continue;
                        collapsed_group = null;
                    }
                    try self.visible.append(self.allocator, row_index);
                },
            }
        }
        if (preserve_row) |row_index| self.selectVisibleRow(row_index) else self.selected = @min(self.selected, self.visible.items.len -| 1);
    }

    fn selectVisibleRow(self: *Review, row_index: usize) void {
        for (self.visible.items, 0..) |visible_row, visible_index| {
            if (visible_row == row_index) {
                self.selected = visible_index;
                return;
            }
        }
        self.selected = @min(self.selected, self.visible.items.len -| 1);
    }

    fn rowDepth(self: *const Review, row: Row) usize {
        return switch (row) {
            .header => 0,
            .directory => |directory| directory.depth,
            .change => |index| pathDepth(self.changeset.changes[index].path),
        };
    }

    fn pathDepth(path: []const u8) usize {
        return std.mem.count(u8, path, &.{std.fs.path.sep});
    }

    fn groupIndex(group: git.Group) usize {
        return switch (group) {
            .staged => 0,
            .unstaged => 1,
            .untracked => 2,
        };
    }

    /// Select the active diff line linewise. Repeating the operation extends
    /// the active end down by one line, matching document `x` behavior.
    pub fn selectDiffLine(self: *Review, viewport_rows: usize) void {
        const diff = self.selectedDiff() orelse return;
        if (diff.lines.len == 0) return;
        if (self.diff_anchor == null) {
            self.diff_anchor = self.diff_line;
        } else {
            self.moveDiffLine(1, viewport_rows);
        }
    }

    pub fn collapseDiffSelection(self: *Review) void {
        const diff = self.selectedDiff() orelse return;
        if (diff.lines.len != 0) self.diff_anchor = self.diff_line;
    }

    pub fn clearDiffSelection(self: *Review) bool {
        if (self.diff_anchor == null) return false;
        self.diff_anchor = null;
        return true;
    }

    pub fn reverseDiffSelection(self: *Review) void {
        if (self.diff_anchor) |anchor| {
            self.diff_anchor = self.diff_line;
            self.diff_line = anchor;
        }
    }

    pub fn diffLineSelected(self: Review, index: usize) bool {
        if (self.diff_anchor == null) return false;
        const selection = self.diffSelection();
        return index >= selection.start and index <= selection.end;
    }

    /// The inclusive diff-line range currently selected.
    pub fn diffSelection(self: Review) struct { start: usize, end: usize } {
        const anchor = self.diff_anchor orelse self.diff_line;
        return .{ .start = @min(anchor, self.diff_line), .end = @max(anchor, self.diff_line) };
    }

    /// The captured anchor for a line note over the current diff selection, or
    /// null when nothing textual is selected. `excerpt` is owned by the caller.
    pub const AnchorDraft = struct {
        path: []const u8,
        group: git.Group,
        side: review_model.Side,
        start_line: usize,
        end_line: usize,
        blob: ?[]const u8,
        excerpt: []u8,
        context: anchor_model.Context,
    };

    pub fn captureAnchor(self: Review, allocator: std.mem.Allocator) !?AnchorDraft {
        const change_index = self.selectedChange() orelse return null;
        const change = self.changeset.changes[change_index];
        const diff = &self.changeset.diffs[change_index];
        if (diff.lines.len == 0) return null;
        const selection = self.diffSelection();
        const lines = diff.lines[selection.start .. selection.end + 1];

        var has_addition = false;
        var has_deletion = false;
        for (lines) |line| {
            if (line.kind == .addition) has_addition = true;
            if (line.kind == .deletion) has_deletion = true;
        }
        // A thread anchor belongs to exactly one diff side. Context may join
        // changed lines on that side, but a mixed deletion/addition range is
        // ambiguous and must be narrowed by the reviewer.
        if (has_deletion and has_addition) return null;
        const side: review_model.Side = if (has_deletion) .old else .new;

        var start_line: ?usize = null;
        var end_line: usize = 0;
        for (lines) |line| {
            const number = if (side == .new) line.new_line else line.old_line;
            if (number) |value| {
                if (start_line == null) start_line = value;
                end_line = value;
            }
        }

        var excerpt: std.ArrayList(u8) = .empty;
        errdefer excerpt.deinit(allocator);
        for (lines) |line| {
            const marker: u8 = switch (line.kind) {
                .addition => '+',
                .deletion => '-',
                .context => ' ',
            };
            try excerpt.append(allocator, marker);
            try excerpt.appendSlice(allocator, diff.text[line.text.start..line.text.end]);
            try excerpt.append(allocator, '\n');
        }

        var side_bytes: std.ArrayList(u8) = .empty;
        defer side_bytes.deinit(allocator);
        var target_start: ?usize = null;
        var target_end: usize = 0;
        var previous_line: ?usize = null;
        for (diff.lines, 0..) |line, index| {
            const number = if (side == .new) line.new_line else line.old_line;
            if (number == null) continue;
            if (previous_line) |previous| {
                if (number.? != previous + 1) try side_bytes.append(allocator, 0);
            }
            previous_line = number.?;
            if (index >= selection.start and index <= selection.end and target_start == null)
                target_start = side_bytes.items.len;
            try side_bytes.appendSlice(allocator, diff.text[line.text.start..line.text.end]);
            try side_bytes.append(allocator, '\n');
            if (index >= selection.start and index <= selection.end) target_end = side_bytes.items.len;
        }
        const context = try anchor_model.capture(allocator, side_bytes.items, target_start orelse 0, target_end);
        errdefer allocator.free(context.bytes);

        return .{
            .path = change.path,
            .group = change.group,
            .side = side,
            .start_line = start_line orelse 1,
            .end_line = if (start_line == null) 1 else end_line,
            .blob = change.sideBlob(side == .new),
            .excerpt = try excerpt.toOwnedSlice(allocator),
            .context = context,
        };
    }

    fn resetDiffCursor(self: *Review) void {
        self.diff_line = 0;
        self.diff_scroll = 0;
        self.diff_visual_scroll = 0;
        self.diff_anchor = null;
    }

    fn ensureVisible(self: *Review, viewport_rows: usize) void {
        if (viewport_rows == 0) return;
        if (self.selected < self.scroll) self.scroll = self.selected;
        if (self.selected >= self.scroll + viewport_rows) self.scroll = self.selected - viewport_rows + 1;
    }
};

// --- Tests ---------------------------------------------------------------

pub fn sideDocument(allocator: std.mem.Allocator, diff: git.FileDiff, side: review_model.Side) ![]u8 {
    var bytes: std.ArrayList(u8) = .empty;
    errdefer bytes.deinit(allocator);
    var previous_line: ?usize = null;
    for (diff.lines) |line| {
        const number = if (side == .new) line.new_line else line.old_line;
        if (number == null) continue;
        if (previous_line) |previous| {
            if (number.? != previous + 1) try bytes.append(allocator, 0);
        }
        previous_line = number.?;
        try bytes.appendSlice(allocator, diff.text[line.text.start..line.text.end]);
        try bytes.append(allocator, '\n');
    }
    return bytes.toOwnedSlice(allocator);
}

pub fn sideLineAtOffset(diff: git.FileDiff, side: review_model.Side, offset: usize) ?usize {
    var cursor: usize = 0;
    var previous_line: ?usize = null;
    for (diff.lines) |line| {
        const number = if (side == .new) line.new_line else line.old_line;
        if (number == null) continue;
        if (previous_line) |previous| {
            if (number.? != previous + 1) cursor += 1;
        }
        previous_line = number.?;
        const length = line.text.end - line.text.start + 1;
        if (offset < cursor + length) return number;
        cursor += length;
    }
    return null;
}

pub fn changeFingerprint(allocator: std.mem.Allocator, change: git.Change, diff: git.FileDiff) ![]u8 {
    return changeFingerprintForPath(allocator, change, diff, change.path);
}

pub fn changeFingerprintForPath(
    allocator: std.mem.Allocator,
    change: git.Change,
    diff: git.FileDiff,
    logical_path: []const u8,
) ![]u8 {
    const Fingerprint = struct {
        path: []const u8,
        content: git.ContentKind,
        old_mode: u32,
        new_mode: u32,
        old_blob: ?[]const u8,
        new_blob: ?[]const u8,
        diff: []const u8,
    };
    return std.json.Stringify.valueAlloc(allocator, Fingerprint{
        .path = logical_path,
        .content = change.content,
        .old_mode = change.old_mode,
        .new_mode = change.new_mode,
        .old_blob = if (change.content == .text) null else change.old_blob,
        .new_blob = if (change.content == .text) null else change.new_blob,
        .diff = diff.text,
    }, .{});
}

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

fn buildNestedChangeSet(allocator: std.mem.Allocator) !git.ChangeSet {
    const paths = [_][]const u8{ "src/app/commands.zig", "README.md", "src/state.zig", "lib/new.zig" };
    var changes = try allocator.alloc(git.Change, paths.len);
    for (paths, 0..) |path, index| {
        changes[index] = .{
            .group = .unstaged,
            .kind = if (index == 3) .renamed else .modified,
            .content = .text,
            .path = try allocator.dupe(u8, path),
            .old_path = if (index == 3) try allocator.dupe(u8, "old/location.zig") else null,
        };
    }
    const diffs = try allocator.alloc(git.FileDiff, paths.len);
    for (diffs) |*diff| diff.* = .{
        .allocator = allocator,
        .text = try allocator.alloc(u8, 0),
        .hunks = try allocator.alloc(git.Hunk, 0),
        .lines = try allocator.alloc(git.DiffLine, 0),
    };
    return .{ .allocator = allocator, .changes = changes, .diffs = diffs };
}

fn findDirectoryRow(review: Review, group: git.Group, path: []const u8) ?usize {
    for (review.rows, 0..) |row, index| switch (row) {
        .directory => |directory| if (directory.group == group and std.mem.eql(u8, directory.path, path)) return index,
        else => {},
    };
    return null;
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

test "review preserves parent directories and places renames at their destination" {
    var review = try Review.init(testing.allocator, try buildNestedChangeSet(testing.allocator));
    defer review.deinit();

    const src = findDirectoryRow(review, .unstaged, "src").?;
    const app = findDirectoryRow(review, .unstaged, "src/app").?;
    const lib = findDirectoryRow(review, .unstaged, "lib").?;
    try testing.expectEqual(@as(usize, 0), review.rows[src].directory.depth);
    try testing.expectEqual(@as(usize, 1), review.rows[app].directory.depth);
    try testing.expect(lib < src);

    var renamed_row: ?usize = null;
    for (review.rows, 0..) |row, index| switch (row) {
        .change => |change_index| {
            if (review.changeset.changes[change_index].kind == .renamed) renamed_row = index;
        },
        else => {},
    };
    try testing.expect(renamed_row.? > lib and renamed_row.? < src);
}

test "Git directories collapse expand and remain selectable" {
    var review = try Review.init(testing.allocator, try buildNestedChangeSet(testing.allocator));
    defer review.deinit();

    const src = findDirectoryRow(review, .unstaged, "src").?;
    review.selectVisibleRow(src);
    const expanded_count = review.visible.items.len;
    try review.collapseOrParent(20);
    try testing.expect(!review.expanded[src]);
    try testing.expect(review.visible.items.len < expanded_count);
    try testing.expect(review.rows[review.selectedRowIndex().?] == .directory);
    try testing.expectEqualStrings("src", review.rows[review.selectedRowIndex().?].directory.path);

    try review.expandOrChild(20);
    try testing.expect(review.expanded[src]);
    try testing.expectEqual(expanded_count, review.visible.items.len);
    try review.expandOrChild(20);
    try testing.expectEqualStrings("src/app", review.rows[review.selectedRowIndex().?].directory.path);
}

test "selecting a thread anchor reveals a change below collapsed directories" {
    var review = try Review.init(testing.allocator, try buildNestedChangeSet(testing.allocator));
    defer review.deinit();
    const src = findDirectoryRow(review, .unstaged, "src").?;
    review.selectVisibleRow(src);
    try review.collapseOrParent(20);

    try testing.expect(review.selectThreadAnchor(.unstaged, "src/app/commands.zig", null, null, 20));
    try testing.expect(review.expanded[src]);
    try testing.expectEqualStrings("src/app/commands.zig", review.changeset.changes[review.selectedChange().?].path);
}

test "Git directory expansion survives refresh" {
    var previous = try Review.init(testing.allocator, try buildNestedChangeSet(testing.allocator));
    defer previous.deinit();
    const previous_src = findDirectoryRow(previous, .unstaged, "src").?;
    previous.selectVisibleRow(previous_src);
    try previous.collapseOrParent(20);

    var replacement = try Review.init(testing.allocator, try buildNestedChangeSet(testing.allocator));
    defer replacement.deinit();
    replacement.restorePosition(previous);
    const replacement_src = findDirectoryRow(replacement, .unstaged, "src").?;
    try testing.expect(!replacement.expanded[replacement_src]);
    try testing.expectEqualStrings("src", replacement.rows[replacement.selectedRowIndex().?].directory.path);
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

test "visual diff paging reaches wrapped rows and cursor movement resets it" {
    var review = try Review.init(testing.allocator, try buildChangeSet(testing.allocator));
    defer review.deinit();
    review.moveSelection(1, 20); // select b.zig

    review.scrollDiffVisual(12);
    try testing.expectEqual(@as(usize, 12), review.diff_visual_scroll);
    review.scrollDiffVisual(-5);
    try testing.expectEqual(@as(usize, 7), review.diff_visual_scroll);
    review.scrollDiffVisual(-20);
    try testing.expectEqual(@as(usize, 0), review.diff_visual_scroll);

    review.scrollDiffVisual(4);
    review.moveDiffLine(1, 20);
    try testing.expectEqual(@as(usize, 0), review.diff_visual_scroll);
}

test "linewise diff selection extends collapses reverses and projects its range" {
    var review = try Review.init(testing.allocator, try buildChangeSet(testing.allocator));
    defer review.deinit();
    review.moveSelection(1, 20); // select b.zig

    review.selectDiffLine(20);
    try testing.expect(review.diffLineSelected(0));
    try testing.expect(!review.diffLineSelected(1));
    review.selectDiffLine(20);
    try testing.expectEqual(@as(usize, 1), review.diff_line);
    try testing.expect(review.diffLineSelected(0));
    try testing.expect(review.diffLineSelected(1));

    review.reverseDiffSelection();
    try testing.expectEqual(@as(usize, 0), review.diff_line);
    try testing.expectEqual(@as(usize, 1), review.diff_anchor.?);
    review.collapseDiffSelection();
    try testing.expectEqual(review.diff_line, review.diff_anchor.?);
    try testing.expect(review.diffLineSelected(0));
    try testing.expect(!review.diffLineSelected(1));
    try testing.expect(review.clearDiffSelection());
    try testing.expect(!review.diffLineSelected(0));
    try testing.expect(!review.clearDiffSelection());
}

test "bookmark target maps a deletion to current source" {
    var review_state = try Review.init(testing.allocator, try buildChangeSet(testing.allocator));
    defer review_state.deinit();
    review_state.moveSelection(1, 20); // b.zig
    review_state.diff_line = 1; // deletion with no new-side line
    const target = review_state.bookmarkTarget().?;
    try testing.expectEqualStrings("b.zig", target.path);
    try testing.expectEqual(@as(usize, 2), target.line);
}

test "captureAnchor derives side, line range, and excerpt from the selection" {
    var review_state = try Review.init(testing.allocator, try buildChangeSet(testing.allocator));
    defer review_state.deinit();
    review_state.moveSelection(1, 20); // select b.zig, which has a diff

    // A mixed deletion/addition selection is refused because it spans sides.
    review_state.diff_anchor = review_state.diff_line;
    review_state.diff_line = 2;
    try testing.expect((try review_state.captureAnchor(testing.allocator)) == null);

    // Narrow to the addition on the new side.
    review_state.diff_anchor = null;
    const anchor = (try review_state.captureAnchor(testing.allocator)).?;
    defer testing.allocator.free(anchor.excerpt);
    defer testing.allocator.free(anchor.context.bytes);
    try testing.expectEqualStrings("b.zig", anchor.path);
    // The selection contains an addition, so it anchors to the new side.
    try testing.expectEqual(review_model.Side.new, anchor.side);
    try testing.expectEqual(@as(usize, 2), anchor.start_line);
    try testing.expectEqual(@as(usize, 2), anchor.end_line);
    try testing.expect(anchor.excerpt.len != 0);
    try testing.expect(anchor.context.bytes.len != 0);
    try testing.expect(anchor.context.target_end > anchor.context.target_start);
}
