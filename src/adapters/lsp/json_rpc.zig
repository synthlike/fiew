//! Bounded LSP JSON-RPC framing and the defensive read-only protocol boundary.

const std = @import("std");

pub const max_header_bytes: usize = 8 << 10;
pub const max_message_bytes: usize = 8 << 20;

pub const Frame = struct {
    body: []const u8,
    consumed: usize,
};

pub const FrameError = error{
    Incomplete,
    HeaderTooLarge,
    MessageTooLarge,
    MalformedHeader,
    MissingContentLength,
    DuplicateContentLength,
};

/// Parse one complete LSP frame from a transcript buffer without allocating.
pub fn parseFrame(bytes: []const u8) FrameError!Frame {
    const marker = "\r\n\r\n";
    const header_end = std.mem.indexOf(u8, bytes, marker) orelse {
        if (bytes.len > max_header_bytes) return error.HeaderTooLarge;
        return error.Incomplete;
    };
    if (header_end > max_header_bytes) return error.HeaderTooLarge;

    var length: ?usize = null;
    var lines = std.mem.splitSequence(u8, bytes[0..header_end], "\r\n");
    while (lines.next()) |line| {
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse return error.MalformedHeader;
        const name = std.mem.trim(u8, line[0..colon], " \t");
        const value = std.mem.trim(u8, line[colon + 1 ..], " \t");
        if (std.ascii.eqlIgnoreCase(name, "Content-Length")) {
            if (length != null) return error.DuplicateContentLength;
            length = std.fmt.parseInt(usize, value, 10) catch return error.MalformedHeader;
        }
    }
    const body_len = length orelse return error.MissingContentLength;
    if (body_len > max_message_bytes) return error.MessageTooLarge;
    const body_start = header_end + marker.len;
    if (body_start + body_len > bytes.len) return error.Incomplete;
    return .{ .body = bytes[body_start .. body_start + body_len], .consumed = body_start + body_len };
}

pub fn appendFrame(allocator: std.mem.Allocator, output: *std.ArrayList(u8), body: []const u8) !void {
    if (body.len > max_message_bytes) return error.MessageTooLarge;
    try output.writer(allocator).print("Content-Length: {d}\r\n\r\n", .{body.len});
    try output.appendSlice(allocator, body);
}

pub const ServerRequest = struct {
    id: std.json.Value,
    method: []const u8,
};

/// Extract only server-to-client requests. Notifications and responses return
/// null. The returned strings and values borrow from `parsed`.
pub fn serverRequest(parsed: std.json.Value) ?ServerRequest {
    const object = switch (parsed) {
        .object => |value| value,
        else => return null,
    };
    const id = object.get("id") orelse return null;
    const method_value = object.get("method") orelse return null;
    const method = switch (method_value) {
        .string => |value| value,
        else => return null,
    };
    return .{ .id = id, .method = method };
}

pub const Refusal = enum { apply_edit, method_not_found };

/// Every server request capable of mutation or command execution is refused.
/// Unknown requests are also rejected because Skaut advertises no such feature.
pub fn refusalFor(method: []const u8) Refusal {
    return if (std.mem.eql(u8, method, "workspace/applyEdit")) .apply_edit else .method_not_found;
}

pub fn refusalBody(allocator: std.mem.Allocator, request: ServerRequest) ![]u8 {
    return switch (refusalFor(request.method)) {
        .apply_edit => std.json.Stringify.valueAlloc(allocator, .{
            .jsonrpc = "2.0",
            .id = request.id,
            .result = .{ .applied = false, .failureReason = "Skaut is read-only" },
        }, .{}),
        .method_not_found => std.json.Stringify.valueAlloc(allocator, .{
            .jsonrpc = "2.0",
            .id = request.id,
            .@"error" = .{ .code = -32601, .message = "method not supported by read-only Skaut client" },
        }, .{}),
    };
}

test "bounded framing parses consecutive transcript messages" {
    const transcript =
        "Content-Length: 2\r\n\r\n{}" ++
        "Content-Length: 4\r\nContent-Type: application/vscode-jsonrpc; charset=utf-8\r\n\r\nnull";
    const first = try parseFrame(transcript);
    try std.testing.expectEqualStrings("{}", first.body);
    const second = try parseFrame(transcript[first.consumed..]);
    try std.testing.expectEqualStrings("null", second.body);
}

test "framing rejects malformed, duplicate, oversized, and incomplete input" {
    try std.testing.expectError(error.MissingContentLength, parseFrame("Other: 2\r\n\r\n{}"));
    try std.testing.expectError(error.DuplicateContentLength, parseFrame("Content-Length: 2\r\nContent-Length: 2\r\n\r\n{}"));
    try std.testing.expectError(error.Incomplete, parseFrame("Content-Length: 3\r\n\r\n{}"));
    var buffer: [128]u8 = undefined;
    const oversized = try std.fmt.bufPrint(&buffer, "Content-Length: {d}\r\n\r\n", .{max_message_bytes + 1});
    try std.testing.expectError(error.MessageTooLarge, parseFrame(oversized));
}

test "workspace edits are refused and all other server requests are rejected" {
    var apply = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"workspace/applyEdit\",\"params\":{}}", .{});
    defer apply.deinit();
    const request = serverRequest(apply.value).?;
    const body = try refusalBody(std.testing.allocator, request);
    defer std.testing.allocator.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"applied\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "read-only") != null);

    var command = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, "{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"workspace/executeCommand\"}", .{});
    defer command.deinit();
    const rejected = try refusalBody(std.testing.allocator, serverRequest(command.value).?);
    defer std.testing.allocator.free(rejected);
    try std.testing.expect(std.mem.indexOf(u8, rejected, "-32601") != null);
}
