//! Private repository-local source bookmarks.

const std = @import("std");
const anchor = @import("anchor.zig");

pub const schema = "skaut.bookmark/v1";
pub const max_label_bytes: usize = 48;

pub const Status = enum { current, outdated };

pub const Bookmark = struct {
    id: u64,
    path: []const u8,
    line: usize,
    column: usize,
    source_offset: usize,
    line_offset: usize,
    context: anchor.Context,
    label: []const u8,
    status: Status = .current,
};

pub const Stored = struct {
    next_id: u64 = 1,
    bookmarks: []const Bookmark = &.{},
};

const Envelope = struct {
    schema: []const u8,
    data: Stored,
};

pub const ParseError = error{ MalformedBookmarks, InvalidSchema, FutureSchema } || std.mem.Allocator.Error;

pub const Parsed = struct {
    parsed: std.json.Parsed(Envelope),

    pub fn value(self: *const Parsed) *const Stored {
        return &self.parsed.value.data;
    }

    pub fn deinit(self: Parsed) void {
        self.parsed.deinit();
    }
};

pub fn serialize(allocator: std.mem.Allocator, value: Stored) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, Envelope{ .schema = schema, .data = value }, .{ .whitespace = .indent_2 });
}

pub fn parse(allocator: std.mem.Allocator, bytes: []const u8) ParseError!Parsed {
    const Probe = struct { schema: []const u8 };
    const probe = std.json.parseFromSlice(Probe, allocator, bytes, .{ .ignore_unknown_fields = true }) catch
        return error.MalformedBookmarks;
    defer probe.deinit();
    if (!std.mem.eql(u8, probe.value.schema, schema)) {
        if (std.mem.startsWith(u8, probe.value.schema, "skaut.bookmark/v")) return error.FutureSchema;
        return error.InvalidSchema;
    }
    const parsed = std.json.parseFromSlice(Envelope, allocator, bytes, .{ .allocate = .alloc_always }) catch return error.MalformedBookmarks;
    errdefer parsed.deinit();
    for (parsed.value.data.bookmarks) |item| {
        if (item.id == 0 or item.path.len == 0 or item.line == 0 or item.context.bytes.len == 0 or
            item.context.target_start > item.context.target_end or item.context.target_end > item.context.bytes.len or
            item.line_offset > item.context.target_end - item.context.target_start or
            item.source_offset != item.context.targetOffset(item.context.original_start) + item.line_offset or !validLabel(item.label))
            return error.MalformedBookmarks;
    }
    return .{ .parsed = parsed };
}

pub fn validLabel(label: []const u8) bool {
    return label.len <= max_label_bytes and std.unicode.utf8ValidateSlice(label);
}

test "bookmark envelope round trips and future schemas are refused" {
    const testing = std.testing;
    const items = [_]Bookmark{.{ .id = 1, .path = "src/main.zig", .line = 3, .column = 2, .source_offset = 8, .line_offset = 0, .context = .{ .bytes = "line\n", .original_start = 8, .target_start = 0, .target_end = 4 }, .label = "later" }};
    const bytes = try serialize(testing.allocator, .{ .next_id = 2, .bookmarks = &items });
    defer testing.allocator.free(bytes);
    try testing.expect(std.mem.indexOf(u8, bytes, "\"schema\": \"skaut.bookmark/v1\"") != null);
    var parsed = try parse(testing.allocator, bytes);
    defer parsed.deinit();
    try testing.expectEqualStrings("later", parsed.value().bookmarks[0].label);
    try testing.expectError(error.FutureSchema, parse(testing.allocator, "{\"schema\":\"skaut.bookmark/v2\",\"data\":{}}"));
    const missing_context = "{\"schema\":\"skaut.bookmark/v1\",\"data\":{\"next_id\":2,\"bookmarks\":[{\"id\":1,\"path\":\"a\",\"line\":1,\"column\":0,\"source_offset\":0,\"label\":\"\",\"status\":\"current\"}]}}";
    try testing.expectError(error.MalformedBookmarks, parse(testing.allocator, missing_context));
}

test "empty and short UTF-8 labels are valid" {
    try std.testing.expect(validLabel(""));
    try std.testing.expect(validLabel("check later"));
    try std.testing.expect(validLabel("λ"));
    try std.testing.expect(!validLabel("x" ** (max_label_bytes + 1)));
}
