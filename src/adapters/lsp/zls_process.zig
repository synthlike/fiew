//! Direct, bounded ZLS executable validation and long-lived JSON-RPC process.

const std = @import("std");
const lsp = @import("../../model/lsp.zig");
const json_rpc = @import("json_rpc.zig");
const zls_protocol = @import("zls_protocol.zig");

pub const output_limit: u64 = 64 << 10;
pub const version_timeout: std.Io.Clock.Duration = .{ .raw = .fromSeconds(2), .clock = .real };

pub const ProbeError = error{ NotInstalled, Incompatible, VersionFailed, OutputTooLarge, TimedOut } || std.mem.Allocator.Error;

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
}
