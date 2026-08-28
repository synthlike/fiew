const std = @import("std");
const project = @import("../model/project.zig");

pub const max_query_bytes: usize = 256;
pub const max_candidates: usize = 10_000;
pub const max_results: usize = 100;

pub const Match = struct {
    node_index: usize,
    score: usize,
};

pub const Scope = enum { all, git_visible };

/// Transient, bounded repository-path matching state. The project tree owns all
/// paths; the finder stores only node indexes.
pub const Finder = struct {
    allocator: std.mem.Allocator,
    query: std.ArrayListUnmanaged(u8) = .empty,
    matches: std.ArrayListUnmanaged(Match) = .empty,
    selected: usize = 0,
    scroll: usize = 0,
    truncated: bool = false,
    scope: Scope = .all,
    allowed: ?[]bool = null,

    pub fn init(allocator: std.mem.Allocator) Finder {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Finder) void {
        self.query.deinit(self.allocator);
        self.matches.deinit(self.allocator);
        if (self.allowed) |allowed| self.allocator.free(allowed);
        self.* = undefined;
    }

    pub fn reset(self: *Finder, tree: *const project.Tree) !void {
        if (self.allowed) |allowed| self.allocator.free(allowed);
        self.allowed = null;
        self.scope = .all;
        self.query.clearRetainingCapacity();
        try self.rebuild(tree);
    }

    pub fn resetGitVisible(self: *Finder, tree: *const project.Tree, paths: []const []const u8) !void {
        var indexes: std.StringHashMapUnmanaged(usize) = .empty;
        defer indexes.deinit(self.allocator);
        for (tree.nodes, 0..) |node, index| {
            if (node.kind == .file) try indexes.put(self.allocator, node.path, index);
        }

        const allowed = try self.allocator.alloc(bool, tree.nodes.len);
        errdefer self.allocator.free(allowed);
        @memset(allowed, false);
        for (paths) |path| if (indexes.get(path)) |index| {
            allowed[index] = true;
        };

        if (self.allowed) |previous| self.allocator.free(previous);
        self.allowed = allowed;
        self.scope = .git_visible;
        self.query.clearRetainingCapacity();
        try self.rebuild(tree);
    }

    pub fn appendCodepoint(self: *Finder, tree: *const project.Tree, codepoint: u21) !void {
        var buffer: [4]u8 = undefined;
        const length = std.unicode.utf8Encode(codepoint, &buffer) catch return;
        if (self.query.items.len + length > max_query_bytes) return;
        try self.query.appendSlice(self.allocator, buffer[0..length]);
        try self.rebuild(tree);
    }

    pub fn backspace(self: *Finder, tree: *const project.Tree) !void {
        if (self.query.items.len == 0) return;
        var start = self.query.items.len - 1;
        while (start > 0 and (self.query.items[start] & 0xc0) == 0x80) start -= 1;
        self.query.shrinkRetainingCapacity(start);
        try self.rebuild(tree);
    }

    pub fn move(self: *Finder, delta: isize, viewport_height: usize) void {
        if (self.matches.items.len == 0) return;
        const current: isize = @intCast(self.selected);
        const last: isize = @intCast(self.matches.items.len - 1);
        self.selected = @intCast(std.math.clamp(current + delta, 0, last));
        self.ensureVisible(viewport_height);
    }

    pub fn selectedNode(self: *const Finder, tree: *const project.Tree) ?*const project.Node {
        if (self.matches.items.len == 0) return null;
        return &tree.nodes[self.matches.items[self.selected].node_index];
    }

    pub fn ensureVisible(self: *Finder, viewport_height: usize) void {
        if (viewport_height == 0) return;
        if (self.selected < self.scroll) self.scroll = self.selected;
        if (self.selected >= self.scroll + viewport_height)
            self.scroll = self.selected - viewport_height + 1;
    }

    pub fn rebuild(self: *Finder, tree: *const project.Tree) !void {
        self.matches.clearRetainingCapacity();
        self.selected = 0;
        self.scroll = 0;
        self.truncated = false;

        var candidates: usize = 0;
        for (tree.nodes, 0..) |node, node_index| {
            if (node.kind != .file) continue;
            if (self.allowed) |allowed| if (!allowed[node_index]) continue;
            if (candidates == max_candidates) {
                self.truncated = true;
                break;
            }
            candidates += 1;
            const score = scorePath(node.path, self.query.items) orelse continue;
            try self.insertBounded(.{ .node_index = node_index, .score = score }, tree);
        }
    }

    fn insertBounded(self: *Finder, candidate: Match, tree: *const project.Tree) !void {
        var at: usize = 0;
        while (at < self.matches.items.len and !lessThan(tree, candidate, self.matches.items[at])) : (at += 1) {}
        if (at >= max_results) {
            self.truncated = true;
            return;
        }
        try self.matches.insert(self.allocator, at, candidate);
        if (self.matches.items.len > max_results) {
            _ = self.matches.pop();
            self.truncated = true;
        }
    }
};

/// Higher scores rank first. Matching is ASCII-case-insensitive by byte while
/// non-ASCII bytes remain exact, so every accepted match still identifies byte
/// positions in the original path without normalization or allocation.
pub fn scorePath(path: []const u8, query: []const u8) ?usize {
    if (query.len == 0) return 0;
    var path_index: usize = 0;
    var previous_match: ?usize = null;
    var run: usize = 0;
    var score: usize = 0;

    for (query) |needle| {
        var found: ?usize = null;
        while (path_index < path.len) : (path_index += 1) {
            if (fold(path[path_index]) == fold(needle)) {
                found = path_index;
                break;
            }
        }
        const index = found orelse return null;
        score += 10;
        if (index == 0 or isSeparator(path[index - 1])) score += 80;
        if (previous_match != null and previous_match.? + 1 == index) {
            run += 1;
            score += 30 + run * 5;
        } else {
            run = 0;
        }
        previous_match = index;
        path_index = index + 1;
    }
    return score;
}

fn lessThan(tree: *const project.Tree, lhs: Match, rhs: Match) bool {
    if (lhs.score != rhs.score) return lhs.score > rhs.score;
    const left_path = tree.nodes[lhs.node_index].path;
    const right_path = tree.nodes[rhs.node_index].path;
    const order = std.mem.order(u8, left_path, right_path);
    if (order != .eq) return order == .lt;
    return lhs.node_index < rhs.node_index;
}

fn fold(byte: u8) u8 {
    return std.ascii.toLower(byte);
}

fn isSeparator(byte: u8) bool {
    return byte == '/' or byte == '\\';
}

test "subsequence ranking favors boundaries and contiguous runs with deterministic ties" {
    try std.testing.expect(scorePath("src/foo/bar.zig", "fb").? > scorePath("src/fbar.zig", "fb").?);
    try std.testing.expect(scorePath("src/ffuzzy.zig", "ff").? > scorePath("src/far_fuzzy.zig", "ff").?);

    const nodes = [_]project.Node{
        .{ .path = "src/ffuzzy.zig", .depth = 2, .kind = .file },
        .{ .path = "src/app/file_finder.zig", .depth = 3, .kind = .file },
        .{ .path = "src/app/far_between.zig", .depth = 3, .kind = .file },
        .{ .path = "alpha/file.zig", .depth = 2, .kind = .file },
        .{ .path = "beta/file.zig", .depth = 2, .kind = .file },
    };
    const tree: project.Tree = .{ .allocator = std.testing.allocator, .nodes = @constCast(&nodes), .file_count = nodes.len };
    var finder = Finder.init(std.testing.allocator);
    defer finder.deinit();

    for ("ff") |character| try finder.appendCodepoint(&tree, character);
    try std.testing.expectEqualStrings("src/ffuzzy.zig", finder.selectedNode(&tree).?.path);

    try finder.reset(&tree);
    for ("file") |character| try finder.appendCodepoint(&tree, character);
    try std.testing.expectEqualStrings("alpha/file.zig", tree.nodes[finder.matches.items[0].node_index].path);
    try std.testing.expectEqualStrings("beta/file.zig", tree.nodes[finder.matches.items[1].node_index].path);
}

test "matcher has explicit empty and output bounds at ten thousand files" {
    const allocator = std.testing.allocator;
    const nodes = try allocator.alloc(project.Node, max_candidates);
    defer allocator.free(nodes);
    var paths: std.ArrayList([]u8) = .empty;
    defer {
        for (paths.items) |path| allocator.free(path);
        paths.deinit(allocator);
    }
    for (nodes, 0..) |*node, index| {
        const path = try std.fmt.allocPrint(allocator, "src/file-{d:0>5}.zig", .{index});
        try paths.append(allocator, path);
        node.* = .{ .path = path, .depth = 2, .kind = .file };
    }
    const tree: project.Tree = .{ .allocator = allocator, .nodes = nodes, .file_count = nodes.len };
    var finder = Finder.init(allocator);
    defer finder.deinit();

    try finder.reset(&tree);
    try std.testing.expectEqual(max_results, finder.matches.items.len);
    try std.testing.expect(finder.truncated);
    for ("not-present") |character| try finder.appendCodepoint(&tree, character);
    try std.testing.expectEqual(@as(usize, 0), finder.matches.items.len);
}

test "Git-visible candidates filter the finder without changing the project tree" {
    const nodes = [_]project.Node{
        .{ .path = ".ignored/cache.bin", .depth = 2, .kind = .file },
        .{ .path = "README.md", .depth = 1, .kind = .file },
        .{ .path = "src/main.zig", .depth = 2, .kind = .file },
    };
    const tree: project.Tree = .{ .allocator = std.testing.allocator, .nodes = @constCast(&nodes), .file_count = nodes.len };
    var finder = Finder.init(std.testing.allocator);
    defer finder.deinit();

    try finder.resetGitVisible(&tree, &.{ "README.md", "src/main.zig", "deleted.txt" });
    try std.testing.expectEqual(Scope.git_visible, finder.scope);
    try std.testing.expectEqual(@as(usize, 2), finder.matches.items.len);
    try std.testing.expectEqual(@as(usize, 3), tree.nodes.len);

    try finder.reset(&tree);
    try std.testing.expectEqual(Scope.all, finder.scope);
    try std.testing.expectEqual(@as(usize, 3), finder.matches.items.len);
}
