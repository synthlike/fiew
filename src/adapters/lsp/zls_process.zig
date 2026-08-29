//! Direct, bounded ZLS executable validation and long-lived JSON-RPC process.

const std = @import("std");
const lsp = @import("../../model/lsp.zig");
const json_rpc = @import("json_rpc.zig");
const zls_protocol = @import("zls_protocol.zig");

pub const output_limit: u64 = 64 << 10;
pub const version_timeout: std.Io.Clock.Duration = .{ .raw = .fromSeconds(2), .clock = .real };

pub const ProbeError = error{ NotInstalled, Incompatible, VersionFailed, OutputTooLarge, TimedOut } || std.mem.Allocator.Error;

pub const WireLocation = struct {
    uri: []u8,
    start: lsp.Position,
    end: lsp.Position,

    pub fn deinit(self: *WireLocation, allocator: std.mem.Allocator) void {
        allocator.free(self.uri);
        self.* = undefined;
    }
};

pub const SemanticResponse = struct {
    allocator: std.mem.Allocator,
    encoding: lsp.PositionEncoding,
    locations: []WireLocation,
    hover_text: ?[]u8 = null,

    pub fn deinit(self: *SemanticResponse) void {
        for (self.locations) |*location| location.deinit(self.allocator);
        self.allocator.free(self.locations);
        if (self.hover_text) |text| self.allocator.free(text);
        self.* = undefined;
    }
};

pub const DefinitionResponse = SemanticResponse;
pub const ReferenceResponse = SemanticResponse;
pub const HoverResponse = SemanticResponse;
const SemanticOperation = enum { definition, references, hover };

pub fn fileUri(allocator: std.mem.Allocator, absolute_path: []const u8) ![]u8 {
    if (!std.fs.path.isAbsolute(absolute_path)) return error.NotAbsolute;
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);
    try output.appendSlice(allocator, "file://");
    const hex = "0123456789ABCDEF";
    for (absolute_path) |byte| switch (byte) {
        'A'...'Z', 'a'...'z', '0'...'9', '-', '.', '_', '~', '/', ':' => try output.append(allocator, byte),
        else => {
            try output.append(allocator, '%');
            try output.append(allocator, hex[byte >> 4]);
            try output.append(allocator, hex[byte & 0x0f]);
        },
    };
    return output.toOwnedSlice(allocator);
}

pub fn pathFromFileUri(allocator: std.mem.Allocator, uri: []const u8) ![]u8 {
    if (!std.mem.startsWith(u8, uri, "file:///")) return error.UnsupportedScheme;
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);
    var index: usize = "file://".len;
    while (index < uri.len) {
        if (uri[index] != '%') {
            if (uri[index] == 0) return error.InvalidUri;
            try output.append(allocator, uri[index]);
            index += 1;
            continue;
        }
        if (index + 2 >= uri.len) return error.InvalidUri;
        const high = std.fmt.charToDigit(uri[index + 1], 16) catch return error.InvalidUri;
        const low = std.fmt.charToDigit(uri[index + 2], 16) catch return error.InvalidUri;
        const byte: u8 = @intCast(high * 16 + low);
        if (byte == 0 or byte == '/' or byte == '\\') return error.InvalidUri;
        try output.append(allocator, byte);
        index += 3;
    }
    return output.toOwnedSlice(allocator);
}

pub fn probe(allocator: std.mem.Allocator, io: std.Io, repository: std.Io.Dir) ProbeError!void {
    const result = std.process.run(allocator, io, .{
        .argv = &.{ "zls", "--version" },
        .cwd = .{ .dir = repository },
        .stdout_limit = .limited64(output_limit),
        .stderr_limit = .limited64(output_limit),
        .timeout = .{ .duration = version_timeout },
    }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.FileNotFound => return error.NotInstalled,
        error.StreamTooLong => return error.OutputTooLarge,
        error.Timeout => return error.TimedOut,
        else => return error.VersionFailed,
    };
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);
    switch (result.term) {
        .exited => |code| if (code != 0) return error.VersionFailed,
        else => return error.VersionFailed,
    }
    zls_protocol.validateVersion(result.stdout) catch return error.Incompatible;
}

/// Own one ZLS process until the surrounding I/O future is cancelled. Status is
/// atomic so the application owner can publish it on its regular tick. The
/// process always receives shutdown/exit during unwinding and is then reaped.
pub fn serve(
    allocator: std.mem.Allocator,
    io: std.Io,
    repository: std.Io.Dir,
    root_uri: []const u8,
    document_uri: ?[]const u8,
    document_version: u64,
    document_text: ?[]const u8,
    status: *std.atomic.Value(lsp.Status),
) void {
    probe(allocator, io, repository) catch |err| {
        status.store(switch (err) {
            error.NotInstalled => .not_installed,
            error.Incompatible => .incompatible,
            else => .crashed,
        }, .release);
        return;
    };

    var child = std.process.spawn(io, .{
        .argv = &.{"zls"},
        .cwd = .{ .dir = repository },
        .stdin = .pipe,
        .stdout = .pipe,
        // ZLS diagnostics are not terminal output and must not fill a pipe.
        .stderr = .ignore,
    }) catch {
        status.store(.crashed, .release);
        return;
    };
    defer child.kill(io);

    var write_buffer: [4096]u8 = undefined;
    var writer = child.stdin.?.writerStreaming(io, &write_buffer);
    var read_buffer: [8192]u8 = undefined;
    var reader = child.stdout.?.readerStreaming(io, &read_buffer);
    var lifecycle: zls_protocol.Lifecycle = .{};

    const initialize_id = lifecycle.begin();
    const initialize = zls_protocol.initializeBody(allocator, initialize_id, root_uri) catch {
        status.store(.crashed, .release);
        return;
    };
    defer allocator.free(initialize);
    writeFrame(&writer.interface, initialize) catch {
        status.store(.crashed, .release);
        return;
    };

    while (true) {
        const body = readFrame(allocator, &reader.interface) catch {
            status.store(.crashed, .release);
            orderlyStop(allocator, io, &writer.interface, &reader.interface, &lifecycle);
            return;
        };
        defer allocator.free(body);
        if (handleServerRequest(allocator, &writer.interface, body)) continue;
        const encoding = zls_protocol.initializeEncoding(allocator, body, initialize_id) catch continue;
        lifecycle.initialized(initialize_id, encoding) catch {
            status.store(.crashed, .release);
            orderlyStop(allocator, io, &writer.interface, &reader.interface, &lifecycle);
            return;
        };
        break;
    }

    const initialized = zls_protocol.initializedBody(allocator) catch {
        status.store(.crashed, .release);
        orderlyStop(allocator, io, &writer.interface, &reader.interface, &lifecycle);
        return;
    };
    defer allocator.free(initialized);
    writeFrame(&writer.interface, initialized) catch {
        status.store(.crashed, .release);
        orderlyStop(allocator, io, &writer.interface, &reader.interface, &lifecycle);
        return;
    };
    if (document_uri) |uri| if (document_text) |text| {
        const open = zls_protocol.didOpenBody(allocator, uri, @intCast(document_version), text) catch {
            status.store(.crashed, .release);
            orderlyStop(allocator, io, &writer.interface, &reader.interface, &lifecycle);
            return;
        };
        defer allocator.free(open);
        writeFrame(&writer.interface, open) catch {
            status.store(.crashed, .release);
            orderlyStop(allocator, io, &writer.interface, &reader.interface, &lifecycle);
            return;
        };
        lifecycle.open(uri) catch {
            status.store(.crashed, .release);
            orderlyStop(allocator, io, &writer.interface, &reader.interface, &lifecycle);
            return;
        };
    };
    status.store(.ready, .release);

    while (true) {
        const body = readFrame(allocator, &reader.interface) catch {
            orderlyStop(allocator, io, &writer.interface, &reader.interface, &lifecycle);
            // Cancellation is used for restart, revocation, and application
            // shutdown; the owner publishes the resulting target state.
            return;
        };
        defer allocator.free(body);
        _ = handleServerRequest(allocator, &writer.interface, body);
    }
}

pub fn requestDefinition(
    allocator: std.mem.Allocator,
    io: std.Io,
    repository: std.Io.Dir,
    root_uri: []const u8,
    document_uri: []const u8,
    document_version: u64,
    document_text: []const u8,
    utf8_position: lsp.Position,
    utf16_position: lsp.Position,
) !DefinitionResponse {
    return requestLocations(allocator, io, repository, root_uri, document_uri, document_version, document_text, utf8_position, utf16_position, .definition);
}

pub fn requestReferences(
    allocator: std.mem.Allocator,
    io: std.Io,
    repository: std.Io.Dir,
    root_uri: []const u8,
    document_uri: []const u8,
    document_version: u64,
    document_text: []const u8,
    utf8_position: lsp.Position,
    utf16_position: lsp.Position,
) !ReferenceResponse {
    return requestLocations(allocator, io, repository, root_uri, document_uri, document_version, document_text, utf8_position, utf16_position, .references);
}

pub fn requestHover(
    allocator: std.mem.Allocator,
    io: std.Io,
    repository: std.Io.Dir,
    root_uri: []const u8,
    document_uri: []const u8,
    document_version: u64,
    document_text: []const u8,
    utf8_position: lsp.Position,
    utf16_position: lsp.Position,
) !HoverResponse {
    return requestLocations(allocator, io, repository, root_uri, document_uri, document_version, document_text, utf8_position, utf16_position, .hover);
}

fn requestLocations(
    allocator: std.mem.Allocator,
    io: std.Io,
    repository: std.Io.Dir,
    root_uri: []const u8,
    document_uri: []const u8,
    document_version: u64,
    document_text: []const u8,
    utf8_position: lsp.Position,
    utf16_position: lsp.Position,
    operation: SemanticOperation,
) !SemanticResponse {
    try probe(allocator, io, repository);
    var child = try std.process.spawn(io, .{
        .argv = &.{"zls"},
        .cwd = .{ .dir = repository },
        .stdin = .pipe,
        .stdout = .pipe,
        .stderr = .ignore,
    });
    defer child.kill(io);

    var write_buffer: [4096]u8 = undefined;
    var writer = child.stdin.?.writerStreaming(io, &write_buffer);
    var read_buffer: [8192]u8 = undefined;
    var reader = child.stdout.?.readerStreaming(io, &read_buffer);
    var lifecycle: zls_protocol.Lifecycle = .{};
    defer orderlyStop(allocator, io, &writer.interface, &reader.interface, &lifecycle);

    const initialize_id = lifecycle.begin();
    const initialize = try zls_protocol.initializeBody(allocator, initialize_id, root_uri);
    defer allocator.free(initialize);
    try writeFrame(&writer.interface, initialize);

    var selected_encoding: ?[]const u8 = null;
    while (true) {
        const body = try readFrame(allocator, &reader.interface);
        defer allocator.free(body);
        if (handleServerRequest(allocator, &writer.interface, body)) continue;
        selected_encoding = zls_protocol.initializeEncoding(allocator, body, initialize_id) catch |err| switch (err) {
            error.UnexpectedResponse, error.UnexpectedEndOfInput, error.MissingField => continue,
            else => return err,
        };
        try lifecycle.initialized(initialize_id, selected_encoding);
        break;
    }

    const initialized = try zls_protocol.initializedBody(allocator);
    defer allocator.free(initialized);
    try writeFrame(&writer.interface, initialized);
    const open = try zls_protocol.didOpenBody(allocator, document_uri, @intCast(document_version), document_text);
    defer allocator.free(open);
    try writeFrame(&writer.interface, open);
    try lifecycle.open(document_uri);

    const encoding = lifecycle.encoding;
    const request_id: i64 = 2;
    const position = if (encoding == .utf8) utf8_position else utf16_position;
    const request = switch (operation) {
        .definition => try zls_protocol.definitionBody(allocator, request_id, document_uri, position),
        .references => try zls_protocol.referencesBody(allocator, request_id, document_uri, position),
        .hover => try zls_protocol.hoverBody(allocator, request_id, document_uri, position),
    };
    defer allocator.free(request);
    try writeFrame(&writer.interface, request);

    while (true) {
        const body = readFrame(allocator, &reader.interface) catch |err| {
            const cancel = zls_protocol.cancelRequestBody(allocator, request_id) catch return err;
            defer allocator.free(cancel);
            writeFrame(&writer.interface, cancel) catch {};
            return err;
        };
        defer allocator.free(body);
        if (handleServerRequest(allocator, &writer.interface, body)) continue;
        if (operation == .hover) {
            const hover_text = parseHoverResponse(allocator, body, request_id) catch |err| switch (err) {
                error.NotResponse => continue,
                else => return err,
            };
            errdefer if (hover_text) |text| allocator.free(text);
            return .{
                .allocator = allocator,
                .encoding = encoding,
                .locations = try allocator.alloc(WireLocation, 0),
                .hover_text = hover_text,
            };
        }
        const locations = parseDefinitionResponse(allocator, body, request_id) catch |err| switch (err) {
            error.NotResponse => continue,
            else => return err,
        };
        return .{ .allocator = allocator, .encoding = encoding, .locations = locations };
    }
}

fn orderlyStop(
    allocator: std.mem.Allocator,
    io: std.Io,
    writer: *std.Io.Writer,
    reader: *std.Io.Reader,
    lifecycle: *zls_protocol.Lifecycle,
) void {
    if (lifecycle.open_uri) |uri| {
        const close = zls_protocol.didCloseBody(allocator, uri) catch null;
        if (close) |body| {
            defer allocator.free(body);
            writeFrame(writer, body) catch {};
        }
        lifecycle.close(uri) catch {};
    }
    if (lifecycle.state != .ready) return;
    const id = lifecycle.beginShutdown() catch return;
    const shutdown = zls_protocol.shutdownBody(allocator, id) catch return;
    defer allocator.free(shutdown);
    writeFrame(writer, shutdown) catch return;

    // Wait briefly for the required shutdown response. A silent server remains
    // bounded and is reaped by the process-owner defer.
    const Outcome = union(enum) { response: ?[]u8, timeout };
    var outcomes: [2]Outcome = undefined;
    var select = std.Io.Select(Outcome).init(io, &outcomes);
    select.concurrent(.response, shutdownResponse, .{ allocator, reader, id }) catch return;
    select.concurrent(.timeout, shutdownDelay, .{io}) catch {
        select.cancelDiscard();
        return;
    };
    const outcome = select.await() catch {
        select.cancelDiscard();
        return;
    };
    var matched = false;
    switch (outcome) {
        .response => |body| if (body) |owned| {
            defer allocator.free(owned);
            matched = responseHasId(allocator, owned, id);
        },
        .timeout => {},
    }
    while (select.cancel()) |remaining| switch (remaining) {
        .response => |body| if (body) |owned| allocator.free(owned),
        .timeout => {},
    };
    if (matched) lifecycle.shutdownComplete(id) catch {};

    const exit = zls_protocol.exitBody(allocator) catch return;
    defer allocator.free(exit);
    writeFrame(writer, exit) catch {};
}

fn shutdownResponse(allocator: std.mem.Allocator, reader: *std.Io.Reader, expected_id: i64) ?[]u8 {
    while (true) {
        const body = readFrame(allocator, reader) catch return null;
        if (responseHasId(allocator, body, expected_id)) return body;
        allocator.free(body);
    }
}

fn responseHasId(allocator: std.mem.Allocator, body: []const u8, expected_id: i64) bool {
    const Header = struct { id: ?i64 = null };
    const parsed = std.json.parseFromSlice(Header, allocator, body, .{ .ignore_unknown_fields = true }) catch return false;
    defer parsed.deinit();
    return parsed.value.id == expected_id;
}

fn shutdownDelay(io: std.Io) void {
    io.sleep(.fromMilliseconds(500), .real) catch {};
}

fn handleServerRequest(allocator: std.mem.Allocator, writer: *std.Io.Writer, body: []const u8) bool {
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch return false;
    defer parsed.deinit();
    const request = json_rpc.serverRequest(parsed.value) orelse return false;
    const refusal = json_rpc.refusalBody(allocator, request) catch return true;
    defer allocator.free(refusal);
    writeFrame(writer, refusal) catch {};
    return true;
}

fn writeFrame(writer: *std.Io.Writer, body: []const u8) !void {
    try writer.print("Content-Length: {d}\r\n\r\n", .{body.len});
    try writer.writeAll(body);
    try writer.flush();
}

fn readFrame(allocator: std.mem.Allocator, reader: *std.Io.Reader) ![]u8 {
    var content_length: ?usize = null;
    var header_bytes: usize = 0;
    while (true) {
        const line = (try reader.takeDelimiter('\n')) orelse return error.EndOfStream;
        header_bytes += line.len + 1;
        if (header_bytes > json_rpc.max_header_bytes) return error.HeaderTooLarge;
        const trimmed = std.mem.trimEnd(u8, line, "\r");
        if (trimmed.len == 0) break;
        const colon = std.mem.indexOfScalar(u8, trimmed, ':') orelse return error.MalformedHeader;
        const name = std.mem.trim(u8, trimmed[0..colon], " \t");
        if (std.ascii.eqlIgnoreCase(name, "Content-Length")) {
            if (content_length != null) return error.DuplicateContentLength;
            content_length = std.fmt.parseInt(usize, std.mem.trim(u8, trimmed[colon + 1 ..], " \t"), 10) catch
                return error.MalformedHeader;
        }
    }
    const length = content_length orelse return error.MissingContentLength;
    if (length > json_rpc.max_message_bytes) return error.MessageTooLarge;
    return reader.readAlloc(allocator, length);
}

pub fn parseDefinitionResponse(allocator: std.mem.Allocator, body: []const u8, expected_id: i64) ![]WireLocation {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
    defer parsed.deinit();
    const object = switch (parsed.value) {
        .object => |value| value,
        else => return error.MalformedResponse,
    };
    const id_value = object.get("id") orelse return error.NotResponse;
    const id = switch (id_value) {
        .integer => |value| value,
        else => return error.MalformedResponse,
    };
    if (id != expected_id) return error.NotResponse;
    if (object.get("error") != null) return error.ServerError;
    const result = object.get("result") orelse return error.MalformedResponse;

    var locations: std.ArrayList(WireLocation) = .empty;
    errdefer {
        for (locations.items) |*location| location.deinit(allocator);
        locations.deinit(allocator);
    }
    switch (result) {
        .null => {},
        .object => |value| try appendWireLocation(allocator, &locations, value),
        .array => |values| for (values.items) |value| switch (value) {
            .object => |location| try appendWireLocation(allocator, &locations, location),
            else => return error.MalformedResponse,
        },
        else => return error.MalformedResponse,
    }
    return locations.toOwnedSlice(allocator);
}

pub fn parseHoverResponse(allocator: std.mem.Allocator, body: []const u8, expected_id: i64) !?[]u8 {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
    defer parsed.deinit();
    const object = switch (parsed.value) {
        .object => |value| value,
        else => return error.MalformedResponse,
    };
    const id_value = object.get("id") orelse return error.NotResponse;
    const id = switch (id_value) {
        .integer => |value| value,
        else => return error.MalformedResponse,
    };
    if (id != expected_id) return error.NotResponse;
    if (object.get("error") != null) return error.ServerError;
    const result = object.get("result") orelse return error.MalformedResponse;
    if (result == .null) return null;
    const result_object = switch (result) {
        .object => |value| value,
        else => return error.MalformedResponse,
    };
    const contents = result_object.get("contents") orelse return error.MalformedResponse;
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);
    try appendHoverContents(allocator, &output, contents);
    if (output.items.len == 0) {
        output.deinit(allocator);
        return null;
    }
    return try output.toOwnedSlice(allocator);
}

fn appendHoverContents(allocator: std.mem.Allocator, output: *std.ArrayList(u8), contents: std.json.Value) !void {
    switch (contents) {
        .string => |value| try output.appendSlice(allocator, value),
        .object => |object| {
            const value = switch (object.get("value") orelse return error.MalformedResponse) {
                .string => |text| text,
                else => return error.MalformedResponse,
            };
            try output.appendSlice(allocator, value);
        },
        .array => |values| for (values.items, 0..) |value, index| {
            if (index != 0) try output.appendSlice(allocator, "\n\n");
            try appendHoverContents(allocator, output, value);
        },
        else => return error.MalformedResponse,
    }
}

fn appendWireLocation(
    allocator: std.mem.Allocator,
    locations: *std.ArrayList(WireLocation),
    object: std.json.ObjectMap,
) !void {
    const uri_value = object.get("uri") orelse object.get("targetUri") orelse return error.MalformedResponse;
    const uri = switch (uri_value) {
        .string => |value| value,
        else => return error.MalformedResponse,
    };
    const range_value = object.get("range") orelse object.get("targetSelectionRange") orelse object.get("targetRange") orelse
        return error.MalformedResponse;
    const range = switch (range_value) {
        .object => |value| value,
        else => return error.MalformedResponse,
    };
    const start = try parsePosition(range.get("start") orelse return error.MalformedResponse);
    const end = try parsePosition(range.get("end") orelse return error.MalformedResponse);
    const owned_uri = try allocator.dupe(u8, uri);
    errdefer allocator.free(owned_uri);
    try locations.append(allocator, .{ .uri = owned_uri, .start = start, .end = end });
}

fn parsePosition(value: std.json.Value) !lsp.Position {
    const object = switch (value) {
        .object => |item| item,
        else => return error.MalformedResponse,
    };
    const line_value = object.get("line") orelse return error.MalformedResponse;
    const character_value = object.get("character") orelse return error.MalformedResponse;
    const line = switch (line_value) {
        .integer => |item| item,
        else => return error.MalformedResponse,
    };
    const character = switch (character_value) {
        .integer => |item| item,
        else => return error.MalformedResponse,
    };
    if (line < 0 or character < 0 or line > std.math.maxInt(u32) or character > std.math.maxInt(u32))
        return error.MalformedResponse;
    return .{ .line = @intCast(line), .character = @intCast(character) };
}

test "definition responses accept Location and LocationLink variants" {
    const body =
        \\{"jsonrpc":"2.0","id":2,"result":[
        \\ {"uri":"file:///repo/a.zig","range":{"start":{"line":1,"character":2},"end":{"line":1,"character":3}}},
        \\ {"targetUri":"file:///repo/b.zig","targetSelectionRange":{"start":{"line":4,"character":5},"end":{"line":4,"character":6}}}
        \\]}
    ;
    const locations = try parseDefinitionResponse(std.testing.allocator, body, 2);
    defer {
        for (locations) |*location| location.deinit(std.testing.allocator);
        std.testing.allocator.free(locations);
    }
    try std.testing.expectEqual(@as(usize, 2), locations.len);
    try std.testing.expectEqualStrings("file:///repo/b.zig", locations[1].uri);
    try std.testing.expectEqual(lsp.Position{ .line = 4, .character = 5 }, locations[1].start);
}

test "hover responses accept markup marked strings arrays and null" {
    const markdown = try parseHoverResponse(std.testing.allocator, "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"contents\":{\"kind\":\"markdown\",\"value\":\"**const** value\"}}}", 2);
    defer std.testing.allocator.free(markdown.?);
    try std.testing.expectEqualStrings("**const** value", markdown.?);

    const marked = try parseHoverResponse(std.testing.allocator, "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"contents\":[\"type\",{\"language\":\"zig\",\"value\":\"const x: u8\"}]}}", 2);
    defer std.testing.allocator.free(marked.?);
    try std.testing.expectEqualStrings("type\n\nconst x: u8", marked.?);
    try std.testing.expect((try parseHoverResponse(std.testing.allocator, "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":null}", 2)) == null);
}

test "hover responses reject malformed and mismatched output" {
    try std.testing.expectError(error.NotResponse, parseHoverResponse(std.testing.allocator, "{\"id\":3,\"result\":null}", 2));
    try std.testing.expectError(error.MalformedResponse, parseHoverResponse(std.testing.allocator, "{\"id\":2,\"result\":{\"contents\":9}}", 2));
}

test "definition responses reject malformed and mismatched output" {
    try std.testing.expectError(error.NotResponse, parseDefinitionResponse(std.testing.allocator, "{\"jsonrpc\":\"2.0\",\"id\":3,\"result\":null}", 2));
    try std.testing.expectError(error.MalformedResponse, parseDefinitionResponse(std.testing.allocator, "{\"jsonrpc\":\"2.0\",\"id\":2,\"result\":{\"uri\":\"http://bad\"}}", 2));
}

test "streaming reader consumes delimiters between consecutive ZLS frames" {
    const transcript =
        "Content-Length: 2\r\n\r\n{}" ++
        "Content-Length: 4\r\n\r\nnull";
    var reader = std.Io.Reader.fixed(transcript);
    const first = try readFrame(std.testing.allocator, &reader);
    defer std.testing.allocator.free(first);
    try std.testing.expectEqualStrings("{}", first);
    const second = try readFrame(std.testing.allocator, &reader);
    defer std.testing.allocator.free(second);
    try std.testing.expectEqualStrings("null", second);
}

test "file URI encoding preserves separators and escapes unsafe bytes" {
    const uri = try fileUri(std.testing.allocator, "/tmp/a repo/#main.zig");
    defer std.testing.allocator.free(uri);
    try std.testing.expectEqualStrings("file:///tmp/a%20repo/%23main.zig", uri);
    const path = try pathFromFileUri(std.testing.allocator, uri);
    defer std.testing.allocator.free(path);
    try std.testing.expectEqualStrings("/tmp/a repo/#main.zig", path);
    try std.testing.expectError(error.UnsupportedScheme, pathFromFileUri(std.testing.allocator, "https://example.test/a.zig"));
    try std.testing.expectError(error.InvalidUri, pathFromFileUri(std.testing.allocator, "file:///tmp/a%2Fb.zig"));
}
