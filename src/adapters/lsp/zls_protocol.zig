//! ZLS-specific LSP lifecycle messages and transcript state machine.

const std = @import("std");
const lsp = @import("../../model/lsp.zig");

pub const VersionError = error{ MalformedVersion, IncompatibleVersion };

pub fn validateVersion(output: []const u8) VersionError!void {
    const trimmed = std.mem.trim(u8, output, " \t\r\n");
    var tokens = std.mem.tokenizeAny(u8, trimmed, " \t");
    var version = tokens.next() orelse return error.MalformedVersion;
    if (std.ascii.eqlIgnoreCase(version, "zls")) version = tokens.next() orelse return error.MalformedVersion;
    if (version.len > 0 and version[0] == 'v') version = version[1..];
    var components = std.mem.splitScalar(u8, version, '.');
    _ = std.fmt.parseInt(u32, components.next() orelse return error.MalformedVersion, 10) catch return error.MalformedVersion;
    const minor = std.fmt.parseInt(u32, components.next() orelse return error.MalformedVersion, 10) catch return error.MalformedVersion;
    _ = std.fmt.parseInt(u32, components.next() orelse return error.MalformedVersion, 10) catch return error.MalformedVersion;
    if (components.next() != null) return error.MalformedVersion;
    if (minor != 16) return error.IncompatibleVersion;
}

pub const Lifecycle = struct {
    state: State = .stopped,
    next_id: i64 = 1,
    initialize_id: ?i64 = null,
    shutdown_id: ?i64 = null,
    encoding: lsp.PositionEncoding = .utf16,
    open_uri: ?[]const u8 = null,

    pub const State = enum { stopped, starting, initializing, ready, shutting_down, crashed };

    pub fn begin(self: *Lifecycle) i64 {
        std.debug.assert(self.state == .stopped or self.state == .crashed);
        self.state = .starting;
        const id = self.takeId();
        self.initialize_id = id;
        self.state = .initializing;
        return id;
    }

    pub fn initialized(self: *Lifecycle, id: i64, selected_encoding: ?[]const u8) !void {
        if (self.state != .initializing or self.initialize_id != id) return error.UnexpectedResponse;
        self.encoding = if (selected_encoding) |encoding|
            if (std.mem.eql(u8, encoding, "utf-8")) .utf8 else if (std.mem.eql(u8, encoding, "utf-16")) .utf16 else return error.UnsupportedPositionEncoding
        else
            .utf16;
        self.initialize_id = null;
        self.state = .ready;
    }

    pub fn open(self: *Lifecycle, uri: []const u8) !void {
        if (self.state != .ready) return error.NotReady;
        if (self.open_uri != null) return error.DocumentAlreadyOpen;
        self.open_uri = uri;
    }

    pub fn close(self: *Lifecycle, uri: []const u8) !void {
        const active = self.open_uri orelse return error.DocumentNotOpen;
        if (!std.mem.eql(u8, active, uri)) return error.DocumentMismatch;
        self.open_uri = null;
    }

    pub fn beginShutdown(self: *Lifecycle) !i64 {
        if (self.open_uri != null) return error.DocumentStillOpen;
        if (self.state != .ready) return error.NotReady;
        self.state = .shutting_down;
        const id = self.takeId();
        self.shutdown_id = id;
        return id;
    }

    pub fn shutdownComplete(self: *Lifecycle, id: i64) !void {
        if (self.state != .shutting_down or self.shutdown_id != id) return error.UnexpectedResponse;
        self.shutdown_id = null;
        self.state = .stopped;
    }

    pub fn crash(self: *Lifecycle) void {
        self.open_uri = null;
        self.initialize_id = null;
        self.shutdown_id = null;
        self.state = .crashed;
    }

    fn takeId(self: *Lifecycle) i64 {
        const id = self.next_id;
        self.next_id += 1;
        return id;
    }
};

pub fn initializeBody(allocator: std.mem.Allocator, id: i64, root_uri: []const u8) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, .{
        .jsonrpc = "2.0",
        .id = id,
        .method = "initialize",
        .params = .{
            .processId = @as(?i64, null),
            .clientInfo = .{ .name = "fiew" },
            .rootUri = root_uri,
            .workspaceFolders = &.{.{ .uri = root_uri, .name = "repository" }},
            .capabilities = .{
                .general = .{ .positionEncodings = &.{ "utf-8", "utf-16" } },
                .workspace = .{ .applyEdit = false, .workspaceEdit = .{ .documentChanges = false } },
                .textDocument = .{
                    .definition = .{ .dynamicRegistration = false, .linkSupport = true },
                    .references = .{ .dynamicRegistration = false },
                    .hover = .{ .dynamicRegistration = false, .contentFormat = &.{ "markdown", "plaintext" } },
                },
            },
            // This narrows ZLS behavior but is not represented as a sandbox.
            .initializationOptions = .{ .enable_build_on_save = false },
        },
    }, .{});
}

pub fn initializedBody(allocator: std.mem.Allocator) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, .{
        .jsonrpc = "2.0",
        .method = "initialized",
        .params = @as(struct {}, .{}),
    }, .{});
}

pub fn didOpenBody(allocator: std.mem.Allocator, uri: []const u8, version: i64, text: []const u8) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, .{
        .jsonrpc = "2.0",
        .method = "textDocument/didOpen",
        .params = .{ .textDocument = .{ .uri = uri, .languageId = "zig", .version = version, .text = text } },
    }, .{});
}

pub fn didCloseBody(allocator: std.mem.Allocator, uri: []const u8) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, .{
        .jsonrpc = "2.0",
        .method = "textDocument/didClose",
        .params = .{ .textDocument = .{ .uri = uri } },
    }, .{});
}

pub fn definitionBody(
    allocator: std.mem.Allocator,
    id: i64,
    uri: []const u8,
    position: lsp.Position,
) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, .{
        .jsonrpc = "2.0",
        .id = id,
        .method = "textDocument/definition",
        .params = .{
            .textDocument = .{ .uri = uri },
            .position = position,
        },
    }, .{});
}

pub fn referencesBody(
    allocator: std.mem.Allocator,
    id: i64,
    uri: []const u8,
    position: lsp.Position,
) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, .{
        .jsonrpc = "2.0",
        .id = id,
        .method = "textDocument/references",
        .params = .{
            .textDocument = .{ .uri = uri },
            .position = position,
            // The declaration is not synthesized by fiew. It appears only if
            // ZLS includes it in this requested result set.
            .context = .{ .includeDeclaration = true },
        },
    }, .{});
}

pub fn hoverBody(
    allocator: std.mem.Allocator,
    id: i64,
    uri: []const u8,
    position: lsp.Position,
) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, .{
        .jsonrpc = "2.0",
        .id = id,
        .method = "textDocument/hover",
        .params = .{
            .textDocument = .{ .uri = uri },
            .position = position,
        },
    }, .{});
}

pub fn cancelRequestBody(allocator: std.mem.Allocator, id: i64) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, .{
        .jsonrpc = "2.0",
        .method = "$/cancelRequest",
        .params = .{ .id = id },
    }, .{});
}

pub fn shutdownBody(allocator: std.mem.Allocator, id: i64) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, .{ .jsonrpc = "2.0", .id = id, .method = "shutdown" }, .{});
}

pub fn exitBody(allocator: std.mem.Allocator) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, .{ .jsonrpc = "2.0", .method = "exit" }, .{});
}

/// Parse the negotiated encoding from an initialize response. Omission follows
/// LSP's UTF-16 default.
pub fn initializeEncoding(allocator: std.mem.Allocator, body: []const u8, expected_id: i64) !?[]const u8 {
    const Response = struct {
        id: i64,
        result: struct { capabilities: struct { positionEncoding: ?[]const u8 = null } },
    };
    const parsed = try std.json.parseFromSlice(Response, allocator, body, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    if (parsed.value.id != expected_id) return error.UnexpectedResponse;
    const value = parsed.value.result.capabilities.positionEncoding orelse return null;
    if (std.mem.eql(u8, value, "utf-8")) return "utf-8";
    if (std.mem.eql(u8, value, "utf-16")) return "utf-16";
    return error.UnsupportedPositionEncoding;
}

test "only the matching ZLS minor line is accepted" {
    try validateVersion("0.16.0\n");
    try validateVersion("zls 0.16.7\n");
    try std.testing.expectError(error.IncompatibleVersion, validateVersion("0.15.0"));
    try std.testing.expectError(error.MalformedVersion, validateVersion("development"));
}

test "lifecycle transcript balances initialize open close shutdown and exit" {
    var lifecycle: Lifecycle = .{};
    const initialize_id = lifecycle.begin();
    const initialize = try initializeBody(std.testing.allocator, initialize_id, "file:///repo");
    defer std.testing.allocator.free(initialize);
    try std.testing.expect(std.mem.indexOf(u8, initialize, "\"applyEdit\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, initialize, "\"dynamicRegistration\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, initialize, "\"linkSupport\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, initialize, "\"references\"") != null);
    const initialized = try initializedBody(std.testing.allocator);
    defer std.testing.allocator.free(initialized);
    try std.testing.expect(std.mem.indexOf(u8, initialized, "\"params\":{}") != null);
    const cancel = try cancelRequestBody(std.testing.allocator, 9);
    defer std.testing.allocator.free(cancel);
    try std.testing.expect(std.mem.indexOf(u8, cancel, "\"method\":\"$/cancelRequest\"") != null);
    try lifecycle.initialized(initialize_id, "utf-8");
    try lifecycle.open("file:///repo/main.zig");
    try lifecycle.close("file:///repo/main.zig");
    const shutdown_id = try lifecycle.beginShutdown();
    try lifecycle.shutdownComplete(shutdown_id);
    try std.testing.expectEqual(Lifecycle.State.stopped, lifecycle.state);
}

test "document lifecycle refuses imbalance and mismatched responses" {
    var lifecycle: Lifecycle = .{};
    const id = lifecycle.begin();
    try std.testing.expectError(error.UnexpectedResponse, lifecycle.initialized(id + 1, null));
    try lifecycle.initialized(id, null);
    try lifecycle.open("file:///one.zig");
    try std.testing.expectError(error.DocumentAlreadyOpen, lifecycle.open("file:///two.zig"));
    try std.testing.expectError(error.DocumentMismatch, lifecycle.close("file:///two.zig"));
    try std.testing.expectError(error.DocumentStillOpen, lifecycle.beginShutdown());
}

test "reference request asks ZLS to decide whether to include the declaration" {
    const body = try referencesBody(std.testing.allocator, 7, "file:///repo/main.zig", .{ .line = 2, .character = 3 });
    defer std.testing.allocator.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"method\":\"textDocument/references\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"includeDeclaration\":true") != null);
}

test "hover capability and request advertise only readable content" {
    const initialize = try initializeBody(std.testing.allocator, 1, "file:///repo");
    defer std.testing.allocator.free(initialize);
    try std.testing.expect(std.mem.indexOf(u8, initialize, "\"hover\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, initialize, "\"markdown\"") != null);
    const request = try hoverBody(std.testing.allocator, 2, "file:///repo/main.zig", .{ .line = 3, .character = 4 });
    defer std.testing.allocator.free(request);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"method\":\"textDocument/hover\"") != null);
}

test "initialize response negotiates UTF-8 and defaults to UTF-16" {
    try std.testing.expectEqualStrings("utf-8", (try initializeEncoding(std.testing.allocator, "{\"id\":1,\"result\":{\"capabilities\":{\"positionEncoding\":\"utf-8\"}}}", 1)).?);
    try std.testing.expect((try initializeEncoding(std.testing.allocator, "{\"id\":1,\"result\":{\"capabilities\":{}}}", 1)) == null);
}
