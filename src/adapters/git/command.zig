//! Read-only git invocation. Every git call in fiew goes through `run`, which
//! shells out to the installed `git` executable with a fixed safety preamble:
//! no pager, no shell, no hooks, no external diff drivers, and no text
//! converters. Only non-mutating subcommands are ever passed in.

const std = @import("std");

/// Upper bound on captured output per stream, so a pathological repository
/// cannot exhaust memory.
pub const output_limit: u64 = 64 << 20;
pub const timeout: std.Io.Clock.Duration = .{ .raw = .fromSeconds(10), .clock = .real };

pub const Error = error{
    /// `git` could not be found or launched.
    GitUnavailable,
    /// git produced more output than `output_limit`.
    OutputTooLarge,
    /// git exited unsuccessfully.
    CommandFailed,
    /// git was killed by a signal rather than exiting.
    Terminated,
    /// git exceeded the bounded invocation deadline.
    TimedOut,
} || std.mem.Allocator.Error;

/// The captured result of one git invocation. Owns its buffers.
pub const Output = struct {
    allocator: std.mem.Allocator,
    stdout: []u8,
    stderr: []u8,
    /// Process exit code, or null if git was signaled.
    exit_code: ?u8,

    pub fn deinit(self: *Output) void {
        self.allocator.free(self.stdout);
        self.allocator.free(self.stderr);
        self.* = undefined;
    }

    pub fn succeeded(self: *const Output) bool {
        return self.exit_code == 0;
    }
};

/// Flags applied to every invocation. `--no-pager` prevents any pager, and
/// `core.pager=cat` is a belt-and-suspenders fallback; `core.quotepath=false`
/// keeps non-ASCII paths readable as UTF-8.
const preamble = [_][]const u8{
    "git",
    "--no-pager",
    "-c",
    "core.pager=cat",
    "-c",
    "core.quotepath=false",
};

/// Run `git args...` inside `repo_dir` and capture its output. `args` must be a
/// non-mutating subcommand (status, diff, rev-parse, ls-files, cat-file, ...).
pub fn run(
    allocator: std.mem.Allocator,
    io: std.Io,
    repo_dir: std.Io.Dir,
    args: []const []const u8,
) Error!Output {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);
    try argv.appendSlice(allocator, &preamble);
    try argv.appendSlice(allocator, args);

    const result = std.process.run(allocator, io, .{
        .argv = argv.items,
        .cwd = .{ .dir = repo_dir },
        .stdout_limit = .limited64(output_limit),
        .stderr_limit = .limited64(output_limit),
        .timeout = .{ .duration = timeout },
    }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.StreamTooLong => return error.OutputTooLarge,
        error.Timeout => return error.TimedOut,
        error.FileNotFound => return error.GitUnavailable,
        else => return error.GitUnavailable,
    };

    return .{
        .allocator = allocator,
        .stdout = result.stdout,
        .stderr = result.stderr,
        .exit_code = switch (result.term) {
            .exited => |code| code,
            else => null,
        },
    };
}

/// Run one command and reject every unsuccessful termination explicitly.
pub fn runChecked(
    allocator: std.mem.Allocator,
    io: std.Io,
    repo_dir: std.Io.Dir,
    args: []const []const u8,
) Error!Output {
    var output = try run(allocator, io, repo_dir, args);
    errdefer output.deinit();
    if (output.exit_code == null) return error.Terminated;
    if (!output.succeeded()) return error.CommandFailed;
    return output;
}

const build_options = @import("build_options");

test "checked invocation rejects a nonzero Git exit" {
    if (!build_options.git_integration) return error.SkipZigTest;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try std.testing.expectError(
        error.CommandFailed,
        runChecked(std.testing.allocator, std.testing.io, tmp.dir, &.{ "rev-parse", "--verify", "definitely-missing" }),
    );
}
