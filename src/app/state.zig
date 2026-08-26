const std = @import("std");
const document = @import("../model/document.zig");
const project = @import("../model/project.zig");
const project_browser = @import("project_browser.zig");

pub const Focus = enum {
    sidebar,
    main,
};

pub const App = struct {
    browser: project_browser.Browser,
    sidebar_visible: bool = true,
    focus: Focus = .sidebar,
    pinned: ?document.Snapshot = null,
    preview: ?document.Snapshot = null,
    cursor_grapheme: usize = 0,
    preferred_column: u32 = 0,
    document_scroll_line: usize = 0,
    document_scroll_column: u32 = 0,
    feedback: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator, tree: *const project.Tree) !App {
        return .{ .browser = try .init(allocator, tree) };
    }

    pub fn deinit(self: *App) void {
        if (self.preview) |*snapshot| snapshot.deinit();
        if (self.pinned) |*snapshot| snapshot.deinit();
        self.browser.deinit();
        self.* = undefined;
    }

    pub fn activeDocument(self: *const App) ?*const document.Snapshot {
        if (self.preview) |*snapshot| return snapshot;
        if (self.pinned) |*snapshot| return snapshot;
        return null;
    }

    pub fn showPreview(self: *App, snapshot: document.Snapshot) void {
        if (self.preview) |*previous| previous.deinit();
        self.preview = snapshot;
        self.feedback = null;
        self.resetDocumentPosition();
    }

    pub fn clearPreview(self: *App) void {
        if (self.preview) |*snapshot| snapshot.deinit();
        self.preview = null;
        self.feedback = null;
        self.resetDocumentPosition();
    }

    pub fn pinPreview(self: *App) bool {
        if (self.preview == null) return false;
        if (self.pinned) |*snapshot| snapshot.deinit();
        const pinned = self.preview.?;
        self.preview = null;
        self.pinned = pinned;
        self.focus = .main;
        self.resetDocumentPosition();
        return true;
    }

    pub fn collapseSidebar(self: *App) void {
        self.sidebar_visible = false;
        self.clearPreview();
        self.focus = .main;
    }

    pub fn showSidebar(self: *App) void {
        self.sidebar_visible = true;
        self.focus = .sidebar;
    }

    pub fn toggleFocus(self: *App) void {
        if (!self.sidebar_visible) {
            self.showSidebar();
            return;
        }
        self.focus = switch (self.focus) {
            .sidebar => .main,
            .main => .sidebar,
        };
    }

    pub fn moveHorizontal(self: *App, delta: isize, viewport_width: usize) void {
        const snapshot = self.activeDocument() orelse return;
        if (snapshot.graphemes.len == 0) return;
        const current: isize = @intCast(self.cursor_grapheme);
        const last: isize = @intCast(snapshot.graphemes.len - 1);
        self.cursor_grapheme = @intCast(std.math.clamp(current + delta, 0, last));
        self.preferred_column = snapshot.graphemes[self.cursor_grapheme].visual_column;
        self.ensureDocumentHorizontallyVisible(viewport_width);
    }

    pub fn moveVertical(
        self: *App,
        delta: isize,
        viewport_height: usize,
        viewport_width: usize,
    ) void {
        const snapshot = self.activeDocument() orelse return;
        if (snapshot.graphemes.len == 0) return;
        const current = snapshot.graphemes[@min(self.cursor_grapheme, snapshot.graphemes.len - 1)];
        const line_count: isize = @intCast(snapshot.lineCount());
        const target_line: usize = @intCast(std.math.clamp(
            @as(isize, @intCast(current.line)) + delta,
            0,
            line_count - 1,
        ));

        var best_index = self.cursor_grapheme;
        var fallback_index: ?usize = null;
        var best_distance: u32 = std.math.maxInt(u32);
        for (snapshot.graphemes, 0..) |grapheme, index| {
            if (grapheme.line != target_line) continue;
            if (grapheme.width == 0) {
                fallback_index = index;
                continue;
            }
            const distance = if (grapheme.visual_column > self.preferred_column)
                grapheme.visual_column - self.preferred_column
            else
                self.preferred_column - grapheme.visual_column;
            if (distance < best_distance) {
                best_distance = distance;
                best_index = index;
            }
        }
        if (best_distance == std.math.maxInt(u32)) {
            if (fallback_index) |index| best_index = index;
        }
        self.cursor_grapheme = best_index;
        self.ensureDocumentVisible(target_line, viewport_height);
        self.ensureDocumentHorizontallyVisible(viewport_width);
    }

    pub fn selection(self: *const App) document.ByteRange {
        const snapshot = self.activeDocument() orelse return .{ .start = 0, .end = 0 };
        return snapshot.sourceRangeForGrapheme(self.cursor_grapheme);
    }

    pub fn ensureCurrentDocumentVisible(
        self: *App,
        viewport_height: usize,
        viewport_width: usize,
    ) void {
        const snapshot = self.activeDocument() orelse return;
        if (snapshot.graphemes.len == 0) return;
        const line = snapshot.graphemes[@min(self.cursor_grapheme, snapshot.graphemes.len - 1)].line;
        self.ensureDocumentVisible(line, viewport_height);
        self.ensureDocumentHorizontallyVisible(viewport_width);
    }

    fn resetDocumentPosition(self: *App) void {
        self.cursor_grapheme = 0;
        self.preferred_column = 0;
        self.document_scroll_line = 0;
        self.document_scroll_column = 0;
    }

    fn ensureDocumentHorizontallyVisible(self: *App, viewport_width: usize) void {
        const snapshot = self.activeDocument() orelse return;
        if (snapshot.graphemes.len == 0 or viewport_width == 0) return;
        const selected = snapshot.graphemes[@min(self.cursor_grapheme, snapshot.graphemes.len - 1)];
        if (selected.visual_column < self.document_scroll_column) {
            self.document_scroll_column = selected.visual_column;
            return;
        }
        const end = selected.visual_column + @max(selected.width, 1);
        const width: u32 = @intCast(viewport_width);
        if (end > self.document_scroll_column + width) {
            self.document_scroll_column = end - width;
        }
    }

    fn ensureDocumentVisible(self: *App, line: usize, viewport_height: usize) void {
        if (viewport_height == 0) return;
        if (line < self.document_scroll_line) self.document_scroll_line = line;
        if (line >= self.document_scroll_line + viewport_height) {
            self.document_scroll_line = line - viewport_height + 1;
        }
    }
};

const noop_snapshot = @import("../model/document.zig");

test "preview cancellation and sidebar collapse restore the pinned document" {
    const nodes = [_]project.Node{.{ .path = "a.txt", .depth = 1, .kind = .file }};
    const tree: project.Tree = .{
        .allocator = std.testing.allocator,
        .nodes = @constCast(&nodes),
        .file_count = 1,
    };
    var app = try App.init(std.testing.allocator, &tree);
    defer app.deinit();

    app.pinned = try testSnapshot("pinned.txt", "pinned");
    app.showPreview(try testSnapshot("preview.txt", "preview"));
    try std.testing.expectEqualStrings("preview.txt", app.activeDocument().?.path);
    app.collapseSidebar();
    try std.testing.expectEqualStrings("pinned.txt", app.activeDocument().?.path);
    try std.testing.expect(!app.sidebar_visible);
}

test "focus and collapsed state survive responsive layout changes" {
    const nodes = [_]project.Node{.{ .path = "a.txt", .depth = 1, .kind = .file }};
    const tree: project.Tree = .{
        .allocator = std.testing.allocator,
        .nodes = @constCast(&nodes),
        .file_count = 1,
    };
    var app = try App.init(std.testing.allocator, &tree);
    defer app.deinit();

    app.browser.scroll = 0;
    app.toggleFocus();
    try std.testing.expectEqual(Focus.main, app.focus);
    app.collapseSidebar();
    try std.testing.expect(!app.sidebar_visible);
    app.showSidebar();
    try std.testing.expectEqual(Focus.sidebar, app.focus);
    try std.testing.expectEqual(@as(usize, 0), app.browser.scroll);
}

test "horizontal navigation selects complete byte ranges and scrolls" {
    const nodes = [_]project.Node{.{ .path = "a.txt", .depth = 1, .kind = .file }};
    const tree: project.Tree = .{
        .allocator = std.testing.allocator,
        .nodes = @constCast(&nodes),
        .file_count = 1,
    };
    var app = try App.init(std.testing.allocator, &tree);
    defer app.deinit();
    app.showPreview(try testSnapshot("a.txt", "abcdef"));

    app.moveHorizontal(5, 3);
    try std.testing.expectEqual(document.ByteRange{ .start = 5, .end = 6 }, app.selection());
    try std.testing.expectEqual(@as(u32, 3), app.document_scroll_column);
}

test "pinning a preview focuses main without duplicate ownership" {
    const nodes = [_]project.Node{.{ .path = "a.txt", .depth = 1, .kind = .file }};
    const tree: project.Tree = .{
        .allocator = std.testing.allocator,
        .nodes = @constCast(&nodes),
        .file_count = 1,
    };
    var app = try App.init(std.testing.allocator, &tree);
    defer app.deinit();
    app.showPreview(try testSnapshot("a.txt", "a"));

    try std.testing.expect(app.pinPreview());
    try std.testing.expectEqual(Focus.main, app.focus);
    try std.testing.expect(app.preview == null);
    try std.testing.expectEqualStrings("a.txt", app.pinned.?.path);
}

fn testSnapshot(path: []const u8, bytes: []const u8) !noop_snapshot.Snapshot {
    return noop_snapshot.Snapshot.init(
        std.testing.allocator,
        path,
        bytes,
        1,
        .{ .size = bytes.len },
        .{ .next_fn = scalarNext, .width_fn = scalarWidth },
    );
}

fn scalarNext(_: ?*const anyopaque, text: []const u8, start: usize) usize {
    return @min(text.len, start + (std.unicode.utf8ByteSequenceLength(text[start]) catch 1));
}

fn scalarWidth(_: ?*const anyopaque, text: []const u8) u16 {
    return if (std.mem.eql(u8, text, "\n")) 0 else 1;
}
