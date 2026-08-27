const std = @import("std");
const project = @import("../model/project.zig");

pub const Browser = struct {
    allocator: std.mem.Allocator,
    tree: *const project.Tree,
    expanded: []bool,
    visible: std.ArrayListUnmanaged(usize) = .empty,
    selected: usize = 0,
    scroll: usize = 0,

    pub fn init(allocator: std.mem.Allocator, tree: *const project.Tree) !Browser {
        const expanded = try allocator.alloc(bool, tree.nodes.len);
        // Directories start collapsed, so only top-level entries show initially.
        @memset(expanded, false);
        var self: Browser = .{
            .allocator = allocator,
            .tree = tree,
            .expanded = expanded,
        };
        errdefer self.deinit();
        try self.rebuildVisible(null);
        return self;
    }

    pub fn deinit(self: *Browser) void {
        self.visible.deinit(self.allocator);
        self.allocator.free(self.expanded);
        self.* = undefined;
    }

    pub fn selectedNode(self: Browser) ?*const project.Node {
        if (self.visible.items.len == 0) return null;
        return &self.tree.nodes[self.visible.items[self.selected]];
    }

    pub fn selectedNodeIndex(self: Browser) ?usize {
        if (self.visible.items.len == 0) return null;
        return self.visible.items[self.selected];
    }

    pub fn move(self: *Browser, delta: isize, viewport_height: usize) void {
        if (self.visible.items.len == 0) return;
        const current: isize = @intCast(self.selected);
        const last: isize = @intCast(self.visible.items.len - 1);
        self.selected = @intCast(std.math.clamp(current + delta, 0, last));
        self.ensureVisible(viewport_height);
    }

    pub fn selectVisible(self: *Browser, visible_index: usize, viewport_height: usize) void {
        if (visible_index >= self.visible.items.len) return;
        self.selected = visible_index;
        self.ensureVisible(viewport_height);
    }

    pub fn collapseOrParent(self: *Browser, viewport_height: usize) !void {
        const node_index = self.selectedNodeIndex() orelse return;
        const node = self.tree.nodes[node_index];
        if (node.kind == .directory and self.expanded[node_index]) {
            self.expanded[node_index] = false;
            try self.rebuildVisible(node_index);
            self.ensureVisible(viewport_height);
            return;
        }
        if (node.depth <= 1) return;

        var index = node_index;
        while (index > 0) {
            index -= 1;
            const candidate = self.tree.nodes[index];
            if (candidate.kind == .directory and candidate.depth + 1 == node.depth and
                isDescendant(candidate.path, node.path))
            {
                self.selectNode(index);
                self.ensureVisible(viewport_height);
                return;
            }
        }
    }

    pub fn expandOrChild(self: *Browser, viewport_height: usize) !void {
        const node_index = self.selectedNodeIndex() orelse return;
        const node = self.tree.nodes[node_index];
        if (node.kind != .directory) return;
        if (!self.expanded[node_index]) {
            self.expanded[node_index] = true;
            try self.rebuildVisible(node_index);
        } else if (node_index + 1 < self.tree.nodes.len) {
            const child = self.tree.nodes[node_index + 1];
            if (child.depth == node.depth + 1 and isDescendant(node.path, child.path)) {
                self.selectNode(node_index + 1);
            }
        }
        self.ensureVisible(viewport_height);
    }

    pub fn toggleSelected(self: *Browser, viewport_height: usize) !bool {
        const node_index = self.selectedNodeIndex() orelse return false;
        if (self.tree.nodes[node_index].kind != .directory) return false;
        self.expanded[node_index] = !self.expanded[node_index];
        try self.rebuildVisible(node_index);
        self.ensureVisible(viewport_height);
        return true;
    }

    pub fn ensureVisible(self: *Browser, viewport_height: usize) void {
        if (viewport_height == 0) return;
        if (self.selected < self.scroll) self.scroll = self.selected;
        if (self.selected >= self.scroll + viewport_height) {
            self.scroll = self.selected - viewport_height + 1;
        }
    }

    fn rebuildVisible(self: *Browser, preserve_node: ?usize) !void {
        self.visible.clearRetainingCapacity();
        var collapsed_depth: ?usize = null;
        for (self.tree.nodes, 0..) |node, index| {
            if (collapsed_depth) |depth| {
                if (node.depth > depth) continue;
                collapsed_depth = null;
            }
            try self.visible.append(self.allocator, index);
            if (node.kind == .directory and !self.expanded[index]) collapsed_depth = node.depth;
        }
        if (preserve_node) |node| self.selectNode(node) else self.selected = 0;
    }

    fn selectNode(self: *Browser, node_index: usize) void {
        for (self.visible.items, 0..) |visible_node, visible_index| {
            if (visible_node == node_index) {
                self.selected = visible_index;
                return;
            }
        }
        self.selected = @min(self.selected, self.visible.items.len -| 1);
    }

    fn isDescendant(parent: []const u8, child: []const u8) bool {
        return child.len > parent.len and std.mem.startsWith(u8, child, parent) and
            child[parent.len] == std.fs.path.sep;
    }
};

test "collapse preserves selection and hides descendants" {
    const nodes = [_]project.Node{
        .{ .path = "README.md", .depth = 1, .kind = .file },
        .{ .path = "src", .depth = 1, .kind = .directory },
        .{ .path = "src/app", .depth = 2, .kind = .directory },
        .{ .path = "src/app/main.zig", .depth = 3, .kind = .file },
        .{ .path = "src/root.zig", .depth = 2, .kind = .file },
    };
    const tree: project.Tree = .{
        .allocator = std.testing.allocator,
        .nodes = @constCast(&nodes),
        .file_count = 3,
    };
    var browser = try Browser.init(std.testing.allocator, &tree);
    defer browser.deinit();

    // Folded by default: only the two top-level entries are visible.
    try std.testing.expectEqual(@as(usize, 2), browser.visible.items.len);
    browser.move(1, 20);
    try std.testing.expectEqualStrings("src", browser.selectedNode().?.path);

    // Expanding `src` reveals its immediate children (src/app stays collapsed).
    try browser.expandOrChild(20);
    try std.testing.expectEqual(@as(usize, 4), browser.visible.items.len);

    // Collapsing `src` hides them again and keeps the selection on `src`.
    try std.testing.expect(try browser.toggleSelected(20));
    try std.testing.expectEqual(@as(usize, 2), browser.visible.items.len);
    try std.testing.expectEqualStrings("src", browser.selectedNode().?.path);
}

test "selection remains bounded with ten thousand files" {
    const allocator = std.testing.allocator;
    const nodes = try allocator.alloc(project.Node, 10_000);
    defer allocator.free(nodes);
    var paths: std.ArrayList([]u8) = .empty;
    defer {
        for (paths.items) |path| allocator.free(path);
        paths.deinit(allocator);
    }
    for (nodes, 0..) |*node, index| {
        const path = try std.fmt.allocPrint(allocator, "file-{d:0>5}.zig", .{index});
        try paths.append(allocator, path);
        node.* = .{ .path = path, .depth = 1, .kind = .file };
    }
    const tree: project.Tree = .{ .allocator = allocator, .nodes = nodes, .file_count = nodes.len };
    var browser = try Browser.init(allocator, &tree);
    defer browser.deinit();

    browser.move(20_000, 30);
    try std.testing.expectEqual(@as(usize, 9_999), browser.selected);
    try std.testing.expectEqual(@as(usize, 9_970), browser.scroll);
}
