//! Private review-local ordered reading Trails.

const std = @import("std");
const anchor = @import("anchor.zig");

pub const schema = "fiew.trail/v1";
pub const max_title_bytes: usize = 80;
pub const max_note_bytes: usize = 4096;
pub const id_bytes: usize = 32;

pub const Status = enum { current, outdated };

pub const Point = struct {
    path: []const u8,
    /// Immutable one-based captured line retained when the point is Outdated.
    line: usize,
    /// Current uniquely re-anchored line; null while the captured line remains current.
    anchored_line: ?usize = null,
    column: usize = 0,
    source_offset: usize,
    line_offset: usize,
    content: []const u8,
    context: anchor.Context,
    status: Status = .current,
};

pub const Owner = struct {
    review: []const u8,
};

/// One independently persisted Trail. Its identity and owner never change.
pub const Trail = struct {
    id: []const u8,
    owner: Owner,
    title: []const u8,
    note: []const u8 = "",
    points: []const Point,
};

const Envelope = struct { schema: []const u8, data: Trail };
pub const ParseError = error{ MalformedTrail, InvalidSchema, FutureSchema } || std.mem.Allocator.Error;

pub const Parsed = struct {
    parsed: std.json.Parsed(Envelope),
    pub fn value(self: *const Parsed) *const Trail {
        return &self.parsed.value.data;
    }
    pub fn deinit(self: Parsed) void {
        self.parsed.deinit();
    }
};

pub fn validId(value: []const u8) bool {
    if (value.len != id_bytes) return false;
    for (value) |byte| if (!std.ascii.isDigit(byte) and (byte < 'a' or byte > 'f')) return false;
    return true;
}

pub fn validTitle(value: []const u8) bool {
    return value.len != 0 and value.len <= max_title_bytes and
        std.mem.trim(u8, value, " \t\r\n").len != 0 and std.unicode.utf8ValidateSlice(value);
}

pub fn validNote(value: []const u8) bool {
    return value.len <= max_note_bytes and std.unicode.utf8ValidateSlice(value);
}

pub fn serialize(allocator: std.mem.Allocator, value: Trail) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, Envelope{ .schema = schema, .data = value }, .{ .whitespace = .indent_2 });
}

pub fn parse(allocator: std.mem.Allocator, bytes: []const u8) ParseError!Parsed {
    const Probe = struct { schema: []const u8 };
    const probe = std.json.parseFromSlice(Probe, allocator, bytes, .{ .ignore_unknown_fields = true }) catch return error.MalformedTrail;
    defer probe.deinit();
    if (!std.mem.eql(u8, probe.value.schema, schema)) {
        if (std.mem.startsWith(u8, probe.value.schema, "fiew.trail/v")) return error.FutureSchema;
        return error.InvalidSchema;
    }
    const parsed = std.json.parseFromSlice(Envelope, allocator, bytes, .{ .allocate = .alloc_always }) catch return error.MalformedTrail;
    errdefer parsed.deinit();
    const value = &parsed.value.data;
    if (!validId(value.id) or value.owner.review.len == 0 or !std.mem.eql(u8, std.fs.path.basename(value.owner.review), value.owner.review) or
        !validTitle(value.title) or !validNote(value.note) or value.points.len < 2) return error.MalformedTrail;
    for (value.points) |point| {
        if (point.path.len == 0 or point.line == 0 or (point.anchored_line != null and point.anchored_line.? == 0) or !std.unicode.utf8ValidateSlice(point.content) or
            point.context.bytes.len == 0 or point.context.target_start > point.context.target_end or
            point.context.target_end > point.context.bytes.len or point.line_offset > point.context.target_end - point.context.target_start or
            point.source_offset != point.context.targetOffset(point.context.original_start) + point.line_offset)
            return error.MalformedTrail;
    }
    return .{ .parsed = parsed };
}

test "standalone Trail envelope preserves identity, ownership, and ordered points" {
    const points = [_]Point{
        .{ .path = "a.zig", .line = 1, .source_offset = 0, .line_offset = 0, .content = "a", .context = .{ .bytes = "a\n", .original_start = 0, .target_start = 0, .target_end = 1 } },
        .{ .path = "b.zig", .line = 2, .source_offset = 2, .line_offset = 0, .content = "b", .context = .{ .bytes = "b\n", .original_start = 2, .target_start = 0, .target_end = 1 } },
    };
    const item: Trail = .{ .id = "0123456789abcdef0123456789abcdef", .owner = .{ .review = "review.json" }, .title = "Read path", .note = "why", .points = &points };
    const bytes = try serialize(std.testing.allocator, item);
    defer std.testing.allocator.free(bytes);
    var parsed = try parse(std.testing.allocator, bytes);
    defer parsed.deinit();
    try std.testing.expectEqualStrings(item.id, parsed.value().id);
    try std.testing.expectEqualStrings("review.json", parsed.value().owner.review);
    try std.testing.expectEqualStrings("b.zig", parsed.value().points[1].path);
    try std.testing.expectError(error.FutureSchema, parse(std.testing.allocator, "{\"schema\":\"fiew.trail/v2\",\"data\":{}}"));
}
