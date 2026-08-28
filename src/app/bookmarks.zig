//! In-memory private bookmark state for one canonical repository identity.

const std = @import("std");
const bookmark = @import("../model/bookmark.zig");
const anchor = @import("../model/anchor.zig");

pub const Bookmarks = struct {
    allocator: std.mem.Allocator,
    repository_path: []u8,
    items: std.ArrayListUnmanaged(bookmark.Bookmark) = .empty,
    next_id: u64 = 1,
    selected: usize = 0,
    scroll: usize = 0,
    dirty: bool = false,

    pub fn init(allocator: std.mem.Allocator, repository_path: []const u8) !Bookmarks {
        return .{
            .allocator = allocator,
            .repository_path = try allocator.dupe(u8, repository_path),
        };
    }

    pub fn fromStored(
        allocator: std.mem.Allocator,
        expected_repository_path: []const u8,
        persisted: bookmark.Stored,
    ) !Bookmarks {
        var self = try init(allocator, expected_repository_path);
        errdefer self.deinit();
        self.next_id = persisted.next_id;
        for (persisted.bookmarks) |item| {
            const owned_path = try allocator.dupe(u8, item.path);
            errdefer allocator.free(owned_path);
            const owned_label = try allocator.dupe(u8, item.label);
            errdefer allocator.free(owned_label);
            const owned_context = try allocator.dupe(u8, item.context.bytes);
            errdefer allocator.free(owned_context);
            try self.items.append(allocator, .{
                .id = item.id,
                .path = owned_path,
                .line = item.line,
                .column = item.column,
                .source_offset = item.source_offset,
                .line_offset = item.line_offset,
                .context = .{
                    .bytes = owned_context,
                    .original_start = item.context.original_start,
                    .target_start = item.context.target_start,
                    .target_end = item.context.target_end,
                },
                .label = owned_label,
                .status = item.status,
            });
            self.next_id = @max(self.next_id, item.id +| 1);
        }
        return self;
    }

    pub fn deinit(self: *Bookmarks) void {
        for (self.items.items) |item| {
            self.allocator.free(item.path);
            self.allocator.free(item.label);
            self.allocator.free(item.context.bytes);
        }
        self.items.deinit(self.allocator);
        self.allocator.free(self.repository_path);
        self.* = undefined;
    }

    pub fn stored(self: Bookmarks) bookmark.Stored {
        return .{
            .next_id = self.next_id,
            .bookmarks = self.items.items,
        };
    }

    pub fn add(
        self: *Bookmarks,
        path: []const u8,
        line: usize,
        column: usize,
        source_offset: usize,
        context: anchor.Context,
        label: []const u8,
    ) !void {
        if (!bookmark.validLabel(label)) return error.InvalidLabel;
        if (context.bytes.len == 0 or context.target_start > context.target_end or context.target_end > context.bytes.len)
            return error.InvalidAnchor;
        const target_source_start = context.targetOffset(context.original_start);
        if (source_offset < target_source_start or source_offset - target_source_start > context.target_end - context.target_start)
            return error.InvalidAnchor;
        const owned_path = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(owned_path);
        const owned_label = try self.allocator.dupe(u8, label);
        errdefer self.allocator.free(owned_label);
        const owned_context = try self.allocator.dupe(u8, context.bytes);
        errdefer self.allocator.free(owned_context);
        try self.items.append(self.allocator, .{
            .id = self.next_id,
            .path = owned_path,
            .line = @max(line, 1),
            .column = column,
            .source_offset = source_offset,
            .line_offset = source_offset -| context.targetOffset(context.original_start),
            .context = .{
                .bytes = owned_context,
                .original_start = context.original_start,
                .target_start = context.target_start,
                .target_end = context.target_end,
            },
            .label = owned_label,
            .status = .current,
        });
        self.next_id +|= 1;
        self.selected = self.items.items.len - 1;
        self.dirty = true;
    }

    pub fn deleteSelected(self: *Bookmarks) void {
        if (self.items.items.len == 0) return;
        const removed = self.items.orderedRemove(self.selected);
        self.allocator.free(removed.path);
        self.allocator.free(removed.label);
        self.allocator.free(removed.context.bytes);
        if (self.selected >= self.items.items.len and self.selected > 0) self.selected -= 1;
        self.dirty = true;
        self.ensureVisible(20);
    }

    pub fn selectedBookmark(self: *Bookmarks) ?*bookmark.Bookmark {
        if (self.selected >= self.items.items.len) return null;
        return &self.items.items[self.selected];
    }

    pub fn moveSelection(self: *Bookmarks, delta: isize, viewport_rows: usize) void {
        if (self.items.items.len == 0) return;
        const current: isize = @intCast(self.selected);
        self.selected = @intCast(std.math.clamp(current + delta, 0, @as(isize, @intCast(self.items.items.len - 1))));
        self.ensureVisible(viewport_rows);
    }

    pub fn selectVisible(self: *Bookmarks, visible_index: usize, viewport_rows: usize) void {
        const index = self.scroll + visible_index;
        if (index >= self.items.items.len) return;
        self.selected = index;
        self.ensureVisible(viewport_rows);
    }

    pub fn markSelectedOutdated(self: *Bookmarks) void {
        const item = self.selectedBookmark() orelse return;
        if (item.status == .outdated) return;
        item.status = .outdated;
        self.dirty = true;
    }

    pub fn markSelectedCurrent(self: *Bookmarks) void {
        const item = self.selectedBookmark() orelse return;
        if (item.status == .current) return;
        item.status = .current;
        self.dirty = true;
    }

    pub fn reanchorPath(self: *Bookmarks, path: []const u8, source: []const u8) void {
        for (self.items.items) |*item| {
            if (!std.mem.eql(u8, item.path, path)) continue;
            switch (anchor.match(item.context, source)) {
                .retained => {
                    if (item.status == .outdated) {
                        item.status = .current;
                        self.dirty = true;
                    }
                },
                .relocated => |context_start| {
                    item.context.original_start = context_start;
                    item.source_offset = item.context.targetOffset(context_start) + item.line_offset;
                    item.line = 1 + std.mem.count(u8, source[0..item.source_offset], "\n");
                    item.status = .current;
                    self.dirty = true;
                },
                .outdated => if (item.status != .outdated) {
                    item.status = .outdated;
                    self.dirty = true;
                },
            }
        }
    }

    pub fn markPathOutdated(self: *Bookmarks, path: []const u8) void {
        for (self.items.items) |*item| {
            if (!std.mem.eql(u8, item.path, path) or item.status == .outdated) continue;
            item.status = .outdated;
            self.dirty = true;
        }
    }

    pub fn reanchorRenamedPath(self: *Bookmarks, old_path: []const u8, new_path: []const u8, source: []const u8) !void {
        for (self.items.items) |*item| {
            if (!std.mem.eql(u8, item.path, old_path)) continue;
            switch (anchor.match(item.context, source)) {
                .retained, .relocated => |context_start| {
                    const replacement = try self.allocator.dupe(u8, new_path);
                    self.allocator.free(item.path);
                    item.path = replacement;
                    item.context.original_start = context_start;
                    item.source_offset = item.context.targetOffset(context_start) + item.line_offset;
                    item.line = 1 + std.mem.count(u8, source[0..item.source_offset], "\n");
                    item.status = .current;
                    self.dirty = true;
                },
                .outdated => if (item.status != .outdated) {
                    item.status = .outdated;
                    self.dirty = true;
                },
            }
        }
    }

    pub fn markClean(self: *Bookmarks) void {
        self.dirty = false;
    }

    fn ensureVisible(self: *Bookmarks, viewport_rows: usize) void {
        if (viewport_rows == 0) return;
        if (self.selected < self.scroll) self.scroll = self.selected;
        if (self.selected >= self.scroll + viewport_rows)
            self.scroll = self.selected - viewport_rows + 1;
    }
};

const testing = std.testing;

test "loaded bookmark state is cloned for its repository" {
    const items = [_]bookmark.Bookmark{.{ .id = 1, .path = "a.zig", .line = 2, .column = 3, .source_offset = 4, .line_offset = 4, .context = .{ .bytes = "line\n", .original_start = 0, .target_start = 0, .target_end = 4 }, .label = "A" }};
    const stored: bookmark.Stored = .{ .next_id = 2, .bookmarks = &items };
    var loaded = try Bookmarks.fromStored(testing.allocator, "/repo", stored);
    defer loaded.deinit();
    try testing.expectEqualStrings("/repo", loaded.repository_path);
    try testing.expectEqualStrings("a.zig", loaded.items.items[0].path);
    var moved = try Bookmarks.fromStored(testing.allocator, "/moved/repo", stored);
    defer moved.deinit();
    try testing.expectEqualStrings("/moved/repo", moved.repository_path);
    try testing.expectEqualStrings("a.zig", moved.items.items[0].path);
    try testing.expect(!moved.dirty);
}

test "bookmark retains original then uniquely relocates or becomes Outdated" {
    var state = try Bookmarks.init(testing.allocator, "/repo");
    defer state.deinit();
    try state.add("a.zig", 2, 1, 3, .{ .bytes = "a\ntarget\nb\n", .original_start = 0, .target_start = 2, .target_end = 8 }, "");
    state.markClean();
    state.reanchorPath("a.zig", "a\ntarget\nb\na\ntarget\nb\n");
    try testing.expectEqual(bookmark.Status.current, state.selectedBookmark().?.status);
    try testing.expect(!state.dirty);
    state.reanchorPath("a.zig", "x\na\ntarget\nb\ny\n");
    try testing.expectEqual(@as(usize, 5), state.selectedBookmark().?.source_offset);
    try testing.expect(state.dirty);
    state.markClean();
    state.reanchorPath("a.zig", "a\ntarget\nb\na\ntarget\nb\n");
    try testing.expectEqual(bookmark.Status.outdated, state.selectedBookmark().?.status);
}

test "bookmark follows only an explicit rename with exact context" {
    var state = try Bookmarks.init(testing.allocator, "/repo");
    defer state.deinit();
    try state.add("old.zig", 1, 0, 0, .{ .bytes = "target\n", .original_start = 0, .target_start = 0, .target_end = 7 }, "");
    state.markClean();
    try state.reanchorRenamedPath("old.zig", "new.zig", "changed\n");
    try testing.expectEqualStrings("old.zig", state.selectedBookmark().?.path);
    try testing.expectEqual(bookmark.Status.outdated, state.selectedBookmark().?.status);
    try state.reanchorRenamedPath("old.zig", "new.zig", "target\n");
    try testing.expectEqualStrings("new.zig", state.selectedBookmark().?.path);
    try testing.expectEqual(bookmark.Status.current, state.selectedBookmark().?.status);
}

test "create delete and status transitions retain private location state" {
    var state = try Bookmarks.init(testing.allocator, "/repo");
    defer state.deinit();
    try state.add("a.zig", 3, 4, 20, .{ .bytes = "a\n", .original_start = 20, .target_start = 0, .target_end = 1 }, "");
    try state.add("b.zig", 5, 0, 40, .{ .bytes = "b\n", .original_start = 40, .target_start = 0, .target_end = 1 }, "label");
    try testing.expectEqual(@as(usize, 2), state.items.items.len);
    try testing.expectEqualStrings("label", state.selectedBookmark().?.label);
    state.markSelectedOutdated();
    try testing.expectEqual(bookmark.Status.outdated, state.selectedBookmark().?.status);
    state.deleteSelected();
    try testing.expectEqual(@as(usize, 1), state.items.items.len);
    try testing.expect(state.dirty);
}
