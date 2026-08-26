const std = @import("std");

pub const NodeKind = enum {
    directory,
    file,
    symlink,
    other,
};

pub const Node = struct {
    path: []const u8,
    depth: usize,
    kind: NodeKind,
};

pub const Tree = struct {
    allocator: std.mem.Allocator,
    nodes: []Node,
    file_count: usize,

    pub fn deinit(self: *Tree) void {
        for (self.nodes) |node| self.allocator.free(node.path);
        self.allocator.free(self.nodes);
        self.* = undefined;
    }
};
