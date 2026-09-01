//! In-memory state for Trails belonging to one active named review.

const std = @import("std");
const trail = @import("../model/trail.zig");
const anchor = @import("../model/anchor.zig");

pub const Draft = struct {
    points: std.ArrayListUnmanaged(trail.Point) = .empty,

    pub fn deinit(self: *Draft, allocator: std.mem.Allocator) void {
        for (self.points.items) |point| freePoint(allocator, point);
        self.points.deinit(allocator);
        self.* = undefined;
    }
};

pub const Trails = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    review: []u8,
    items: std.ArrayListUnmanaged(trail.Trail) = .empty,
    dirty_items: std.ArrayListUnmanaged(bool) = .empty,
    deleted_ids: std.ArrayListUnmanaged([]u8) = .empty,
    selected_trail: usize = 0,
    selected_point: usize = 0,
    detail: bool = false,
    recording: ?Draft = null,
    dirty: bool = false,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, review: []const u8) !Trails {
        return .{ .allocator = allocator, .io = io, .review = try allocator.dupe(u8, review) };
    }

    pub fn fromStored(allocator: std.mem.Allocator, io: std.Io, expected_review: []const u8, persisted: []const trail.Trail) !Trails {
        var self = try init(allocator, io, expected_review);
        errdefer self.deinit();
        for (persisted) |item| {
            if (!std.mem.eql(u8, expected_review, item.owner.review)) continue;
            try self.items.append(allocator, try cloneTrail(allocator, item));
            try self.dirty_items.append(allocator, false);
        }
        return self;
    }

    pub fn deinit(self: *Trails) void {
        if (self.recording) |*draft| draft.deinit(self.allocator);
        for (self.items.items) |item| freeTrail(self.allocator, item);
        self.items.deinit(self.allocator);
        self.dirty_items.deinit(self.allocator);
        for (self.deleted_ids.items) |id| self.allocator.free(id);
        self.deleted_ids.deinit(self.allocator);
        self.allocator.free(self.review);
        self.* = undefined;
    }

    pub fn start(self: *Trails, point: trail.Point) !void {
        if (self.recording != null) return error.AlreadyRecording;
        var draft: Draft = .{};
        errdefer draft.deinit(self.allocator);
        try draft.points.append(self.allocator, point);
        self.recording = draft;
    }

    pub fn appendPoint(self: *Trails, point: trail.Point) !void {
        const draft = if (self.recording) |*value| value else return error.NotRecording;
        try draft.points.append(self.allocator, point);
    }

    pub fn pointCount(self: Trails) usize {
        return if (self.recording) |draft| draft.points.items.len else 0;
    }

    pub fn saveDraft(self: *Trails, title: []const u8, note: []const u8) !void {
        if (!trail.validTitle(title)) return error.InvalidTitle;
        if (!trail.validNote(note)) return error.InvalidNote;
        const draft = if (self.recording) |*value| value else return error.NotRecording;
        if (draft.points.items.len < 2) return error.TooFewPoints;
        const owned_title = try self.allocator.dupe(u8, title);
        errdefer self.allocator.free(owned_title);
        const owned_note = try self.allocator.dupe(u8, note);
        errdefer self.allocator.free(owned_note);
        try self.items.ensureUnusedCapacity(self.allocator, 1);
        try self.dirty_items.ensureUnusedCapacity(self.allocator, 1);
        const id = try newId(self.allocator, self.io);
        errdefer self.allocator.free(id);
        const owner = try self.allocator.dupe(u8, self.review);
        errdefer self.allocator.free(owner);
        const points = try draft.points.toOwnedSlice(self.allocator);
        draft.* = .{};
        self.items.appendAssumeCapacity(.{ .id = id, .owner = .{ .review = owner }, .title = owned_title, .note = owned_note, .points = points });
        self.dirty_items.appendAssumeCapacity(true);
        self.selected_trail = self.items.items.len - 1;
        self.selected_point = 0;
        self.detail = false;
        draft.deinit(self.allocator);
        self.recording = null;
        self.dirty = true;
    }

    pub fn deleteSelected(self: *Trails) !void {
        if (self.selected_trail >= self.items.items.len) return;
        try self.deleted_ids.ensureUnusedCapacity(self.allocator, 1);
        const removed = self.items.orderedRemove(self.selected_trail);
        _ = self.dirty_items.orderedRemove(self.selected_trail);
        self.deleted_ids.appendAssumeCapacity(@constCast(removed.id));
        freeTrailExceptId(self.allocator, removed);
        if (self.selected_trail >= self.items.items.len and self.selected_trail > 0) self.selected_trail -= 1;
        self.selected_point = 0;
        self.detail = false;
        self.dirty = true;
    }

    pub fn selectedTrail(self: *Trails) ?*trail.Trail {
        if (self.selected_trail >= self.items.items.len) return null;
        return &self.items.items[self.selected_trail];
    }

    pub fn selectedPoint(self: *Trails) ?*trail.Point {
        const item = self.selectedTrail() orelse return null;
        if (self.selected_point >= item.points.len) return null;
        return @constCast(&item.points[self.selected_point]);
    }

    pub fn moveSelection(self: *Trails, delta: isize) void {
        const length = if (self.detail) if (self.selectedTrail()) |item| item.points.len else 0 else self.items.items.len;
        if (length == 0) return;
        const current = if (self.detail) self.selected_point else self.selected_trail;
        const next: usize = @intCast(std.math.clamp(@as(isize, @intCast(current)) + delta, 0, @as(isize, @intCast(length - 1))));
        if (self.detail) self.selected_point = next else self.selected_trail = next;
    }

    pub fn openSelected(self: *Trails) bool {
        if (self.selectedTrail() == null) return false;
        self.detail = true;
        self.selected_point = 0;
        return true;
    }

    pub fn closeDetail(self: *Trails) void {
        self.detail = false;
    }

    pub fn markSelectedOutdated(self: *Trails) void {
        const point = self.selectedPoint() orelse return;
        if (point.status != .outdated) {
            point.status = .outdated;
            self.markSelectedDirty();
        }
    }

    pub fn reanchorPoint(self: *Trails, point: *trail.Point, source: []const u8) void {
        switch (anchor.match(point.context, source)) {
            .retained => if (point.status == .outdated) {
                point.status = .current;
                self.markSelectedDirty();
            },
            .relocated => |context_start| {
                point.context.original_start = context_start;
                point.source_offset = point.context.targetOffset(context_start) + point.line_offset;
                point.anchored_line = 1 + std.mem.count(u8, source[0..point.source_offset], "\n");
                point.status = .current;
                self.markSelectedDirty();
            },
            .outdated => if (point.status != .outdated) {
                point.status = .outdated;
                self.markSelectedDirty();
            },
        }
    }

    fn markSelectedDirty(self: *Trails) void {
        if (self.selected_trail < self.dirty_items.items.len) self.dirty_items.items[self.selected_trail] = true;
        self.dirty = true;
    }

    pub fn nextDirty(self: *Trails) ?*trail.Trail {
        for (self.dirty_items.items, 0..) |is_dirty, index| if (is_dirty) return &self.items.items[index];
        return null;
    }

    pub fn markTrailClean(self: *Trails, id: []const u8) void {
        for (self.items.items, 0..) |item, index| if (std.mem.eql(u8, item.id, id)) {
            self.dirty_items.items[index] = false;
            break;
        };
        self.refreshDirty();
    }

    pub fn nextDeleted(self: *Trails) ?[]const u8 {
        return if (self.deleted_ids.items.len == 0) null else self.deleted_ids.items[0];
    }

    pub fn markDeleted(self: *Trails, id: []const u8) void {
        if (self.deleted_ids.items.len == 0 or !std.mem.eql(u8, self.deleted_ids.items[0], id)) return;
        self.allocator.free(self.deleted_ids.orderedRemove(0));
        self.refreshDirty();
    }

    fn refreshDirty(self: *Trails) void {
        self.dirty = self.deleted_ids.items.len != 0;
        if (!self.dirty) for (self.dirty_items.items) |value| if (value) {
            self.dirty = true;
            break;
        };
    }
};

pub fn clonePoint(allocator: std.mem.Allocator, point: trail.Point) !trail.Point {
    const path = try allocator.dupe(u8, point.path);
    errdefer allocator.free(path);
    const content = try allocator.dupe(u8, point.content);
    errdefer allocator.free(content);
    const context = try allocator.dupe(u8, point.context.bytes);
    errdefer allocator.free(context);
    return .{ .path = path, .line = point.line, .anchored_line = point.anchored_line, .column = point.column, .source_offset = point.source_offset, .line_offset = point.line_offset, .content = content, .context = .{ .bytes = context, .original_start = point.context.original_start, .target_start = point.context.target_start, .target_end = point.context.target_end }, .status = point.status };
}

fn newId(allocator: std.mem.Allocator, io: std.Io) ![]u8 {
    var random: [16]u8 = undefined;
    io.random(&random);
    const id = try allocator.alloc(u8, trail.id_bytes);
    const hex = "0123456789abcdef";
    for (random, 0..) |byte, index| {
        id[index * 2] = hex[byte >> 4];
        id[index * 2 + 1] = hex[byte & 0x0f];
    }
    return id;
}

fn cloneTrail(allocator: std.mem.Allocator, item: trail.Trail) !trail.Trail {
    const id = try allocator.dupe(u8, item.id);
    errdefer allocator.free(id);
    const owner = try allocator.dupe(u8, item.owner.review);
    errdefer allocator.free(owner);
    const title = try allocator.dupe(u8, item.title);
    errdefer allocator.free(title);
    const note = try allocator.dupe(u8, item.note);
    errdefer allocator.free(note);
    var points: std.ArrayList(trail.Point) = .empty;
    errdefer {
        for (points.items) |point| freePoint(allocator, point);
        points.deinit(allocator);
    }
    for (item.points) |point| try points.append(allocator, try clonePoint(allocator, point));
    return .{ .id = id, .owner = .{ .review = owner }, .title = title, .note = note, .points = try points.toOwnedSlice(allocator) };
}

pub fn freePoint(allocator: std.mem.Allocator, point: trail.Point) void {
    allocator.free(point.path);
    allocator.free(point.content);
    allocator.free(point.context.bytes);
}

fn freeTrailExceptId(allocator: std.mem.Allocator, item: trail.Trail) void {
    allocator.free(item.owner.review);
    allocator.free(item.title);
    allocator.free(item.note);
    for (item.points) |point| freePoint(allocator, point);
    allocator.free(item.points);
}

fn freeTrail(allocator: std.mem.Allocator, item: trail.Trail) void {
    allocator.free(item.id);
    freeTrailExceptId(allocator, item);
}

test "record save select delete and conservative re-anchor" {
    var state = try Trails.init(std.testing.allocator, std.testing.io, "review.json");
    defer state.deinit();
    const p: trail.Point = .{ .path = try std.testing.allocator.dupe(u8, "a.zig"), .line = 1, .source_offset = 0, .line_offset = 0, .content = try std.testing.allocator.dupe(u8, "target"), .context = .{ .bytes = try std.testing.allocator.dupe(u8, "target\n"), .original_start = 0, .target_start = 0, .target_end = 6 } };
    try state.start(p);
    try state.appendPoint(try clonePoint(std.testing.allocator, p));
    try state.saveDraft("Path", "note");
    try std.testing.expectEqual(@as(usize, 2), state.selectedTrail().?.points.len);
    _ = state.openSelected();
    state.reanchorPoint(state.selectedPoint().?, "x\ntarget\n");
    try std.testing.expectEqual(@as(usize, 2), state.selectedPoint().?.source_offset);
    try std.testing.expectEqual(@as(usize, 2), state.selectedPoint().?.anchored_line.?);
    state.reanchorPoint(state.selectedPoint().?, "target\ntarget\n");
    try std.testing.expectEqual(trail.Status.outdated, state.selectedPoint().?.status);
    try std.testing.expectEqualStrings("a.zig", state.selectedPoint().?.path);
    try std.testing.expectEqualStrings("target", state.selectedPoint().?.content);
    try std.testing.expectEqual(@as(usize, 1), state.selectedPoint().?.line);
    try state.deleteSelected();
    try std.testing.expectEqual(@as(usize, 0), state.items.items.len);
}
