//! Pure transient definition-result state.

const std = @import("std");

pub const Target = struct {
    path: []u8,
    line: usize,
    column: usize,
    source_start: usize,
    preview: []u8,
    external: bool,
    /// True for the first ordered result in a file. Renderers use this to
    /// make reference groups visible without adding non-selectable rows.
    group_start: bool = true,

    pub fn deinit(self: *Target, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        allocator.free(self.preview);
        self.* = undefined;
    }
};

pub const Results = struct {
    allocator: std.mem.Allocator,
    items: []Target,
    selected: usize = 0,
    scroll: usize = 0,
    truncated: bool = false,

    pub fn init(allocator: std.mem.Allocator, items: []Target) Results {
        return .{ .allocator = allocator, .items = items };
    }

    pub fn initTruncated(allocator: std.mem.Allocator, items: []Target, truncated: bool) Results {
        return .{ .allocator = allocator, .items = items, .truncated = truncated };
    }

    pub fn deinit(self: *Results) void {
        for (self.items) |*item| item.deinit(self.allocator);
        self.allocator.free(self.items);
        self.* = undefined;
    }

    pub fn selectedTarget(self: *const Results) ?*const Target {
        if (self.items.len == 0) return null;
        return &self.items[@min(self.selected, self.items.len - 1)];
    }

    pub fn move(self: *Results, delta: isize, viewport_rows: usize) void {
        if (self.items.len == 0) return;
        const current: isize = @intCast(self.selected);
        self.selected = @intCast(std.math.clamp(current + delta, 0, @as(isize, @intCast(self.items.len - 1))));
        self.ensureVisible(viewport_rows);
    }

    pub fn ensureVisible(self: *Results, viewport_rows: usize) void {
        if (viewport_rows == 0) return;
        if (self.selected < self.scroll) self.scroll = self.selected;
        if (self.selected >= self.scroll + viewport_rows)
            self.scroll = self.selected - viewport_rows + 1;
    }
};

test "definition result movement remains bounded and visible" {
    const items = try std.testing.allocator.alloc(Target, 4);
    for (items, 0..) |*item, index| item.* = .{
        .path = try std.fmt.allocPrint(std.testing.allocator, "file-{d}.zig", .{index}),
        .line = index + 1,
        .column = 0,
        .source_start = 0,
        .preview = try std.testing.allocator.dupe(u8, "const value = 1;"),
        .external = false,
    };
    var results = Results.init(std.testing.allocator, items);
    defer results.deinit();
    results.move(3, 2);
    try std.testing.expectEqual(@as(usize, 3), results.selected);
    try std.testing.expectEqual(@as(usize, 2), results.scroll);
    results.move(-20, 2);
    try std.testing.expectEqual(@as(usize, 0), results.selected);
    try std.testing.expectEqual(@as(usize, 0), results.scroll);
}
