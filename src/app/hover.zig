//! Bounded, terminal-safe transient hover content.

const std = @import("std");
const syntax = @import("../model/syntax.zig");

pub const max_bytes: usize = 64 << 10;

pub const Content = struct {
    allocator: std.mem.Allocator,
    text: []u8,
    scroll: usize = 0,
    document_generation: u64,
    syntax_data: ?syntax.ParseData = null,

    pub fn init(
        allocator: std.mem.Allocator,
        source: []const u8,
        document_generation: u64,
    ) !Content {
        return .{
            .allocator = allocator,
            .text = try sanitize(allocator, source),
            .document_generation = document_generation,
        };
    }

    pub fn deinit(self: *Content) void {
        if (self.syntax_data) |*data| data.deinit();
        self.allocator.free(self.text);
        self.* = undefined;
    }

    pub fn lineCount(self: Content) usize {
        if (self.text.len == 0) return 0;
        return std.mem.count(u8, self.text, "\n") + 1;
    }

    pub const Line = struct {
        text: []const u8,
        source_start: usize,
    };

    pub fn line(self: Content, requested: usize) ?Line {
        var iterator = std.mem.splitScalar(u8, self.text, '\n');
        var index: usize = 0;
        var source_start: usize = 0;
        while (iterator.next()) |value| : (index += 1) {
            if (index == requested) return .{ .text = value, .source_start = source_start };
            source_start += value.len + 1;
        }
        return null;
    }

    pub fn setSyntax(self: *Content, data: syntax.ParseData) void {
        if (self.syntax_data) |*previous| previous.deinit();
        self.syntax_data = data;
    }

    pub fn move(self: *Content, delta: isize, viewport_rows: usize) void {
        const count = self.lineCount();
        const maximum = count -| @max(viewport_rows, 1);
        const current: isize = @intCast(self.scroll);
        self.scroll = @intCast(std.math.clamp(current + delta, 0, @as(isize, @intCast(maximum))));
    }
};

/// Keep Markdown and unknown markup readable while neutralizing terminal
/// controls. CRLF is normalized and tabs become four spaces.
pub fn sanitize(allocator: std.mem.Allocator, source: []const u8) ![]u8 {
    var output: std.ArrayList(u8) = .empty;
    defer output.deinit(allocator);
    var index: usize = 0;
    var truncated = false;
    while (index < source.len) {
        var replacement: []const u8 = undefined;
        var consumed: usize = 1;
        const byte = source[index];
        if (byte == '\r') {
            if (index + 1 < source.len and source[index + 1] == '\n') consumed = 2;
            replacement = "\n";
        } else if (byte == '\n') {
            replacement = "\n";
        } else if (byte == '\t') {
            replacement = "    ";
        } else if (byte < 0x20 or byte == 0x7f) {
            replacement = "\xef\xbf\xbd";
        } else {
            consumed = std.unicode.utf8ByteSequenceLength(byte) catch 1;
            if (index + consumed > source.len) consumed = 1;
            replacement = source[index .. index + consumed];
        }
        if (output.items.len + replacement.len > max_bytes - 24) {
            truncated = true;
            break;
        }
        try output.appendSlice(allocator, replacement);
        index += consumed;
    }
    if (truncated) try output.appendSlice(allocator, "\n\xe2\x80\xa6 hover truncated");
    return output.toOwnedSlice(allocator);
}

test "hover sanitization preserves readable markup and bounds controls" {
    const source = "**type** <custom>\r\nvalue\t\x1b[31m";
    const value = try sanitize(std.testing.allocator, source);
    defer std.testing.allocator.free(value);
    try std.testing.expectEqualStrings("**type** <custom>\nvalue    \xef\xbf\xbd[31m", value);
}

test "hover sanitization truncates oversized server content" {
    const source = try std.testing.allocator.alloc(u8, max_bytes + 100);
    defer std.testing.allocator.free(source);
    @memset(source, 'x');
    const value = try sanitize(std.testing.allocator, source);
    defer std.testing.allocator.free(value);
    try std.testing.expect(value.len <= max_bytes);
    try std.testing.expect(std.mem.endsWith(u8, value, "hover truncated"));
}

test "hover content scroll remains bounded" {
    var content = try Content.init(std.testing.allocator, "one\ntwo\nthree\nfour", 7);
    defer content.deinit();
    content.move(20, 2);
    try std.testing.expectEqual(@as(usize, 2), content.scroll);
    content.move(-20, 2);
    try std.testing.expectEqual(@as(usize, 0), content.scroll);
}
