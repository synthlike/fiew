const std = @import("std");
const text_segmentation = @import("../ports/text_segmentation.zig");

pub const Encoding = enum {
    utf8,
    invalid_utf8,
    binary,
};

pub const Metadata = struct {
    size: u64,
    modified_nanoseconds: i96 = 0,
};

pub const ByteRange = struct {
    start: usize,
    end: usize,
};

pub const IndexRange = struct {
    start: usize,
    end: usize,
};

pub const Grapheme = struct {
    source: ByteRange,
    display: ByteRange,
    line: usize,
    visual_column: u32,
    width: u16,
};

/// Immutable after initialization. All ranges refer to the original source bytes.
pub const Snapshot = struct {
    allocator: std.mem.Allocator,
    path: []const u8,
    bytes: []const u8,
    display_bytes: []const u8,
    display_to_source: []const usize,
    graphemes: []const Grapheme,
    line_starts: []const usize,
    display_line_starts: []const usize,
    generation: u64,
    encoding: Encoding,
    metadata: Metadata,

    pub fn init(
        allocator: std.mem.Allocator,
        path: []const u8,
        bytes: []const u8,
        generation: u64,
        metadata: Metadata,
        segmenter: text_segmentation.Segmenter,
    ) !Snapshot {
        const owned_path = try allocator.dupe(u8, path);
        errdefer allocator.free(owned_path);
        const owned_bytes = try allocator.dupe(u8, bytes);
        errdefer allocator.free(owned_bytes);

        if (std.mem.indexOfScalar(u8, owned_bytes, 0) != null) {
            const empty_display = try allocator.alloc(u8, 0);
            errdefer allocator.free(empty_display);
            const empty_mapping = try allocator.alloc(usize, 0);
            errdefer allocator.free(empty_mapping);
            const empty_graphemes = try allocator.alloc(Grapheme, 0);
            errdefer allocator.free(empty_graphemes);
            const line_starts = try allocator.dupe(usize, &.{0});
            errdefer allocator.free(line_starts);
            const display_line_starts = try allocator.dupe(usize, &.{0});

            return .{
                .allocator = allocator,
                .path = owned_path,
                .bytes = owned_bytes,
                .display_bytes = empty_display,
                .display_to_source = empty_mapping,
                .graphemes = empty_graphemes,
                .line_starts = line_starts,
                .display_line_starts = display_line_starts,
                .generation = generation,
                .encoding = .binary,
                .metadata = metadata,
            };
        }

        var display: std.ArrayList(u8) = .empty;
        defer display.deinit(allocator);
        var mapping: std.ArrayList(usize) = .empty;
        defer mapping.deinit(allocator);
        try mapping.append(allocator, 0);

        var source_index: usize = 0;
        var invalid = false;
        while (source_index < owned_bytes.len) {
            const sequence_length = std.unicode.utf8ByteSequenceLength(owned_bytes[source_index]) catch 1;
            const remaining = owned_bytes.len - source_index;
            const valid_sequence = sequence_length <= remaining and
                std.unicode.utf8ValidateSlice(owned_bytes[source_index .. source_index + sequence_length]);

            if (valid_sequence) {
                for (owned_bytes[source_index .. source_index + sequence_length], 0..) |byte, offset| {
                    try display.append(allocator, byte);
                    try mapping.append(allocator, source_index + offset + 1);
                }
                source_index += sequence_length;
            } else {
                invalid = true;
                try display.appendSlice(allocator, "\u{fffd}");
                try mapping.append(allocator, source_index);
                try mapping.append(allocator, source_index);
                source_index += 1;
                try mapping.append(allocator, source_index);
            }
        }

        var graphemes: std.ArrayList(Grapheme) = .empty;
        defer graphemes.deinit(allocator);
        var line_starts: std.ArrayList(usize) = .empty;
        defer line_starts.deinit(allocator);
        try line_starts.append(allocator, 0);
        var display_line_starts: std.ArrayList(usize) = .empty;
        defer display_line_starts.deinit(allocator);
        try display_line_starts.append(allocator, 0);

        var display_index: usize = 0;
        var line: usize = 0;
        var visual_column: u32 = 0;
        while (display_index < display.items.len) {
            const display_end = segmenter.next(display.items, display_index);
            std.debug.assert(display_end > display_index and display_end <= display.items.len);
            const source_start = mapping.items[display_index];
            const source_end = mapping.items[display_end];
            const slice = display.items[display_index..display_end];
            const is_newline = slice.len != 0 and slice[slice.len - 1] == '\n';
            const width: u16 = if (is_newline)
                0
            else if (std.mem.eql(u8, slice, "\t"))
                4
            else if (slice.len == 1 and (slice[0] < 0x20 or slice[0] == 0x7f))
                1
            else
                segmenter.width(slice);

            try graphemes.append(allocator, .{
                .source = .{ .start = source_start, .end = source_end },
                .display = .{ .start = display_index, .end = display_end },
                .line = line,
                .visual_column = visual_column,
                .width = width,
            });

            if (is_newline) {
                line += 1;
                visual_column = 0;
                try line_starts.append(allocator, source_end);
                try display_line_starts.append(allocator, display_end);
            } else {
                visual_column += width;
            }
            display_index = display_end;
        }

        const owned_display = try display.toOwnedSlice(allocator);
        errdefer allocator.free(owned_display);
        const owned_mapping = try mapping.toOwnedSlice(allocator);
        errdefer allocator.free(owned_mapping);
        const owned_graphemes = try graphemes.toOwnedSlice(allocator);
        errdefer allocator.free(owned_graphemes);
        const owned_line_starts = try line_starts.toOwnedSlice(allocator);
        errdefer allocator.free(owned_line_starts);
        const owned_display_line_starts = try display_line_starts.toOwnedSlice(allocator);

        return .{
            .allocator = allocator,
            .path = owned_path,
            .bytes = owned_bytes,
            .display_bytes = owned_display,
            .display_to_source = owned_mapping,
            .graphemes = owned_graphemes,
            .line_starts = owned_line_starts,
            .display_line_starts = owned_display_line_starts,
            .generation = generation,
            .encoding = if (invalid) .invalid_utf8 else .utf8,
            .metadata = metadata,
        };
    }

    pub fn deinit(self: *Snapshot) void {
        self.allocator.free(self.path);
        self.allocator.free(self.bytes);
        self.allocator.free(self.display_bytes);
        self.allocator.free(self.display_to_source);
        self.allocator.free(self.graphemes);
        self.allocator.free(self.line_starts);
        self.allocator.free(self.display_line_starts);
        self.* = undefined;
    }

    pub fn lineCount(self: Snapshot) usize {
        return self.line_starts.len;
    }

    pub fn sourceRangeForGrapheme(self: Snapshot, index: usize) ByteRange {
        if (self.graphemes.len == 0) return .{ .start = 0, .end = 0 };
        return self.graphemes[@min(index, self.graphemes.len - 1)].source;
    }

    pub fn graphemeRangeForLine(self: Snapshot, requested_line: usize) IndexRange {
        const target = @min(requested_line, self.line_starts.len -| 1);
        var low: usize = 0;
        var high = self.graphemes.len;
        while (low < high) {
            const middle = low + (high - low) / 2;
            if (self.graphemes[middle].line < target) low = middle + 1 else high = middle;
        }
        const start = low;
        high = self.graphemes.len;
        while (low < high) {
            const middle = low + (high - low) / 2;
            if (self.graphemes[middle].line <= target) low = middle + 1 else high = middle;
        }
        return .{ .start = start, .end = low };
    }

    pub fn lineDisplayRange(self: Snapshot, requested_line: usize) ByteRange {
        if (self.encoding == .binary or self.line_starts.len == 0) return .{ .start = 0, .end = 0 };
        const target = @min(requested_line, self.display_line_starts.len - 1);
        const start = self.display_line_starts[target];
        var end = if (target + 1 < self.display_line_starts.len)
            self.display_line_starts[target + 1]
        else
            self.display_bytes.len;
        if (end > start and self.display_bytes[end - 1] == '\n') end -= 1;
        if (end > start and self.display_bytes[end - 1] == '\r') end -= 1;
        return .{ .start = start, .end = end };
    }
};

fn scalarNext(_: ?*const anyopaque, text: []const u8, start: usize) usize {
    const length = std.unicode.utf8ByteSequenceLength(text[start]) catch 1;
    return @min(text.len, start + length);
}

fn scalarWidth(_: ?*const anyopaque, text: []const u8) u16 {
    return if (std.mem.eql(u8, text, "\n")) 0 else 1;
}

const scalar_segmenter: text_segmentation.Segmenter = .{
    .next_fn = scalarNext,
    .width_fn = scalarWidth,
};

test "valid source bytes and mappings remain stable" {
    var snapshot = try Snapshot.init(
        std.testing.allocator,
        "src/main.zig",
        "aé\nβ",
        7,
        .{ .size = 7 },
        scalar_segmenter,
    );
    defer snapshot.deinit();

    try std.testing.expectEqual(Encoding.utf8, snapshot.encoding);
    try std.testing.expectEqualStrings("aé\nβ", snapshot.display_bytes);
    try std.testing.expectEqual(@as(u64, 7), snapshot.generation);
    try std.testing.expectEqual(@as(usize, 2), snapshot.lineCount());
    try std.testing.expectEqual(ByteRange{ .start = 1, .end = 3 }, snapshot.sourceRangeForGrapheme(1));
}

test "invalid UTF-8 is replaced without losing source byte boundaries" {
    const source = [_]u8{ 'a', 0xff, 'b' };
    var snapshot = try Snapshot.init(
        std.testing.allocator,
        "bad.txt",
        &source,
        1,
        .{ .size = source.len },
        scalar_segmenter,
    );
    defer snapshot.deinit();

    try std.testing.expectEqual(Encoding.invalid_utf8, snapshot.encoding);
    try std.testing.expectEqualStrings("a\u{fffd}b", snapshot.display_bytes);
    try std.testing.expectEqual(ByteRange{ .start = 1, .end = 2 }, snapshot.sourceRangeForGrapheme(1));
    try std.testing.expectEqualSlices(u8, &source, snapshot.bytes);
}

test "CRLF line endings are mapped but omitted from displayed lines" {
    var snapshot = try Snapshot.init(
        std.testing.allocator,
        "windows.txt",
        "one\r\ntwo",
        1,
        .{ .size = 8 },
        scalar_segmenter,
    );
    defer snapshot.deinit();

    try std.testing.expectEqual(@as(usize, 2), snapshot.lineCount());
    const first = snapshot.lineDisplayRange(0);
    const second = snapshot.lineDisplayRange(1);
    try std.testing.expectEqualStrings("one", snapshot.display_bytes[first.start..first.end]);
    try std.testing.expectEqualStrings("two", snapshot.display_bytes[second.start..second.end]);
}

test "NUL-containing content is represented as binary metadata" {
    const source = [_]u8{ 'a', 0, 'b' };
    var snapshot = try Snapshot.init(
        std.testing.allocator,
        "image.bin",
        &source,
        1,
        .{ .size = source.len },
        scalar_segmenter,
    );
    defer snapshot.deinit();

    try std.testing.expectEqual(Encoding.binary, snapshot.encoding);
    try std.testing.expectEqual(@as(usize, 0), snapshot.display_bytes.len);
    try std.testing.expectEqualSlices(u8, &source, snapshot.bytes);
}
