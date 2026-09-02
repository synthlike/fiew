//! Skaut-owned Language Server Protocol values.
//!
//! Wire JSON and process handles stay in adapters. These values bind semantic
//! work to immutable repository and document identities.

const std = @import("std");
const document = @import("document.zig");

pub const PositionEncoding = enum { utf8, utf16 };

pub const Position = struct {
    line: u32,
    character: u32,
};

pub const Status = enum(u8) {
    unavailable,
    untrusted,
    not_installed,
    incompatible,
    stopped,
    starting,
    ready,
    crashed,
};

pub fn statusText(value: Status) []const u8 {
    return switch (value) {
        .unavailable => "ZLS unavailable",
        .untrusted => "ZLS untrusted",
        .not_installed => "ZLS not installed",
        .incompatible => "ZLS incompatible",
        .stopped => "ZLS stopped",
        .starting => "ZLS starting",
        .ready => "ZLS ready",
        .crashed => "ZLS crashed",
    };
}

pub const RequestIdentity = struct {
    repository_slug: [32]u8,
    document_generation: u64,
    selection: document.ByteRange,
    operation: Operation,
    request_generation: u64,
};

pub const Operation = enum { definition, references, hover };

pub const PositionError = error{ InvalidEncoding, InvalidLine, InvalidBoundary, OutOfRange };

/// Convert a source byte boundary to an LSP position against one immutable
/// UTF-8 snapshot. UTF-16 columns count code units, including surrogate pairs.
pub fn positionAt(snapshot: document.Snapshot, byte_offset: usize, encoding: PositionEncoding) PositionError!Position {
    if (snapshot.encoding != .utf8) return error.InvalidEncoding;
    if (byte_offset > snapshot.bytes.len) return error.OutOfRange;
    if (byte_offset < snapshot.bytes.len and (snapshot.bytes[byte_offset] & 0xc0) == 0x80)
        return error.InvalidBoundary;

    var low: usize = 0;
    var high = snapshot.line_starts.len;
    while (low + 1 < high) {
        const middle = low + (high - low) / 2;
        if (snapshot.line_starts[middle] <= byte_offset) low = middle else high = middle;
    }
    const start = snapshot.line_starts[low];
    const line_bytes = snapshot.bytes[start..byte_offset];
    const character: usize = switch (encoding) {
        .utf8 => line_bytes.len,
        .utf16 => utf16Units(line_bytes),
    };
    return .{ .line = @intCast(low), .character = @intCast(character) };
}

/// Convert an LSP position to a source byte boundary against one immutable
/// snapshot. Positions inside a UTF-8 sequence or UTF-16 surrogate pair fail.
pub fn byteOffsetAt(snapshot: document.Snapshot, position: Position, encoding: PositionEncoding) PositionError!usize {
    if (snapshot.encoding != .utf8) return error.InvalidEncoding;
    if (position.line >= snapshot.line_starts.len) return error.InvalidLine;
    const line: usize = @intCast(position.line);
    const start = snapshot.line_starts[line];
    var end = if (line + 1 < snapshot.line_starts.len) snapshot.line_starts[line + 1] else snapshot.bytes.len;
    if (end > start and snapshot.bytes[end - 1] == '\n') end -= 1;
    if (end > start and snapshot.bytes[end - 1] == '\r') end -= 1;
    const wanted: usize = @intCast(position.character);

    if (encoding == .utf8) {
        const offset = start + wanted;
        if (offset > end) return error.OutOfRange;
        if (offset < end and (snapshot.bytes[offset] & 0xc0) == 0x80) return error.InvalidBoundary;
        return offset;
    }

    var offset = start;
    var units: usize = 0;
    while (offset < end) {
        if (units == wanted) return offset;
        const sequence_len = std.unicode.utf8ByteSequenceLength(snapshot.bytes[offset]) catch return error.InvalidEncoding;
        if (offset + sequence_len > end) return error.InvalidEncoding;
        const codepoint = std.unicode.utf8Decode(snapshot.bytes[offset .. offset + sequence_len]) catch return error.InvalidEncoding;
        const next_units: usize = if (codepoint > 0xffff) 2 else 1;
        if (units + next_units > wanted) return error.InvalidBoundary;
        units += next_units;
        offset += sequence_len;
    }
    if (units == wanted) return offset;
    return error.OutOfRange;
}

fn utf16Units(bytes: []const u8) usize {
    var units: usize = 0;
    var view = std.unicode.Utf8View.initUnchecked(bytes);
    var iterator = view.iterator();
    while (iterator.nextCodepoint()) |codepoint| units += if (codepoint > 0xffff) 2 else 1;
    return units;
}

const scalar_segmenter: @import("../ports/text_segmentation.zig").Segmenter = .{
    .next_fn = struct {
        fn next(_: ?*const anyopaque, text: []const u8, start: usize) usize {
            return start + (std.unicode.utf8ByteSequenceLength(text[start]) catch 1);
        }
    }.next,
    .width_fn = struct {
        fn width(_: ?*const anyopaque, _: []const u8) u16 {
            return 1;
        }
    }.width,
};

fn testSnapshot(bytes: []const u8) !document.Snapshot {
    return document.Snapshot.init(std.testing.allocator, "sample.zig", bytes, 9, .{ .size = bytes.len }, scalar_segmenter);
}

test "UTF-8 and UTF-16 positions map only at valid immutable snapshot boundaries" {
    var value = try testSnapshot("a😀b\nβ");
    defer value.deinit();

    try std.testing.expectEqual(Position{ .line = 0, .character = 5 }, try positionAt(value, 5, .utf8));
    try std.testing.expectEqual(Position{ .line = 0, .character = 3 }, try positionAt(value, 5, .utf16));
    try std.testing.expectEqual(@as(usize, 5), try byteOffsetAt(value, .{ .line = 0, .character = 3 }, .utf16));
    try std.testing.expectError(error.InvalidBoundary, byteOffsetAt(value, .{ .line = 0, .character = 2 }, .utf16));
    try std.testing.expectError(error.InvalidBoundary, positionAt(value, 2, .utf8));
    try std.testing.expectEqual(@as(usize, 9), try byteOffsetAt(value, .{ .line = 1, .character = 1 }, .utf16));
}

test "invalid and binary snapshots refuse LSP mapping" {
    const source = [_]u8{ 0xff, 'x' };
    var value = try testSnapshot(&source);
    defer value.deinit();
    try std.testing.expectError(error.InvalidEncoding, positionAt(value, 0, .utf16));
}
