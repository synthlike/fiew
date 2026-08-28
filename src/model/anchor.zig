const std = @import("std");

pub const surrounding_lines: usize = 3;

/// Exact raw-byte evidence for one line/selection. `original_start` is the
/// context start in the candidate byte stream; target offsets are relative.
pub const Context = struct {
    bytes: []const u8,
    original_start: usize,
    target_start: usize,
    target_end: usize,

    pub fn targetOffset(self: Context, context_start: usize) usize {
        return context_start + self.target_start;
    }
};

pub const Match = union(enum) {
    retained: usize,
    relocated: usize,
    outdated,
};

pub fn match(context: Context, candidate: []const u8) Match {
    if (context.bytes.len == 0 or context.target_start > context.target_end or context.target_end > context.bytes.len)
        return .outdated;
    if (fitsAt(candidate, context.original_start, context.bytes)) return .{ .retained = context.original_start };
    var found: ?usize = null;
    var cursor: usize = 0;
    while (cursor <= candidate.len) {
        const index = std.mem.indexOfPos(u8, candidate, cursor, context.bytes) orelse break;
        if (lineBoundary(candidate, index) and endBoundary(candidate, index + context.bytes.len)) {
            if (found != null) return .outdated;
            found = index;
        }
        cursor = index + 1;
    }
    return if (found) |index| .{ .relocated = index } else .outdated;
}

fn fitsAt(candidate: []const u8, start: usize, expected: []const u8) bool {
    return start <= candidate.len and expected.len <= candidate.len - start and
        std.mem.eql(u8, candidate[start .. start + expected.len], expected) and lineBoundary(candidate, start) and
        endBoundary(candidate, start + expected.len);
}

fn lineBoundary(candidate: []const u8, start: usize) bool {
    return start == 0 or candidate[start - 1] == '\n';
}

fn endBoundary(candidate: []const u8, end: usize) bool {
    return end == candidate.len or (end > 0 and candidate[end - 1] == '\n') or candidate[end] == '\n';
}

/// Capture complete lines around a target byte range. The resulting bytes are
/// owned by the caller and retain original line endings exactly.
pub fn capture(
    allocator: std.mem.Allocator,
    source: []const u8,
    target_start: usize,
    target_end: usize,
) !Context {
    const bounded_start = @min(target_start, source.len);
    const bounded_end = @min(@max(target_end, bounded_start), source.len);
    var context_start = lineStart(source, bounded_start);
    for (0..surrounding_lines) |_| {
        if (context_start == 0) break;
        context_start = lineStart(source, context_start - 1);
    }
    var context_end = lineEnd(source, bounded_end);
    for (0..surrounding_lines) |_| {
        if (context_end >= source.len) break;
        context_end = lineEnd(source, context_end);
    }
    return .{
        .bytes = try allocator.dupe(u8, source[context_start..context_end]),
        .original_start = context_start,
        .target_start = bounded_start - context_start,
        .target_end = bounded_end - context_start,
    };
}

pub fn lineStart(source: []const u8, offset: usize) usize {
    var index = @min(offset, source.len);
    while (index > 0 and source[index - 1] != '\n') index -= 1;
    return index;
}

pub fn lineEnd(source: []const u8, offset: usize) usize {
    var index = @min(offset, source.len);
    while (index < source.len and source[index] != '\n') index += 1;
    if (index < source.len) index += 1;
    return index;
}

const testing = std.testing;

test "stored location wins before duplicate relocation search" {
    const context: Context = .{ .bytes = "same\n", .original_start = 5, .target_start = 0, .target_end = 4 };
    try testing.expectEqual(@as(usize, 5), match(context, "xxxx\nsame\nsame\n").retained);
}

test "relocation requires exactly one raw-byte context" {
    const context: Context = .{ .bytes = "before\ntarget\nafter\n", .original_start = 99, .target_start = 7, .target_end = 13 };
    try testing.expectEqual(@as(usize, 2), match(context, "x\nbefore\ntarget\nafter\ny\n").relocated);
    try testing.expectEqual(std.meta.Tag(Match).outdated, std.meta.activeTag(match(context, "before\ntarget\nafter\nbefore\ntarget\nafter\n")));
    try testing.expectEqual(std.meta.Tag(Match).outdated, std.meta.activeTag(match(context, "before\n target\nafter\n")));
}

test "capture keeps three surrounding complete lines and raw endings" {
    const source = "0\r\n1\r\n2\r\n3\r\nTARGET\r\n5\r\n6\r\n7\r\n8\r\n";
    const start = std.mem.indexOf(u8, source, "TARGET").?;
    const value = try capture(testing.allocator, source, start, start + 6);
    defer testing.allocator.free(value.bytes);
    try testing.expectEqualStrings("1\r\n2\r\n3\r\nTARGET\r\n5\r\n6\r\n7\r\n", value.bytes);
}
