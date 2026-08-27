//! fiew-owned syntax types. These are the only shapes the application and view
//! layers see; no Tree-sitter C types cross this boundary.

const std = @import("std");
const document = @import("document.zig");

/// Presentation category for a highlighted source span. Kept small and
/// style-oriented rather than mirroring the grammar's full capture vocabulary,
/// since Zig highlighting is presentation assistance, not semantic truth.
pub const HighlightKind = enum {
    keyword,
    type,
    function,
    string,
    number,
    constant,
    comment,
    operator,
    punctuation,
    label,
    variable,

    /// Map a query capture name (the leading dotted segment) to a kind.
    pub fn fromCapture(name: []const u8) ?HighlightKind {
        const end = std.mem.indexOfScalar(u8, name, '.') orelse name.len;
        return std.meta.stringToEnum(HighlightKind, name[0..end]);
    }
};

/// A highlighted range over original source bytes.
pub const HighlightSpan = struct {
    source: document.ByteRange,
    kind: HighlightKind,
};

/// A foldable region expressed in zero-based source line numbers. `start_line`
/// is the line kept visible when folded; `end_line` is the last hidden line.
pub const FoldRange = struct {
    start_line: usize,
    end_line: usize,

    pub fn isFoldable(self: FoldRange) bool {
        return self.end_line > self.start_line;
    }

    pub fn contains(self: FoldRange, line: usize) bool {
        return line >= self.start_line and line <= self.end_line;
    }
};

/// Order spans so that, when painted in sequence, smaller (more specific) spans
/// land last and win over any enclosing span.
pub fn lessSpecificFirst(_: void, a: HighlightSpan, b: HighlightSpan) bool {
    if (a.source.start != b.source.start) return a.source.start < b.source.start;
    const a_len = a.source.end - a.source.start;
    const b_len = b.source.end - b.source.start;
    return a_len > b_len;
}

/// One named node in the structural outline, recorded in pre-order with the
/// index of its enclosing named node.
pub const OutlineNode = struct {
    source: document.ByteRange,
    start_line: usize,
    end_line: usize,
    parent: ?usize,
};

/// A flat, pre-order list of named nodes. Structural navigation is pure over
/// this fiew-owned projection so no Tree-sitter type reaches the reducer.
pub const Outline = struct {
    allocator: std.mem.Allocator,
    nodes: []const OutlineNode,

    pub fn deinit(self: *Outline) void {
        self.allocator.free(self.nodes);
        self.* = undefined;
    }

    /// Index of the deepest (smallest) named node whose bytes cover `selection`.
    pub fn enclosing(self: Outline, selection: document.ByteRange) ?usize {
        var best: ?usize = null;
        var best_span: usize = std.math.maxInt(usize);
        for (self.nodes, 0..) |node, index| {
            if (node.source.start <= selection.start and node.source.end >= selection.end) {
                const span = node.source.end - node.source.start;
                if (span < best_span) {
                    best_span = span;
                    best = index;
                }
            }
        }
        return best;
    }

    pub fn parent(self: Outline, index: usize) ?usize {
        return self.nodes[index].parent;
    }

    pub fn firstChild(self: Outline, index: usize) ?usize {
        for (self.nodes[index + 1 ..], index + 1..) |node, candidate| {
            if (node.parent == index) return candidate;
        }
        return null;
    }

    pub fn nextSibling(self: Outline, index: usize) ?usize {
        const owner = self.nodes[index].parent;
        for (self.nodes[index + 1 ..], index + 1..) |node, candidate| {
            if (node.parent == owner) return candidate;
        }
        return null;
    }

    pub fn prevSibling(self: Outline, index: usize) ?usize {
        const owner = self.nodes[index].parent;
        var candidate = index;
        while (candidate > 0) {
            candidate -= 1;
            if (self.nodes[candidate].parent == owner) return candidate;
        }
        return null;
    }
};

/// Immutable, fiew-owned analysis of one document snapshot. Produced entirely by
/// a parse job and read (never recomputed) during rendering.
pub const ParseData = struct {
    allocator: std.mem.Allocator,
    highlights: []const HighlightSpan,
    folds: []const FoldRange,
    outline: Outline,

    pub fn deinit(self: *ParseData) void {
        self.allocator.free(self.highlights);
        self.allocator.free(self.folds);
        self.outline.deinit();
        self.* = undefined;
    }

    /// The fold whose region contains `line`, preferring the innermost.
    pub fn foldContaining(self: ParseData, line: usize) ?usize {
        var best: ?usize = null;
        var best_span: usize = std.math.maxInt(usize);
        for (self.folds, 0..) |fold, index| {
            if (fold.contains(line)) {
                const span = fold.end_line - fold.start_line;
                if (span < best_span) {
                    best_span = span;
                    best = index;
                }
            }
        }
        return best;
    }
};

test "capture names map to presentation kinds" {
    try std.testing.expectEqual(HighlightKind.string, HighlightKind.fromCapture("string").?);
    try std.testing.expectEqual(HighlightKind.string, HighlightKind.fromCapture("string.escape").?);
    try std.testing.expectEqual(HighlightKind.function, HighlightKind.fromCapture("function.call").?);
    try std.testing.expect(HighlightKind.fromCapture("nonexistent") == null);
}

test "fold ranges report foldability and containment" {
    const fold: FoldRange = .{ .start_line = 3, .end_line = 7 };
    try std.testing.expect(fold.isFoldable());
    try std.testing.expect(fold.contains(3));
    try std.testing.expect(fold.contains(7));
    try std.testing.expect(!fold.contains(8));
    const single: FoldRange = .{ .start_line = 5, .end_line = 5 };
    try std.testing.expect(!single.isFoldable());
}

test "outline navigation ascends, descends, and moves between siblings" {
    // Pre-order layout:
    //   0 root      [0,100)
    //   1  fn a     [10,40)   parent 0
    //   2   stmt a1 [20,30)   parent 1
    //   3  fn b     [50,90)   parent 0
    var nodes = [_]OutlineNode{
        .{ .source = .{ .start = 0, .end = 100 }, .start_line = 0, .end_line = 20, .parent = null },
        .{ .source = .{ .start = 10, .end = 40 }, .start_line = 1, .end_line = 6, .parent = 0 },
        .{ .source = .{ .start = 20, .end = 30 }, .start_line = 2, .end_line = 3, .parent = 1 },
        .{ .source = .{ .start = 50, .end = 90 }, .start_line = 8, .end_line = 15, .parent = 0 },
    };
    const outline: Outline = .{ .allocator = std.testing.allocator, .nodes = &nodes };

    const here = outline.enclosing(.{ .start = 24, .end = 25 }).?;
    try std.testing.expectEqual(@as(usize, 2), here);
    try std.testing.expectEqual(@as(usize, 1), outline.parent(here).?);
    try std.testing.expectEqual(@as(usize, 2), outline.firstChild(1).?);
    try std.testing.expectEqual(@as(usize, 3), outline.nextSibling(1).?);
    try std.testing.expectEqual(@as(usize, 1), outline.prevSibling(3).?);
    try std.testing.expect(outline.nextSibling(3) == null);
    try std.testing.expect(outline.parent(0) == null);
}

test "fold containment prefers the innermost region" {
    const folds = [_]FoldRange{
        .{ .start_line = 0, .end_line = 20 },
        .{ .start_line = 5, .end_line = 10 },
    };
    var data: ParseData = .{
        .allocator = std.testing.allocator,
        .highlights = &.{},
        .folds = &folds,
        .outline = .{ .allocator = std.testing.allocator, .nodes = &.{} },
    };
    try std.testing.expectEqual(@as(usize, 1), data.foldContaining(7).?);
    try std.testing.expectEqual(@as(usize, 0), data.foldContaining(2).?);
    try std.testing.expect(data.foldContaining(25) == null);
}
