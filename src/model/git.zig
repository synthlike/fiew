//! fiew-owned model of the current Git working-tree review. No git wire formats
//! appear here; adapters translate git output into these values.

const std = @import("std");

/// The three change groups fiew reviews. A path may appear in more than one.
pub const Group = enum {
    /// `HEAD` to index.
    staged,
    /// Index to working tree.
    unstaged,
    /// Whole untracked file added.
    untracked,

    pub fn title(self: Group) []const u8 {
        return switch (self) {
            .staged => "Staged",
            .unstaged => "Unstaged",
            .untracked => "Untracked",
        };
    }
};

/// What happened to a path.
pub const ChangeKind = enum {
    added,
    modified,
    deleted,
    renamed,
    copied,
    type_changed,
    mode_changed,
    unmerged,

    pub fn label(self: ChangeKind) []const u8 {
        return switch (self) {
            .added => "added",
            .modified => "modified",
            .deleted => "deleted",
            .renamed => "renamed",
            .copied => "copied",
            .type_changed => "type changed",
            .mode_changed => "mode changed",
            .unmerged => "unmerged",
        };
    }
};

/// Whether a change carries a textual diff or only metadata.
pub const ContentKind = enum {
    text,
    binary,
    submodule,

    /// Binary, submodule (and mode-only) changes present metadata without hunks.
    pub fn hasTextDiff(self: ContentKind) bool {
        return self == .text;
    }
};

/// The git file mode for a gitlink (submodule) entry.
pub const submodule_mode: u32 = 0o160000;

/// One changed path within a group.
pub const Change = struct {
    group: Group,
    kind: ChangeKind,
    content: ContentKind,
    /// Current (new-side) repository-relative path, or the only path.
    path: []const u8,
    /// Previous path for renames and copies.
    old_path: ?[]const u8 = null,
    /// Rename/copy similarity score (0–100).
    similarity: ?u8 = null,
    old_mode: u32 = 0,
    new_mode: u32 = 0,

    /// Whether this entry shows a unified textual diff.
    pub fn showsDiff(self: Change) bool {
        return self.content.hasTextDiff() and self.kind != .mode_changed;
    }
};

/// An owned list of changes for one or more groups.
pub const ChangeList = struct {
    allocator: std.mem.Allocator,
    items: []Change,

    pub const empty: ChangeList = .{ .allocator = undefined, .items = &.{} };

    pub fn deinit(self: *ChangeList) void {
        for (self.items) |change| {
            self.allocator.free(change.path);
            if (change.old_path) |old| self.allocator.free(old);
        }
        self.allocator.free(self.items);
        self.* = undefined;
    }

    pub fn count(self: ChangeList, group: Group) usize {
        var total: usize = 0;
        for (self.items) |change| {
            if (change.group == group) total += 1;
        }
        return total;
    }
};

/// One line inside a unified diff hunk.
pub const LineKind = enum { context, addition, deletion };

pub const DiffLine = struct {
    kind: LineKind,
    /// One-based line number on the old side, when present.
    old_line: ?usize,
    /// One-based line number on the new side, when present.
    new_line: ?usize,
    /// Byte range of the line's text (without the +/-/space marker or newline)
    /// inside the owning `FileDiff.text`.
    text: Range,
};

pub const Range = struct { start: usize, end: usize };

/// A contiguous hunk: its `@@` header plus the lines it covers.
pub const Hunk = struct {
    old_start: usize,
    old_count: usize,
    new_start: usize,
    new_count: usize,
    /// Byte range of the header text (the section heading after `@@`).
    header: Range,
    /// Indices into `FileDiff.lines`.
    first_line: usize,
    line_count: usize,
};

/// The parsed unified diff for one changed file. Owns its text and arrays.
pub const FileDiff = struct {
    allocator: std.mem.Allocator,
    /// The concatenated line texts the ranges point into.
    text: []const u8,
    hunks: []const Hunk,
    lines: []const DiffLine,

    pub const empty_text: []const u8 = "";

    pub fn deinit(self: *FileDiff) void {
        self.allocator.free(self.text);
        self.allocator.free(self.hunks);
        self.allocator.free(self.lines);
        self.* = undefined;
    }

    pub fn changedLineCount(self: FileDiff) usize {
        var total: usize = 0;
        for (self.lines) |line| {
            if (line.kind != .context) total += 1;
        }
        return total;
    }
};

/// A complete snapshot of the working-tree review: every change across the
/// three groups and, for text changes, its parsed diff. `changes.items[i]`
/// corresponds to `diffs[i]`; metadata-only entries carry an empty diff.
pub const ChangeSet = struct {
    allocator: std.mem.Allocator,
    changes: []Change,
    diffs: []FileDiff,

    pub const empty: ChangeSet = .{ .allocator = undefined, .changes = &.{}, .diffs = &.{} };

    pub fn deinit(self: *ChangeSet) void {
        for (self.changes) |change| {
            self.allocator.free(change.path);
            if (change.old_path) |old| self.allocator.free(old);
        }
        self.allocator.free(self.changes);
        for (self.diffs) |*diff| diff.deinit();
        self.allocator.free(self.diffs);
        self.* = undefined;
    }

    pub fn isEmpty(self: ChangeSet) bool {
        return self.changes.len == 0;
    }

    pub fn groupCount(self: ChangeSet, group: Group) usize {
        var total: usize = 0;
        for (self.changes) |change| {
            if (change.group == group) total += 1;
        }
        return total;
    }
};
