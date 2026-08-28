//! In-memory private bookmark state for one canonical repository identity.

const std = @import("std");
const bookmark = @import("../model/bookmark.zig");

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
            try self.items.append(allocator, .{
                .id = item.id,
                .path = owned_path,
                .line = item.line,
                .column = item.column,
                .source_offset = item.source_offset,
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
        label: []const u8,
    ) !void {
        if (!bookmark.validLabel(label)) return error.InvalidLabel;
        const owned_path = try self.allocator.dupe(u8, path);
        errdefer self.allocator.free(owned_path);
        const owned_label = try self.allocator.dupe(u8, label);
        errdefer self.allocator.free(owned_label);
        try self.items.append(self.allocator, .{
            .id = self.next_id,
            .path = owned_path,
            .line = @max(line, 1),
            .column = column,
            .source_offset = source_offset,
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
    const items = [_]bookmark.Bookmark{.{ .id = 1, .path = "a.zig", .line = 2, .column = 3, .source_offset = 4, .label = "A" }};
    var loaded = try Bookmarks.fromStored(testing.allocator, "/repo", .{ .next_id = 2, .bookmarks = &items });
    defer loaded.deinit();
    try testing.expectEqualStrings("/repo", loaded.repository_path);
    try testing.expectEqualStrings("a.zig", loaded.items.items[0].path);
}

test "create delete and status transitions retain private location state" {
    var state = try Bookmarks.init(testing.allocator, "/repo");
    defer state.deinit();
    try state.add("a.zig", 3, 4, 20, "");
    try state.add("b.zig", 5, 0, 40, "label");
    try testing.expectEqual(@as(usize, 2), state.items.items.len);
    try testing.expectEqualStrings("label", state.selectedBookmark().?.label);
    state.markSelectedOutdated();
    try testing.expectEqual(bookmark.Status.outdated, state.selectedBookmark().?.status);
    state.deleteSelected();
    try testing.expectEqual(@as(usize, 1), state.items.items.len);
    try testing.expect(state.dirty);
}
