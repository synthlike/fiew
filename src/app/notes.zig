//! In-memory review-note state: the notes loaded from `.reviews/` plus the
//! session's own review, with create/edit/resolve/delete operations. It owns a
//! deep copy of every note so ownership stays simple; the terminal adapter
//! flushes dirty files and deletes emptied ones through the store.

const std = @import("std");
const review = @import("../model/review.zig");
const git = @import("../model/git.zig");
const store = @import("../adapters/storage/review_store.zig");

/// Addresses a note by its file and position.
pub const NoteRef = struct { file: usize, note: usize };

/// Metadata needed to open the session's review file on the first note.
pub const SessionInit = struct {
    filename: []const u8,
    base_ref: []const u8,
    base_sha: []const u8,
    created: []const u8,
};

const ReviewFile = struct {
    filename: []u8,
    base_ref: []u8,
    base_sha: []u8,
    created: []u8,
    notes: std.ArrayListUnmanaged(review.Note) = .empty,
    dirty: bool = false,

    fn view(self: ReviewFile) review.Review {
        return .{
            .allocator = undefined,
            .base_ref = self.base_ref,
            .base_sha = self.base_sha,
            .created = self.created,
            .notes = self.notes.items,
        };
    }
};

pub const Notes = struct {
    allocator: std.mem.Allocator,
    files: std.ArrayListUnmanaged(ReviewFile) = .empty,
    session: ?usize = null,
    /// Flat index across all notes (Review sidebar selection / `[ n` `] n`).
    selected: usize = 0,
    next_id: usize = 1,
    /// Filenames whose review became empty and should be deleted on flush.
    removed: std.ArrayListUnmanaged([]u8) = .empty,

    /// Build notes state by deep-copying everything the store loaded. The caller
    /// still owns and must deinit `loaded`.
    pub fn fromLoaded(allocator: std.mem.Allocator, loaded: store.Loaded) !Notes {
        var self: Notes = .{ .allocator = allocator };
        errdefer self.deinit();
        for (loaded.entries) |entry| {
            var file: ReviewFile = .{
                .filename = try allocator.dupe(u8, entry.filename),
                .base_ref = try allocator.dupe(u8, entry.review.base_ref),
                .base_sha = try allocator.dupe(u8, entry.review.base_sha),
                .created = try allocator.dupe(u8, entry.review.created),
            };
            for (entry.review.notes) |note| {
                try file.notes.append(allocator, try dupeNote(allocator, note));
            }
            try self.files.append(allocator, file);
        }
        return self;
    }

    pub fn deinit(self: *Notes) void {
        for (self.files.items) |*file| freeFile(self.allocator, file);
        self.files.deinit(self.allocator);
        for (self.removed.items) |name| self.allocator.free(name);
        self.removed.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn total(self: Notes) usize {
        var count: usize = 0;
        for (self.files.items) |file| count += file.notes.items.len;
        return count;
    }

    /// Route new notes into an already-loaded review file named `filename`.
    pub fn useSession(self: *Notes, filename: []const u8) void {
        for (self.files.items, 0..) |file, index| {
            if (std.mem.eql(u8, file.filename, filename)) {
                self.session = index;
                return;
            }
        }
    }

    /// Count of Open notes in the review file named `filename`.
    pub fn openCountInFile(self: Notes, filename: []const u8) usize {
        var count: usize = 0;
        for (self.files.items) |file| {
            if (!std.mem.eql(u8, file.filename, filename)) continue;
            for (file.notes.items) |note| {
                if (note.status == .open) count += 1;
            }
        }
        return count;
    }

    pub fn refAt(self: Notes, flat_index: usize) ?NoteRef {
        var remaining = flat_index;
        for (self.files.items, 0..) |file, file_index| {
            if (remaining < file.notes.items.len) return .{ .file = file_index, .note = remaining };
            remaining -= file.notes.items.len;
        }
        return null;
    }

    pub fn selectedRef(self: Notes) ?NoteRef {
        return self.refAt(self.selected);
    }

    pub fn noteAt(self: Notes, ref: NoteRef) *review.Note {
        return &self.files.items[ref.file].notes.items[ref.note];
    }

    /// A freshly allocated note id (`n1`, `n2`, …) unique within this state.
    pub fn nextId(self: *Notes, allocator: std.mem.Allocator) ![]u8 {
        const id = try std.fmt.allocPrint(allocator, "n{d}", .{self.next_id});
        self.next_id += 1;
        return id;
    }

    /// Append an already-owned note to the session review, creating the session
    /// file on first use. Selection moves to the new note.
    pub fn add(self: *Notes, session: SessionInit, note: review.Note) !void {
        if (self.session == null) {
            const file: ReviewFile = .{
                .filename = try self.allocator.dupe(u8, session.filename),
                .base_ref = try self.allocator.dupe(u8, session.base_ref),
                .base_sha = try self.allocator.dupe(u8, session.base_sha),
                .created = try self.allocator.dupe(u8, session.created),
            };
            try self.files.append(self.allocator, file);
            self.session = self.files.items.len - 1;
        }
        const index = self.session.?;
        try self.files.items[index].notes.append(self.allocator, note);
        self.files.items[index].dirty = true;
        self.selected = self.flatIndex(.{ .file = index, .note = self.files.items[index].notes.items.len - 1 });
    }

    /// Toggle the selected note between Open and Resolved.
    pub fn toggleResolved(self: *Notes) void {
        const ref = self.selectedRef() orelse return;
        const note = self.noteAt(ref);
        note.status = if (note.status == .resolved) .open else .resolved;
        self.files.items[ref.file].dirty = true;
    }

    /// Replace the selected note's body with an owned string.
    pub fn replaceBody(self: *Notes, new_body: []u8) void {
        const ref = self.selectedRef() orelse {
            self.allocator.free(new_body);
            return;
        };
        const note = self.noteAt(ref);
        self.allocator.free(note.body);
        note.body = new_body;
        self.files.items[ref.file].dirty = true;
    }

    /// Delete the selected note. If its file becomes empty, the file is dropped
    /// and its name recorded for removal on flush.
    pub fn deleteSelected(self: *Notes) !void {
        const ref = self.selectedRef() orelse return;
        var file = &self.files.items[ref.file];
        const removed_note = file.notes.orderedRemove(ref.note);
        freeNote(self.allocator, removed_note);
        file.dirty = true;
        if (file.notes.items.len == 0) {
            try self.removed.append(self.allocator, file.filename);
            file.filename = &.{}; // ownership moved to `removed`
            self.dropFile(ref.file);
        }
        if (self.selected >= self.total() and self.selected > 0) self.selected = self.total() -| 1;
    }

    pub fn moveSelection(self: *Notes, delta: isize) void {
        const count = self.total();
        if (count == 0) return;
        const current: isize = @intCast(self.selected);
        const last: isize = @intCast(count - 1);
        self.selected = @intCast(std.math.clamp(current + delta, 0, last));
    }

    /// Notes anchored to `path` in `group`; used to place gutter markers.
    pub fn forFile(self: Notes, path: []const u8, group: git.Group, buffer: []NoteRef) []NoteRef {
        var count: usize = 0;
        for (self.files.items, 0..) |file, file_index| {
            for (file.notes.items, 0..) |note, note_index| {
                if (note.group == group and std.mem.eql(u8, note.path, path)) {
                    if (count >= buffer.len) return buffer[0..count];
                    buffer[count] = .{ .file = file_index, .note = note_index };
                    count += 1;
                }
            }
        }
        return buffer[0..count];
    }

    /// Dirty files paired with their filename and a serializable review view, so
    /// the adapter can persist them. The caller clears `dirty` after saving.
    pub fn dirtyFiles(self: *Notes, buffer: []DirtyFile) []DirtyFile {
        var count: usize = 0;
        for (self.files.items) |file| {
            if (!file.dirty) continue;
            if (count >= buffer.len) break;
            buffer[count] = .{ .filename = file.filename, .review = file.view() };
            count += 1;
        }
        return buffer[0..count];
    }

    pub fn clearDirty(self: *Notes) void {
        for (self.files.items) |*file| file.dirty = false;
    }

    /// Filenames of reviews to delete, taking ownership out of the state.
    pub fn takeRemoved(self: *Notes) []const []u8 {
        const owned = self.removed.toOwnedSlice(self.allocator) catch &.{};
        self.removed = .empty;
        return owned;
    }

    pub const DirtyFile = struct { filename: []const u8, review: review.Review };

    fn flatIndex(self: Notes, ref: NoteRef) usize {
        var index: usize = 0;
        for (self.files.items[0..ref.file]) |file| index += file.notes.items.len;
        return index + ref.note;
    }

    fn dropFile(self: *Notes, index: usize) void {
        var file = self.files.orderedRemove(index);
        freeFile(self.allocator, &file);
        if (self.session) |current| {
            if (current == index) self.session = null else if (current > index) self.session = current - 1;
        }
    }
};

fn dupeNote(allocator: std.mem.Allocator, note: review.Note) !review.Note {
    const id = try allocator.dupe(u8, note.id);
    errdefer allocator.free(id);
    const path = try allocator.dupe(u8, note.path);
    errdefer allocator.free(path);
    const blob = if (note.blob) |value| try allocator.dupe(u8, value) else null;
    errdefer if (blob) |value| allocator.free(value);
    const excerpt = if (note.excerpt) |value| try allocator.dupe(u8, value) else null;
    errdefer if (excerpt) |value| allocator.free(value);
    const body = try allocator.dupe(u8, note.body);
    return .{
        .id = id,
        .path = path,
        .group = note.group,
        .status = note.status,
        .side = note.side,
        .start_line = note.start_line,
        .end_line = note.end_line,
        .blob = blob,
        .excerpt = excerpt,
        .body = body,
    };
}

fn freeNote(allocator: std.mem.Allocator, note: review.Note) void {
    allocator.free(note.id);
    allocator.free(note.path);
    if (note.blob) |value| allocator.free(value);
    if (note.excerpt) |value| allocator.free(value);
    allocator.free(note.body);
}

fn freeFile(allocator: std.mem.Allocator, file: *ReviewFile) void {
    for (file.notes.items) |note| freeNote(allocator, note);
    file.notes.deinit(allocator);
    allocator.free(file.filename);
    allocator.free(file.base_ref);
    allocator.free(file.base_sha);
    allocator.free(file.created);
}

// --- Tests ---------------------------------------------------------------

const testing = std.testing;

fn ownedNote(allocator: std.mem.Allocator, id: []const u8, path: []const u8, body: []const u8) !review.Note {
    return .{
        .id = try allocator.dupe(u8, id),
        .path = try allocator.dupe(u8, path),
        .group = .unstaged,
        .status = .open,
        .side = .new,
        .start_line = 1,
        .end_line = 1,
        .blob = null,
        .excerpt = try allocator.dupe(u8, "+x"),
        .body = try allocator.dupe(u8, body),
    };
}

fn sampleSession() SessionInit {
    return .{ .filename = "review-1.md", .base_ref = "HEAD", .base_sha = "abc", .created = "2026-08-27T00:00:00Z" };
}

test "add, resolve, edit, and delete notes" {
    var notes: Notes = .{ .allocator = testing.allocator };
    defer notes.deinit();

    try notes.add(sampleSession(), try ownedNote(testing.allocator, "n1", "a.zig", "first"));
    try notes.add(sampleSession(), try ownedNote(testing.allocator, "n2", "b.zig", "second"));
    try testing.expectEqual(@as(usize, 2), notes.total());
    try testing.expectEqual(@as(usize, 1), notes.selected); // last added

    // Resolve toggles status.
    notes.toggleResolved();
    try testing.expectEqual(review.Status.resolved, notes.noteAt(notes.selectedRef().?).status);

    // Edit replaces the body.
    notes.replaceBody(try testing.allocator.dupe(u8, "second (edited)"));
    try testing.expectEqualStrings("second (edited)", notes.noteAt(notes.selectedRef().?).body);

    // Delete removes it.
    try notes.deleteSelected();
    try testing.expectEqual(@as(usize, 1), notes.total());
    try testing.expectEqualStrings("a.zig", notes.noteAt(notes.selectedRef().?).path);
}

test "deleting the last note removes the file and records it for deletion" {
    var notes: Notes = .{ .allocator = testing.allocator };
    defer notes.deinit();
    try notes.add(sampleSession(), try ownedNote(testing.allocator, "n1", "a.zig", "only"));

    try notes.deleteSelected();
    try testing.expectEqual(@as(usize, 0), notes.total());
    const removed = notes.takeRemoved();
    defer {
        for (removed) |name| testing.allocator.free(name);
        testing.allocator.free(removed);
    }
    try testing.expectEqual(@as(usize, 1), removed.len);
    try testing.expectEqualStrings("review-1.md", removed[0]);
}

test "forFile finds notes anchored to a path" {
    var notes: Notes = .{ .allocator = testing.allocator };
    defer notes.deinit();
    try notes.add(sampleSession(), try ownedNote(testing.allocator, "n1", "a.zig", "one"));
    try notes.add(sampleSession(), try ownedNote(testing.allocator, "n2", "a.zig", "two"));
    try notes.add(sampleSession(), try ownedNote(testing.allocator, "n3", "b.zig", "three"));

    var buffer: [8]NoteRef = undefined;
    const found = notes.forFile("a.zig", .unstaged, &buffer);
    try testing.expectEqual(@as(usize, 2), found.len);
}
