//! Portable graceful-shutdown signal handling for the interactive terminal.
//!
//! The signal handler records one atomic request and writes one byte to a pipe.
//! A small watcher thread converts that async-signal-safe write into a normal
//! terminal-loop event, allowing cleanup to use the ordinary defer path.

const std = @import("std");
const builtin = @import("builtin");

pub const ShutdownSignals = struct {
    const NotifyFn = *const fn (context: *anyopaque, exit_code: u8) void;

    previous_int: std.posix.Sigaction,
    previous_term: std.posix.Sigaction,
    pipe: [2]std.posix.fd_t,
    watcher: ?std.Thread = null,

    var pending: std.atomic.Value(u8) = .init(0);
    var signal_write_fd: std.posix.fd_t = -1;
    var notify_context: ?*anyopaque = null;
    var notify_fn: ?NotifyFn = null;
    var watch_read_fd: std.posix.fd_t = -1;

    pub fn install() !ShutdownSignals {
        comptime std.debug.assert(builtin.os.tag == .macos or builtin.os.tag == .linux);
        var pipe: [2]std.posix.fd_t = undefined;
        if (std.c.pipe(&pipe) != 0) return error.SignalPipeUnavailable;
        errdefer {
            _ = std.c.close(pipe[0]);
            _ = std.c.close(pipe[1]);
        }
        // Internal wakeup descriptors must never leak into Git, Mermaid, or
        // ZLS children.
        if (std.c.fcntl(pipe[0], std.c.F.SETFD, @as(c_int, std.c.FD_CLOEXEC)) < 0 or
            std.c.fcntl(pipe[1], std.c.F.SETFD, @as(c_int, std.c.FD_CLOEXEC)) < 0)
            return error.SignalPipeUnavailable;

        pending.store(0, .release);
        signal_write_fd = pipe[1];
        const action: std.posix.Sigaction = .{
            .handler = .{ .handler = handle },
            .mask = emptySignalSet(),
            .flags = 0,
        };
        var result: ShutdownSignals = .{
            .previous_int = undefined,
            .previous_term = undefined,
            .pipe = pipe,
        };
        std.posix.sigaction(std.posix.SIG.INT, &action, &result.previous_int);
        std.posix.sigaction(std.posix.SIG.TERM, &action, &result.previous_term);
        return result;
    }

    pub fn deinit(self: *ShutdownSignals) void {
        self.disarm();
        std.posix.sigaction(std.posix.SIG.INT, &self.previous_int, null);
        std.posix.sigaction(std.posix.SIG.TERM, &self.previous_term, null);
        signal_write_fd = -1;
        _ = std.c.close(self.pipe[0]);
        _ = std.c.close(self.pipe[1]);
        pending.store(0, .release);
        self.* = undefined;
    }

    /// Arm a normal thread to wake the event loop after the loop is ready.
    pub fn arm(self: *ShutdownSignals, context: *anyopaque, callback: NotifyFn) !void {
        std.debug.assert(self.watcher == null);
        notify_context = context;
        notify_fn = callback;
        watch_read_fd = self.pipe[0];
        self.watcher = try std.Thread.spawn(.{}, watch, .{});
    }

    pub fn disarm(self: *ShutdownSignals) void {
        const watcher = self.watcher orelse return;
        var stop = [_]u8{0};
        _ = std.c.write(self.pipe[1], &stop, stop.len);
        watcher.join();
        self.watcher = null;
        notify_fn = null;
        notify_context = null;
        watch_read_fd = -1;
    }

    /// Returns the conventional process exit code for the first pending
    /// shutdown signal, or null when no signal has been received.
    pub fn requestedExitCode() ?u8 {
        const signal = pending.load(.acquire);
        return if (signal == 0) null else 128 + signal;
    }

    fn handle(signal: std.posix.SIG) callconv(.c) void {
        const value: u8 = @intCast(@intFromEnum(signal));
        if (pending.cmpxchgStrong(0, value, .release, .monotonic) == null and signal_write_fd >= 0) {
            var byte = [_]u8{value};
            _ = std.c.write(signal_write_fd, &byte, byte.len);
        }
    }

    fn watch() void {
        var byte: [1]u8 = undefined;
        while (true) {
            const result = std.c.read(watch_read_fd, &byte, byte.len);
            if (result == 1) {
                if (byte[0] == 0) return;
                if (notify_fn) |notify| if (notify_context) |context|
                    notify(context, 128 + byte[0]);
                // Also wake the terminal's established resize path. This is a
                // fallback for event-loop backends whose condition wait is not
                // signaled by a foreign OS thread.
                std.posix.raise(std.posix.SIG.WINCH) catch {};
                return;
            }
            // A process-directed signal may be delivered to this watcher and
            // interrupt read after the handler writes the wake byte.
            if (result < 0 and std.posix.errno(result) == .INTR) continue;
            return;
        }
    }

    fn emptySignalSet() std.posix.sigset_t {
        return switch (builtin.os.tag) {
            .macos => 0,
            else => std.posix.sigemptyset(),
        };
    }
};

test "installed SIGINT and SIGTERM handlers request graceful exit codes" {
    var signals = try ShutdownSignals.install();
    defer signals.deinit();
    var notified: std.atomic.Value(u8) = .init(0);
    const notify = struct {
        fn call(context: *anyopaque, code: u8) void {
            const value: *std.atomic.Value(u8) = @ptrCast(@alignCast(context));
            value.store(code, .release);
        }
    }.call;
    try signals.arm(&notified, notify);

    try std.posix.raise(std.posix.SIG.INT);
    signals.disarm();
    try std.testing.expectEqual(@as(u8, 130), notified.load(.acquire));
    try std.testing.expectEqual(@as(?u8, 130), ShutdownSignals.requestedExitCode());

    // The first request wins while cleanup is in progress.
    ShutdownSignals.handle(std.posix.SIG.TERM);
    try std.testing.expectEqual(@as(?u8, 130), ShutdownSignals.requestedExitCode());

    ShutdownSignals.pending.store(0, .release);
    try std.posix.raise(std.posix.SIG.TERM);
    try std.testing.expectEqual(@as(?u8, 143), ShutdownSignals.requestedExitCode());
}
