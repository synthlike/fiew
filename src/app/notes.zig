//! In-memory reviewer-owned thread state. Persisted comments are append-only;
//! reviewer lifecycle operations mark their owning review file dirty until the
//! storage adapter confirms a durable write.

const std = @import("std");
const review = @import("../model/review.zig");
const git = @import("../model/git.zig");
const store = @import("../adapters/storage/review_store.zig");

pub const ThreadRef = struct { file: usize, thread: usize };
pub const NoteRef = ThreadRef; // Transitional internal name for render call sites.

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
    threads: std.ArrayListUnmanaged(review.Thread) = .empty,
    dirty: bool = false,

    fn view(self: ReviewFile) review.Review {
        return .{ .allocator = undefined, .base_ref = self.base_ref, .base_sha = self.base_sha, .created = self.created, .threads = self.threads.items };
    }
};

pub const Error = std.mem.Allocator.Error || error{ PermissionDenied, InvalidComment };

pub const Notes = struct {
    allocator: std.mem.Allocator,
    files: std.ArrayListUnmanaged(ReviewFile) = .empty,
    session: ?usize = null,
    selected: usize = 0,
    scroll: usize = 0,
    detail_scroll: usize = 0,
    next_id: usize = 1,
    removed: std.ArrayListUnmanaged([]u8) = .empty,

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
            for (entry.review.threads) |thread| try file.threads.append(allocator, try dupeThread(allocator, thread));
            try self.files.append(allocator, file);
        }
        self.recalculateNextId();
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
        for (self.files.items) |file| count += file.threads.items.len;
        return count;
    }

    pub fn useSession(self: *Notes, filename: []const u8) void {
        for (self.files.items, 0..) |file, index| if (std.mem.eql(u8, file.filename, filename)) {
            self.session = index;
            return;
        };
    }

    pub fn blockingCountInFile(self: Notes, filename: []const u8) usize {
        var count: usize = 0;
        for (self.files.items) |file| {
            if (!std.mem.eql(u8, file.filename, filename)) continue;
            for (file.threads.items) |thread| {
                if (thread.status.blocksApproval()) count += 1;
            }
        }
        return count;
    }

    pub fn openCountInFile(self: Notes, filename: []const u8) usize {
        return self.blockingCountInFile(filename);
    }

    pub fn approved(self: Notes, filename: []const u8) bool {
        return self.blockingCountInFile(filename) == 0 and !self.hasDirty();
    }

    pub fn hasDirty(self: Notes) bool {
        for (self.files.items) |file| if (file.dirty) return true;
        return self.removed.items.len != 0;
    }

    pub fn refAt(self: Notes, flat_index: usize) ?ThreadRef {
        var remaining = flat_index;
        for (self.files.items, 0..) |file, file_index| {
            if (remaining < file.threads.items.len) return .{ .file = file_index, .thread = remaining };
            remaining -= file.threads.items.len;
        }
        return null;
    }

    pub fn selectedRef(self: Notes) ?ThreadRef {
        return self.refAt(self.selected);
    }

    pub fn threadAt(self: Notes, ref: ThreadRef) *review.Thread {
        return &self.files.items[ref.file].threads.items[ref.thread];
    }

    pub fn noteAt(self: Notes, ref: ThreadRef) *review.Thread {
        return self.threadAt(ref);
    }

    pub fn nextId(self: *Notes, allocator: std.mem.Allocator) ![]u8 {
        const id = try std.fmt.allocPrint(allocator, "t{d}", .{self.next_id});
        self.next_id += 1;
        return id;
    }

    pub fn addThread(self: *Notes, actor: review.Author, session_init: SessionInit, thread: review.Thread) Error!void {
        if (actor != .reviewer) return error.PermissionDenied;
        if (thread.comments.len == 0 or thread.comments[0].author != .reviewer) return error.InvalidComment;
        if (self.session == null) {
            const file: ReviewFile = .{
                .filename = try self.allocator.dupe(u8, session_init.filename),
                .base_ref = try self.allocator.dupe(u8, session_init.base_ref),
                .base_sha = try self.allocator.dupe(u8, session_init.base_sha),
                .created = try self.allocator.dupe(u8, session_init.created),
            };
            try self.files.append(self.allocator, file);
            self.session = self.files.items.len - 1;
        }
        const index = self.session.?;
        try self.files.items[index].threads.append(self.allocator, thread);
        self.files.items[index].dirty = true;
        self.selected = self.flatIndex(.{ .file = index, .thread = self.files.items[index].threads.items.len - 1 });
        self.ensureVisible(20);
    }

    pub fn appendComment(self: *Notes, ref: ThreadRef, author: review.Author, owned_body: []u8) Error!void {
        var thread = self.threadAt(ref);
        const comments = try self.allocator.realloc(thread.comments, thread.comments.len + 1);
        comments[comments.len - 1] = .{ .author = author, .body = owned_body };
        thread.comments = comments;
        self.files.items[ref.file].dirty = true;
    }

    pub fn setResolved(self: *Notes, actor: review.Author, resolved: bool) Error!void {
        if (actor != .reviewer) return error.PermissionDenied;
        const ref = self.selectedRef() orelse return;
        const thread = self.threadAt(ref);
        thread.status = if (resolved) .resolved else .open;
        self.files.items[ref.file].dirty = true;
    }

    pub fn toggleResolved(self: *Notes) void {
        const ref = self.selectedRef() orelse return;
        const resolved = self.threadAt(ref).status != .resolved;
        self.setResolved(.reviewer, resolved) catch {};
    }

    pub fn deleteSelected(self: *Notes, actor: review.Author) Error!void {
        if (actor != .reviewer) return error.PermissionDenied;
        const ref = self.selectedRef() orelse return;
        var file = &self.files.items[ref.file];
        const removed_thread = file.threads.orderedRemove(ref.thread);
        review.freeThread(self.allocator, removed_thread);
        file.dirty = true;
        // An empty review is still a durable named review. Deleting its final
        // thread must not delete the review identity used by `fiew review`.
        if (self.selected >= self.total() and self.selected > 0) self.selected = self.total() -| 1;
        self.ensureVisible(20);
    }

    pub fn moveSelection(self: *Notes, delta: isize, viewport_rows: usize) void {
        const count = self.total();
        if (count == 0) return;
        const current: isize = @intCast(self.selected);
        self.selected = @intCast(std.math.clamp(current + delta, 0, @as(isize, @intCast(count - 1))));
        self.detail_scroll = 0;
        self.ensureVisible(viewport_rows);
    }

    pub fn selectVisible(self: *Notes, visible_index: usize, viewport_rows: usize) void {
        const index = self.scroll + visible_index;
        if (index >= self.total()) return;
        self.selected = index;
        self.detail_scroll = 0;
        self.ensureVisible(viewport_rows);
    }

    pub fn scrollDetail(self: *Notes, delta: isize) void {
        const current: isize = @intCast(self.detail_scroll);
        self.detail_scroll = @intCast(@max(current + delta, 0));
    }

    pub fn forFile(self: Notes, path: []const u8, group: git.Group, buffer: []ThreadRef) []ThreadRef {
        var count: usize = 0;
        for (self.files.items, 0..) |file, file_index| for (file.threads.items, 0..) |thread, thread_index| {
            if (thread.group == group and std.mem.eql(u8, thread.path, path)) {
                if (count >= buffer.len) return buffer[0..count];
                buffer[count] = .{ .file = file_index, .thread = thread_index };
                count += 1;
            }
        };
        return buffer[0..count];
    }

    pub fn dirtyFiles(self: Notes, buffer: []DirtyFile) []DirtyFile {
        var count: usize = 0;
        for (self.files.items) |file| {
            if (!file.dirty or count >= buffer.len) continue;
            buffer[count] = .{ .filename = file.filename, .review = file.view() };
            count += 1;
        }
        return buffer[0..count];
    }

    pub fn markClean(self: *Notes, filename: []const u8) void {
        for (self.files.items) |*file| {
            if (std.mem.eql(u8, file.filename, filename)) file.dirty = false;
        }
    }

    pub fn removedFiles(self: Notes) []const []u8 {
        return self.removed.items;
    }

    pub fn markRemoved(self: *Notes, filename: []const u8) void {
        for (self.removed.items, 0..) |name, index| {
            if (!std.mem.eql(u8, name, filename)) continue;
            self.allocator.free(self.removed.orderedRemove(index));
            return;
        }
    }

    pub const DirtyFile = struct { filename: []const u8, review: review.Review };

    fn ensureVisible(self: *Notes, viewport_rows: usize) void {
        if (viewport_rows == 0) return;
        if (self.selected < self.scroll) self.scroll = self.selected;
        if (self.selected >= self.scroll + viewport_rows) self.scroll = self.selected - viewport_rows + 1;
    }

    fn flatIndex(self: Notes, ref: ThreadRef) usize {
        var index: usize = 0;
        for (self.files.items[0..ref.file]) |file| index += file.threads.items.len;
        return index + ref.thread;
    }

    fn dropFile(self: *Notes, index: usize) void {
        var file = self.files.orderedRemove(index);
        freeFile(self.allocator, &file);
        if (self.session) |current| {
            if (current == index) self.session = null else if (current > index) self.session = current - 1;
        }
    }

    fn recalculateNextId(self: *Notes) void {
        for (self.files.items) |file| for (file.threads.items) |thread| {
            if (thread.id.len > 1 and thread.id[0] == 't') {
                const value = std.fmt.parseInt(usize, thread.id[1..], 10) catch continue;
                self.next_id = @max(self.next_id, value + 1);
            }
        };
    }
};

fn dupeThread(allocator: std.mem.Allocator, thread: review.Thread) !review.Thread {
    const id = try allocator.dupe(u8, thread.id);
    errdefer allocator.free(id);
    const path = try allocator.dupe(u8, thread.path);
    errdefer allocator.free(path);
    const blob = if (thread.blob) |value| try allocator.dupe(u8, value) else null;
    errdefer if (blob) |value| allocator.free(value);
    const excerpt = if (thread.excerpt) |value| try allocator.dupe(u8, value) else null;
    errdefer if (excerpt) |value| allocator.free(value);
    const comments = try allocator.alloc(review.Comment, thread.comments.len);
    errdefer allocator.free(comments);
    for (thread.comments, 0..) |comment, index| comments[index] = .{
        .author = comment.author,
        .body = try allocator.dupe(u8, comment.body),
    };
    return .{ .id = id, .path = path, .group = thread.group, .status = thread.status, .side = thread.side, .start_line = thread.start_line, .end_line = thread.end_line, .blob = blob, .excerpt = excerpt, .comments = comments };
}

fn freeFile(allocator: std.mem.Allocator, file: *ReviewFile) void {
    for (file.threads.items) |thread| review.freeThread(allocator, thread);
    file.threads.deinit(allocator);
    allocator.free(file.filename);
    allocator.free(file.base_ref);
    allocator.free(file.base_sha);
    allocator.free(file.created);
}

const testing = std.testing;

fn ownedThread(allocator: std.mem.Allocator, id: []const u8, author: review.Author) !review.Thread {
    const comments = try allocator.alloc(review.Comment, 1);
    comments[0] = .{ .author = author, .body = try allocator.dupe(u8, "body") };
    return .{ .id = try allocator.dupe(u8, id), .path = try allocator.dupe(u8, "a.zig"), .group = .unstaged, .status = .open, .comments = comments };
}

fn sampleSession() SessionInit {
    return .{ .filename = "review.md", .base_ref = "HEAD", .base_sha = "abc", .created = "now" };
}

test "comments append in role order and cannot be replaced" {
    var notes: Notes = .{ .allocator = testing.allocator };
    defer notes.deinit();
    try notes.addThread(.reviewer, sampleSession(), try ownedThread(testing.allocator, "t1", .reviewer));
    const ref = notes.selectedRef().?;
    try notes.appendComment(ref, .agent, try testing.allocator.dupe(u8, "agent reply"));
    try notes.appendComment(ref, .reviewer, try testing.allocator.dupe(u8, "reviewer reply"));
    try testing.expectEqual(review.Author.reviewer, notes.threadAt(ref).comments[0].author);
    try testing.expectEqual(review.Author.agent, notes.threadAt(ref).comments[1].author);
    try testing.expectEqualStrings("reviewer reply", notes.threadAt(ref).comments[2].body);
}

test "agent cannot create or control thread lifecycle" {
    var notes: Notes = .{ .allocator = testing.allocator };
    defer notes.deinit();
    const forbidden = try ownedThread(testing.allocator, "t1", .agent);
    try testing.expectError(error.PermissionDenied, notes.addThread(.agent, sampleSession(), forbidden));
    review.freeThread(testing.allocator, forbidden);
    try notes.addThread(.reviewer, sampleSession(), try ownedThread(testing.allocator, "t2", .reviewer));
    try testing.expectError(error.PermissionDenied, notes.setResolved(.agent, true));
    try testing.expectError(error.PermissionDenied, notes.deleteSelected(.agent));
}

test "deleting the final thread preserves an empty durable review" {
    var notes: Notes = .{ .allocator = testing.allocator };
    defer notes.deinit();
    try notes.addThread(.reviewer, sampleSession(), try ownedThread(testing.allocator, "t1", .reviewer));
    try notes.deleteSelected(.reviewer);
    try testing.expectEqual(@as(usize, 0), notes.total());
    var dirty: [1]Notes.DirtyFile = undefined;
    const files = notes.dirtyFiles(&dirty);
    try testing.expectEqual(@as(usize, 1), files.len);
    try testing.expectEqual(@as(usize, 0), files[0].review.threads.len);
    try testing.expectEqual(@as(usize, 0), notes.removedFiles().len);
}

test "Review sidebar selection and scroll are independent" {
    var notes: Notes = .{ .allocator = testing.allocator };
    defer notes.deinit();
    try notes.addThread(.reviewer, sampleSession(), try ownedThread(testing.allocator, "t1", .reviewer));
    try notes.addThread(.reviewer, sampleSession(), try ownedThread(testing.allocator, "t2", .reviewer));
    try notes.addThread(.reviewer, sampleSession(), try ownedThread(testing.allocator, "t3", .reviewer));
    notes.selected = 0;
    notes.scroll = 0;
    notes.moveSelection(2, 2);
    try testing.expectEqual(@as(usize, 2), notes.selected);
    try testing.expectEqual(@as(usize, 1), notes.scroll);
    notes.selectVisible(0, 2);
    try testing.expectEqual(@as(usize, 1), notes.selected);
}

test "dirty state remains until durable save is acknowledged" {
    var notes: Notes = .{ .allocator = testing.allocator };
    defer notes.deinit();
    try notes.addThread(.reviewer, sampleSession(), try ownedThread(testing.allocator, "t1", .reviewer));
    try testing.expect(notes.hasDirty());
    var buffer: [1]Notes.DirtyFile = undefined;
    const dirty = notes.dirtyFiles(&buffer);
    try testing.expectEqual(@as(usize, 1), dirty.len);
    // A failed adapter call performs no acknowledgement.
    try testing.expect(notes.hasDirty());
    try notes.setResolved(.reviewer, true);
    try testing.expect(!notes.approved("review.md"));
    notes.markClean("review.md");
    try testing.expect(!notes.hasDirty());
    try testing.expect(notes.approved("review.md"));
}

test "open and outdated threads block approval" {
    var notes: Notes = .{ .allocator = testing.allocator };
    defer notes.deinit();
    try notes.addThread(.reviewer, sampleSession(), try ownedThread(testing.allocator, "t1", .reviewer));
    try testing.expectEqual(@as(usize, 1), notes.blockingCountInFile("review.md"));
    notes.threadAt(notes.selectedRef().?).status = .outdated;
    try testing.expectEqual(@as(usize, 1), notes.blockingCountInFile("review.md"));
    try notes.setResolved(.reviewer, true);
    try testing.expectEqual(@as(usize, 0), notes.blockingCountInFile("review.md"));
}
