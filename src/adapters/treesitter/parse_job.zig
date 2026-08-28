//! Parse-job coordination: the off-render-loop analysis step and the rules that
//! keep its results fresh. The analysis itself runs on a worker (see main.zig);
//! this module holds the pure, deterministic logic — request/response identity,
//! stale-result rejection, and the timing policy — so it is fully testable
//! without threads or a real clock.

const std = @import("std");
const zig_syntax = @import("zig_syntax.zig");
const markdown_syntax = @import("markdown_syntax.zig");
const syntax = @import("../../model/syntax.zig");

/// Show a pending indicator once a parse has run this long without finishing.
pub const pending_after_ms: u64 = 100;
/// Cancel a parse that has run at least this long.
pub const deadline_ms: u64 = 1000;

pub fn shouldShowPending(elapsed_ms: u64) bool {
    return elapsed_ms >= pending_after_ms and elapsed_ms < deadline_ms;
}

pub fn expired(elapsed_ms: u64) bool {
    return elapsed_ms >= deadline_ms;
}

/// One unit of analysis work bound to a snapshot generation.
pub const Request = struct {
    generation: u64,
    /// Borrowed for the duration of `run`; the worker owns a copy in practice.
    source: []const u8,
};

/// The outcome of a parse job, carrying the generation it was computed for so
/// the owner can reject stale results.
pub const Completion = struct {
    generation: u64,
    /// Null when the input was oversized, parsing was cancelled, or analysis
    /// failed — in every such case the caller keeps the plain-text fallback.
    data: ?syntax.ParseData,

    pub fn deinit(self: *Completion) void {
        if (self.data) |*data| data.deinit();
        self.* = undefined;
    }
};

/// Run analysis for `request` on the calling (worker) thread. Never invoked
/// from the render path. Honors cancellation and the size ceiling via the
/// adapter, always returning a Completion tagged with the request generation.
pub fn run(
    engine: *zig_syntax.Engine,
    allocator: std.mem.Allocator,
    request: Request,
    cancel: ?*zig_syntax.CancelContext,
) Completion {
    var tree = engine.parse(request.source, cancel) orelse
        return .{ .generation = request.generation, .data = null };
    defer tree.deinit();
    const data = engine.analyze(allocator, &tree) catch
        return .{ .generation = request.generation, .data = null };
    return .{ .generation = request.generation, .data = data };
}

/// Markdown has a block/inline/injection pipeline but shares the same job
/// identity and fallback contract as Zig.
pub fn runMarkdown(
    engine: *markdown_syntax.Engine,
    allocator: std.mem.Allocator,
    request: Request,
    cancel: ?*markdown_syntax.CancelContext,
) Completion {
    return .{
        .generation = request.generation,
        .data = engine.analyze(allocator, request.source, cancel),
    };
}

/// Tracks the generation the UI currently cares about and rejects any
/// completion that does not match it, so a slow parse for a superseded snapshot
/// can never alter the current view.
pub const Coordinator = struct {
    current: u64 = 0,

    /// Record that a parse has been requested for `generation`.
    pub fn begin(self: *Coordinator, generation: u64) void {
        self.current = generation;
    }

    /// Take ownership of a fresh completion's data, or reject and free a stale
    /// one. Returns analysis data only when it matches the current generation
    /// and parsing produced a result.
    pub fn accept(self: *Coordinator, completion: *Completion) ?syntax.ParseData {
        // In both branches the completion is left holding no data, so the caller
        // may still safely call `completion.deinit()`.
        if (completion.generation != self.current) {
            if (completion.data) |*data| data.deinit();
            completion.data = null;
            return null;
        }
        const data = completion.data;
        completion.data = null;
        return data;
    }
};

// --- Tests ---------------------------------------------------------------

const testing = std.testing;

const sample = "pub fn main() void {\n    const x = 1;\n    _ = x;\n}\n";

test "timing policy matches the 100 ms and one-second boundaries" {
    try testing.expect(!shouldShowPending(50));
    try testing.expect(shouldShowPending(100));
    try testing.expect(shouldShowPending(999));
    try testing.expect(!shouldShowPending(1000));
    try testing.expect(!expired(999));
    try testing.expect(expired(1000));
}

test "run produces analysis tagged with its generation" {
    var engine = try zig_syntax.Engine.init(testing.allocator);
    defer engine.deinit();
    var completion = run(&engine, testing.allocator, .{ .generation = 7, .source = sample }, null);
    defer completion.deinit();
    try testing.expectEqual(@as(u64, 7), completion.generation);
    try testing.expect(completion.data != null);
    try testing.expect(completion.data.?.folds.len >= 1);
}

test "Markdown run produces analysis with the shared generation contract" {
    var engine = try markdown_syntax.Engine.init(testing.allocator);
    defer engine.deinit();
    const source = "# Heading\n\n```zig\nconst n = 1;\n```\n";
    var completion = runMarkdown(&engine, testing.allocator, .{ .generation = 8, .source = source }, null);
    defer completion.deinit();
    try testing.expectEqual(@as(u64, 8), completion.generation);
    try testing.expect(completion.data != null);
    try testing.expect(completion.data.?.folds.len >= 2);
}

test "run returns no data for oversized input" {
    var engine = try zig_syntax.Engine.init(testing.allocator);
    defer engine.deinit();
    const big = try testing.allocator.alloc(u8, zig_syntax.max_parse_bytes + 1);
    defer testing.allocator.free(big);
    @memset(big, ' ');
    var completion = run(&engine, testing.allocator, .{ .generation = 1, .source = big }, null);
    defer completion.deinit();
    try testing.expect(completion.data == null);
}

test "coordinator installs current results and rejects stale ones" {
    var engine = try zig_syntax.Engine.init(testing.allocator);
    defer engine.deinit();
    var coordinator: Coordinator = .{};

    // A completion for the current generation is accepted; caller owns the data.
    coordinator.begin(3);
    var fresh = run(&engine, testing.allocator, .{ .generation = 3, .source = sample }, null);
    var accepted = coordinator.accept(&fresh);
    try testing.expect(accepted != null);
    accepted.?.deinit();
    fresh.deinit();

    // A completion for a superseded generation is rejected and freed here (the
    // testing allocator would report a leak otherwise).
    coordinator.begin(5);
    var stale = run(&engine, testing.allocator, .{ .generation = 4, .source = sample }, null);
    try testing.expect(coordinator.accept(&stale) == null);
    stale.deinit();
}
