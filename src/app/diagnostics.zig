//! Bounded, redacting diagnostic history.
//!
//! fiew records why capabilities degraded without leaking protected content.
//! Protected detail (source bytes, review-note bodies, environment values, and
//! protocol payloads) is redacted by default; verbatim inclusion is opt-in for
//! explicitly enabled local logging.

const std = @import("std");

/// Origin of a diagnostic event. Kept as a small closed set so history stays
/// bounded and free of caller-supplied strings.
pub const Category = enum {
    state_store,
    repository,
    document,
    git,
    lsp,
    mermaid,
    terminal,
    general,
};

/// Number of retained events. Older events are overwritten once full.
pub const capacity: usize = 128;
/// Upper bound on a stored safe code label.
pub const code_capacity: usize = 64;
/// Upper bound on a stored (possibly redacted) detail line.
pub const detail_capacity: usize = 192;

pub const Entry = struct {
    category: Category,
    code_buffer: [code_capacity]u8 = undefined,
    code_length: usize = 0,
    detail_buffer: [detail_capacity]u8 = undefined,
    detail_length: usize = 0,

    pub fn code(self: *const Entry) []const u8 {
        return self.code_buffer[0..self.code_length];
    }

    pub fn detail(self: *const Entry) []const u8 {
        return self.detail_buffer[0..self.detail_length];
    }
};

/// Marker written in place of redacted protected content.
pub const redaction_marker = "[redacted]";

/// Fixed-capacity ring of diagnostic events. Recording never allocates and is
/// safe to call from worker threads.
pub const Diagnostics = struct {
    entries: [capacity]Entry = undefined,
    start: usize = 0,
    length: usize = 0,
    /// When false (the default), protected detail is redacted. Enabling it is a
    /// deliberate local-logging opt-in.
    include_protected: bool = false,
    /// Guards the ring so recording is safe from worker threads without needing
    /// an `Io` handle at every call site.
    spin: std.atomic.Value(bool) = .init(false),

    pub const init: Diagnostics = .{};

    fn lock(self: *Diagnostics) void {
        while (self.spin.cmpxchgWeak(false, true, .acquire, .monotonic) != null) {
            std.atomic.spinLoopHint();
        }
    }

    fn unlock(self: *Diagnostics) void {
        self.spin.store(false, .release);
    }

    /// Record an event. `code` is a short, non-protected label (typically a
    /// static string literal). `protected` is optional content that may contain
    /// protected data; it is redacted unless `include_protected` is set.
    pub fn record(
        self: *Diagnostics,
        category: Category,
        code: []const u8,
        protected: ?[]const u8,
    ) void {
        self.lock();
        defer self.unlock();

        const slot = (self.start + self.length) % capacity;
        if (self.length == capacity) {
            self.start = (self.start + 1) % capacity;
        } else {
            self.length += 1;
        }

        var entry: Entry = .{ .category = category };
        entry.code_length = copyBounded(&entry.code_buffer, code);
        if (protected) |content| {
            entry.detail_length = if (self.include_protected)
                copyBounded(&entry.detail_buffer, content)
            else
                copyBounded(&entry.detail_buffer, redaction_marker);
        }
        self.entries[slot] = entry;
    }

    /// Number of retained events.
    pub fn count(self: *Diagnostics) usize {
        self.lock();
        defer self.unlock();
        return self.length;
    }

    /// Copy retained events, oldest first, into `out`. Returns the copied slice.
    pub fn snapshot(self: *Diagnostics, out: *[capacity]Entry) []Entry {
        self.lock();
        defer self.unlock();
        var index: usize = 0;
        while (index < self.length) : (index += 1) {
            out[index] = self.entries[(self.start + index) % capacity];
        }
        return out[0..self.length];
    }

    fn copyBounded(buffer: []u8, text: []const u8) usize {
        const length = @min(buffer.len, text.len);
        @memcpy(buffer[0..length], text[0..length]);
        return length;
    }
};

test "protected detail is redacted by default" {
    var diagnostics: Diagnostics = .init;
    diagnostics.record(.state_store, "primary_corrupt", "/Users/someone/secret/repo/notes.json");

    var buffer: [capacity]Entry = undefined;
    const entries = diagnostics.snapshot(&buffer);
    try std.testing.expectEqual(@as(usize, 1), entries.len);
    try std.testing.expectEqualStrings("primary_corrupt", entries[0].code());
    try std.testing.expectEqualStrings(redaction_marker, entries[0].detail());
    try std.testing.expect(std.mem.indexOf(u8, entries[0].detail(), "secret") == null);
}

test "protected detail is retained only when explicitly opted in" {
    var diagnostics: Diagnostics = .init;
    diagnostics.include_protected = true;
    diagnostics.record(.git, "spawn_failed", "/private/path");

    var buffer: [capacity]Entry = undefined;
    const entries = diagnostics.snapshot(&buffer);
    try std.testing.expectEqualStrings("/private/path", entries[0].detail());
}

test "history is bounded and overwrites oldest events" {
    var diagnostics: Diagnostics = .init;
    var index: usize = 0;
    while (index < capacity + 10) : (index += 1) {
        var code_buffer: [16]u8 = undefined;
        const code = std.fmt.bufPrint(&code_buffer, "event_{d}", .{index}) catch unreachable;
        diagnostics.record(.general, code, null);
    }
    try std.testing.expectEqual(capacity, diagnostics.count());

    var buffer: [capacity]Entry = undefined;
    const entries = diagnostics.snapshot(&buffer);
    try std.testing.expectEqualStrings("event_10", entries[0].code());
    try std.testing.expectEqualStrings("event_137", entries[capacity - 1].code());
}

test "oversized code and detail are truncated to their bounds" {
    var diagnostics: Diagnostics = .init;
    diagnostics.include_protected = true;
    const long = "x" ** (detail_capacity * 2);
    diagnostics.record(.general, long, long);

    var buffer: [capacity]Entry = undefined;
    const entries = diagnostics.snapshot(&buffer);
    try std.testing.expectEqual(code_capacity, entries[0].code().len);
    try std.testing.expectEqual(detail_capacity, entries[0].detail().len);
}
