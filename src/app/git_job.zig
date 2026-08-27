//! Generation-gated completion values for asynchronous Git snapshot loading.

const std = @import("std");
const git = @import("../model/git.zig");
const repository = @import("../adapters/git/repository.zig");

pub const Failure = enum {
    git_unavailable,
    command_failed,
    output_too_large,
    terminated,
    timed_out,
    repository_changed,
    untracked_read_failed,
    out_of_memory,
    unknown,

    pub fn message(self: Failure) []const u8 {
        return switch (self) {
            .git_unavailable => "Git is unavailable",
            .command_failed => "Git command failed",
            .output_too_large => "Git output limit exceeded",
            .terminated => "Git command was terminated",
            .timed_out => "Git command timed out",
            .repository_changed => "repository changed during refresh",
            .untracked_read_failed => "untracked file changed or could not be read",
            .out_of_memory => "not enough memory for Git snapshot",
            .unknown => "Git refresh failed",
        };
    }
};

pub fn failureFromError(err: anyerror) Failure {
    return switch (err) {
        error.GitUnavailable => .git_unavailable,
        error.CommandFailed => .command_failed,
        error.OutputTooLarge => .output_too_large,
        error.Terminated => .terminated,
        error.TimedOut => .timed_out,
        error.RepositoryChanged => .repository_changed,
        error.UntrackedReadFailed => .untracked_read_failed,
        error.OutOfMemory => .out_of_memory,
        else => .unknown,
    };
}

pub const Result = union(enum) {
    success: repository.Snapshot,
    failure: Failure,

    pub fn deinit(self: *Result) void {
        switch (self.*) {
            .success => |*snapshot| snapshot.changeset.deinit(),
            .failure => {},
        }
        self.* = undefined;
    }
};

pub const Completion = struct {
    generation: u64,
    result: Result,

    pub fn deinit(self: *Completion) void {
        self.result.deinit();
    }
};

/// Returns a successful snapshot only when it belongs to the latest request.
pub fn accept(completion: *Completion, expected_generation: u64) ?repository.Snapshot {
    if (completion.generation != expected_generation) return null;
    return switch (completion.result) {
        .success => |snapshot| blk: {
            completion.result = .{ .failure = .unknown };
            break :blk snapshot;
        },
        .failure => null,
    };
}

fn emptySet() !git.ChangeSet {
    return .{
        .allocator = std.testing.allocator,
        .changes = try std.testing.allocator.alloc(git.Change, 0),
        .diffs = try std.testing.allocator.alloc(git.FileDiff, 0),
    };
}

test "obsolete Git completions cannot publish" {
    var completion: Completion = .{
        .generation = 1,
        .result = .{ .success = .{ .changeset = try emptySet(), .fingerprint = @splat(0) } },
    };
    defer completion.deinit();
    try std.testing.expect(accept(&completion, 2) == null);
}
