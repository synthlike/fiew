const std = @import("std");
const document = @import("../model/document.zig");
const project = @import("../model/project.zig");
const syntax = @import("../model/syntax.zig");
const project_browser = @import("project_browser.zig");
const git_review = @import("git_review.zig");
const notes_state = @import("notes.zig");
const git = @import("../model/git.zig");
const review = @import("../model/review.zig");
const bookmark_model = @import("../model/bookmark.zig");
const bookmarks_state = @import("bookmarks.zig");
const trails_state = @import("trails.zig");
const trail_model = @import("../model/trail.zig");
const anchor_model = @import("../model/anchor.zig");
const lsp = @import("../model/lsp.zig");
const definitions_state = @import("definitions.zig");
const hover_state = @import("hover.zig");

/// Which structural relation to move the selection toward.
pub const StructuralMove = enum { parent, child, next_sibling, previous_sibling };

/// Which context the collapsible sidebar is showing.
pub const SidebarContext = enum { project, git, review, bookmarks };

pub const GitStatus = enum { disabled, idle, pending, stale };

/// A captured diff anchor with owned strings, held while composing a new note.
pub const OwnedAnchor = struct {
    path: []u8,
    group: git.Group,
    side: ?review.Side = null,
    start_line: ?usize = null,
    end_line: ?usize = null,
    blob: ?[]u8 = null,
    excerpt: ?[]u8 = null,
    context: ?anchor_model.Context = null,

    pub fn deinit(self: *OwnedAnchor, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        if (self.blob) |blob| allocator.free(blob);
        if (self.excerpt) |excerpt| allocator.free(excerpt);
        if (self.context) |context| allocator.free(context.bytes);
    }
};

/// The transient Note Composer: a multiline text buffer plus what it will save.
pub const BookmarkTarget = struct {
    path: []u8,
    line: usize,
    column: usize,
    source_offset: usize,

    pub fn deinit(self: *BookmarkTarget, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        self.* = undefined;
    }
};

pub const BookmarkComposer = struct {
    buffer: std.ArrayListUnmanaged(u8) = .empty,
    target: BookmarkTarget,

    pub fn deinit(self: *BookmarkComposer, allocator: std.mem.Allocator) void {
        self.buffer.deinit(allocator);
        self.target.deinit(allocator);
        self.* = undefined;
    }
};

pub const TrailComposerField = enum { title, note };

pub const TrailComposer = struct {
    title: std.ArrayListUnmanaged(u8) = .empty,
    note: std.ArrayListUnmanaged(u8) = .empty,
    field: TrailComposerField = .title,

    pub fn deinit(self: *TrailComposer, allocator: std.mem.Allocator) void {
        self.title.deinit(allocator);
        self.note.deinit(allocator);
        self.* = undefined;
    }
};

pub const Composer = struct {
    buffer: std.ArrayListUnmanaged(u8) = .empty,
    modified: bool = false,
    /// Set after one Esc when modified, requiring a second Esc to discard.
    discard_armed: bool = false,
    /// Present when composing a new thread; null when appending a reviewer comment.
    anchor: ?OwnedAnchor = null,

    pub fn deinit(self: *Composer, allocator: std.mem.Allocator) void {
        self.buffer.deinit(allocator);
        if (self.anchor) |*anchor| anchor.deinit(allocator);
        self.* = undefined;
    }
};

pub const Focus = enum {
    sidebar,
    main,
};

pub const Mode = enum {
    normal,
    extend,
    command,
};

pub const View = struct {
    snapshot: document.Snapshot,
    anchor_grapheme: usize = 0,
    active_grapheme: usize = 0,
    preferred_column: u32 = 0,
    scroll_line: usize = 0,
    scroll_column: u32 = 0,
    external: bool = false,
    /// Syntax analysis for this snapshot, when Tree-sitter produced it.
    syntax: ?syntax.ParseData = null,
    /// Start lines of folds the user has collapsed in this view.
    closed_folds: std.ArrayListUnmanaged(usize) = .empty,

    pub fn deinit(self: *View) void {
        if (self.syntax) |*data| data.deinit();
        self.closed_folds.deinit(self.snapshot.allocator);
        self.snapshot.deinit();
        self.* = undefined;
    }

    /// Replace this view's syntax analysis, dropping any collapsed folds that no
    /// longer correspond to a fold in the new analysis.
    pub fn setSyntax(self: *View, data: syntax.ParseData) void {
        if (self.syntax) |*previous| {
            var kept: usize = 0;
            for (self.closed_folds.items) |start| {
                if (foldWithStart(data.folds, start) != null) {
                    self.closed_folds.items[kept] = start;
                    kept += 1;
                }
            }
            self.closed_folds.shrinkRetainingCapacity(kept);
            previous.deinit();
        }
        self.syntax = data;
    }

    /// A line is hidden when it lies inside (but not at the start of) any
    /// collapsed fold.
    pub fn isLineHidden(self: *const View, line: usize) bool {
        const data = self.syntax orelse return false;
        for (self.closed_folds.items) |start| {
            const fold = foldWithStart(data.folds, start) orelse continue;
            if (line > fold.start_line and line <= fold.end_line) return true;
        }
        return false;
    }

    /// The first visible line at or after `line`, or null if none remain.
    pub fn firstVisibleLine(self: *const View, line: usize, line_count: usize) ?usize {
        var candidate = line;
        while (candidate < line_count) : (candidate += 1) {
            if (!self.isLineHidden(candidate)) return candidate;
        }
        return null;
    }

    /// Step one visible line in `direction` (-1 or +1), skipping hidden lines.
    /// Returns null at the first/last visible line.
    fn stepVisibleLine(self: *const View, line: usize, direction: isize, line_count: usize) ?usize {
        var candidate = line;
        while (true) {
            if (direction < 0) {
                if (candidate == 0) return null;
                candidate -= 1;
            } else {
                if (candidate + 1 >= line_count) return null;
                candidate += 1;
            }
            if (!self.isLineHidden(candidate)) return candidate;
        }
    }

    pub fn selection(self: View) document.ByteRange {
        if (self.snapshot.graphemes.len == 0) return .{ .start = 0, .end = 0 };
        const anchor = self.snapshot.sourceRangeForGrapheme(self.anchor_grapheme);
        const active = self.snapshot.sourceRangeForGrapheme(self.active_grapheme);
        return .{
            .start = @min(anchor.start, active.start),
            .end = @max(anchor.end, active.end),
        };
    }
};

pub const Location = struct {
    path: []const u8,
    source_start: usize,
    scroll_line: usize,
    scroll_column: u32,
    external: bool = false,
};

pub const App = struct {
    allocator: std.mem.Allocator,
    browser: project_browser.Browser,
    sidebar_visible: bool = true,
    focus: Focus = .sidebar,
    mode: Mode = .normal,
    pinned: ?View = null,
    preview: ?View = null,
    feedback: ?[]const u8 = null,
    /// Startup quote selected once by the terminal adapter and kept across redraws.
    welcome_quote: []const u8 = "",
    history: std.ArrayListUnmanaged(Location) = .empty,
    history_index: ?usize = null,
    sidebar_context: SidebarContext = .project,
    review: ?git_review.Review = null,
    /// Set once at startup: whether the browsed directory is a usable Git repo.
    git_enabled: bool = false,
    git_status: GitStatus = .disabled,
    /// Monotonic owner generation for asynchronous Git snapshots.
    git_generation: u64 = 0,
    /// In the Git context, whether the main view shows a change's source (opened
    /// with `Enter`) rather than its diff.
    viewing_source: bool = false,
    /// Loaded review notes (from `.reviews/`), when a repository is open.
    notes: ?notes_state.Notes = null,
    /// Private bookmarks for this repository, loaded from fiew-owned state.
    bookmarks: ?bookmarks_state.Bookmarks = null,
    bookmarks_available: bool = false,
    /// Trails exist only for the explicitly active named review.
    trails: ?trails_state.Trails = null,
    trails_available: bool = false,
    /// The active composers, when open.
    composer: ?Composer = null,
    bookmark_composer: ?BookmarkComposer = null,
    trail_composer: ?TrailComposer = null,
    /// Trusted ZLS lifecycle is optional and never impairs document viewing.
    zls_status: lsp.Status = .unavailable,
    zls_trusted: bool = false,
    zls_trust_available: bool = false,
    definition_pending: bool = false,
    definition_generation: u64 = 0,
    semantic_operation: lsp.Operation = .definition,
    definition_results: ?definitions_state.Results = null,
    definition_origin_preview: ?View = null,
    hover: ?hover_state.Content = null,

    pub fn init(allocator: std.mem.Allocator, tree: *const project.Tree) !App {
        return .{
            .allocator = allocator,
            .browser = try .init(allocator, tree),
        };
    }

    pub fn deinit(self: *App) void {
        if (self.preview) |*view| view.deinit();
        if (self.pinned) |*view| view.deinit();
        if (self.review) |*review_state| review_state.deinit();
        if (self.notes) |*state_notes| state_notes.deinit();
        if (self.bookmarks) |*state_bookmarks| state_bookmarks.deinit();
        if (self.trails) |*state_trails| state_trails.deinit();
        if (self.composer) |*composer| composer.deinit(self.allocator);
        if (self.bookmark_composer) |*composer| composer.deinit(self.allocator);
        if (self.trail_composer) |*composer| composer.deinit(self.allocator);
        if (self.definition_results) |*results| results.deinit();
        if (self.definition_origin_preview) |*view| view.deinit();
        if (self.hover) |*content| content.deinit();
        for (self.history.items) |location| self.allocator.free(location.path);
        self.history.deinit(self.allocator);
        self.browser.deinit();
        self.* = undefined;
    }

    pub fn beginDefinition(self: *App, operation: lsp.Operation) u64 {
        self.definition_generation +%= 1;
        self.semantic_operation = operation;
        self.definition_pending = true;
        self.feedback = null;
        if (self.definition_results != null or self.definition_origin_preview != null)
            self.dismissDefinitions(true);
        self.dismissHover();
        return self.definition_generation;
    }

    pub fn installHover(self: *App, generation: u64, content: hover_state.Content) bool {
        if (generation != self.definition_generation) {
            var stale = content;
            stale.deinit();
            return false;
        }
        self.dismissHover();
        self.hover = content;
        self.definition_pending = false;
        self.feedback = null;
        return true;
    }

    pub fn dismissHover(self: *App) void {
        if (self.hover) |*content| content.deinit();
        self.hover = null;
    }

    pub fn dismissHoverIfDocumentChanged(self: *App) bool {
        const content = if (self.hover) |*value| value else return false;
        const active = self.activeDocument() orelse {
            self.dismissHover();
            return true;
        };
        if (active.generation == content.document_generation) return false;
        self.dismissHover();
        return true;
    }

    pub fn failDefinition(self: *App, generation: u64, message: []const u8) void {
        if (generation != self.definition_generation) return;
        self.definition_pending = false;
        self.feedback = message;
    }

    pub fn installDefinitions(self: *App, generation: u64, results: definitions_state.Results) bool {
        if (generation != self.definition_generation) {
            var stale = results;
            stale.deinit();
            return false;
        }
        if (self.definition_results) |*previous| previous.deinit();
        self.definition_results = results;
        self.definition_pending = false;
        self.feedback = null;
        return true;
    }

    pub fn prepareDefinitionPreview(self: *App) void {
        if (self.definition_origin_preview != null) return;
        if (self.preview) |view| {
            self.definition_origin_preview = view;
            self.preview = null;
        }
    }

    pub fn dismissDefinitions(self: *App, restore_origin: bool) void {
        if (self.definition_results) |*results| results.deinit();
        self.definition_results = null;
        if (restore_origin) {
            if (self.preview) |*view| view.deinit();
            self.preview = self.definition_origin_preview;
            self.definition_origin_preview = null;
        } else if (self.definition_origin_preview) |*view| {
            view.deinit();
            self.definition_origin_preview = null;
        }
    }

    pub fn pinDefinitionPreview(self: *App) !bool {
        if (self.definition_origin_preview) |origin| {
            const target = self.preview orelse return false;
            self.preview = origin;
            self.definition_origin_preview = null;
            _ = try self.pinPreview();
            self.preview = target;
            return self.pinPreview();
        }
        return self.pinSemanticPreview();
    }

    pub fn cancelDefinition(self: *App) void {
        self.definition_generation +%= 1;
        self.definition_pending = false;
        self.dismissDefinitions(true);
    }

    pub fn showGitSidebar(self: *App) void {
        self.sidebar_context = .git;
        self.focus = .sidebar;
    }

    /// Mark a new asynchronous refresh request and return its generation.
    pub fn beginGitRefresh(self: *App) u64 {
        self.git_generation +%= 1;
        self.git_status = .pending;
        self.feedback = null;
        return self.git_generation;
    }

    pub fn failGitRefresh(self: *App, generation: u64, message: []const u8) void {
        if (generation != self.git_generation) return;
        self.git_status = .stale;
        self.feedback = message;
    }

    /// Show the Git review context with a freshly loaded change set.
    pub fn openReview(self: *App, incoming: git_review.Review) void {
        var review_state = incoming;
        const replacing = self.review != null;
        if (self.review) |*previous| {
            review_state.restorePosition(previous.*);
            previous.deinit();
        }
        self.review = review_state;
        if (!replacing) {
            self.sidebar_context = .git;
            self.focus = .sidebar;
        }
        self.git_status = .idle;
        self.feedback = if (review_state.isEmpty()) "no changes to review" else null;
    }

    /// Return the sidebar to the Project tree.
    pub fn showProjectSidebar(self: *App) void {
        self.sidebar_context = .project;
        self.focus = .sidebar;
    }

    /// Show the Review Threads sidebar.
    pub fn showReviewSidebar(self: *App) void {
        self.sidebar_context = .review;
        self.focus = .sidebar;
    }

    /// Return the selected thread to its matching current Review Diff anchor.
    pub fn showSelectedThreadInDiff(self: *App, viewport_rows: usize) bool {
        const state_notes = if (self.notes) |*value| value else return false;
        const thread = state_notes.threadAt(state_notes.selectedRef() orelse return false);
        const review_state = if (self.review) |*value| value else return false;
        if (!review_state.selectThreadAnchor(thread.group, thread.path, thread.side, thread.start_line, viewport_rows)) return false;
        self.showGitSidebar();
        self.focus = .main;
        self.viewing_source = false;
        return true;
    }

    pub fn showBookmarksSidebar(self: *App) void {
        self.sidebar_context = .bookmarks;
        self.focus = .sidebar;
    }

    pub fn hasBookmarks(self: *const App) bool {
        const state_bookmarks = self.bookmarks orelse return false;
        return state_bookmarks.items.items.len != 0;
    }

    pub fn beginBookmark(self: *App) !bool {
        if (self.sidebar_context == .review) return false;
        var path: []const u8 = undefined;
        var line: usize = 1;
        var column: usize = 0;
        var source_offset: usize = 0;
        if (self.sidebar_context == .git and !self.viewing_source) {
            const review_state = if (self.review) |*value| value else return false;
            const target = review_state.bookmarkTarget() orelse return false;
            path = target.path;
            line = target.line;
        } else {
            const view = self.activeView() orelse return false;
            path = view.snapshot.path;
            if (view.snapshot.graphemes.len != 0) {
                const grapheme = view.snapshot.graphemes[@min(view.active_grapheme, view.snapshot.graphemes.len - 1)];
                line = grapheme.line + 1;
                column = grapheme.visual_column;
                source_offset = grapheme.source.start;
            }
        }
        if (self.bookmark_composer) |*previous| previous.deinit(self.allocator);
        self.bookmark_composer = .{ .target = .{
            .path = try self.allocator.dupe(u8, path),
            .line = line,
            .column = column,
            .source_offset = source_offset,
        } };
        return true;
    }

    pub fn bookmarkComposerInsert(self: *App, codepoint: u21) void {
        const composer = if (self.bookmark_composer) |*value| value else return;
        var buffer: [4]u8 = undefined;
        const length = std.unicode.utf8Encode(codepoint, &buffer) catch return;
        if (composer.buffer.items.len + length > bookmark_model.max_label_bytes) {
            self.feedback = "bookmark label is limited to 48 bytes";
            return;
        }
        composer.buffer.appendSlice(self.allocator, buffer[0..length]) catch return;
        self.feedback = null;
    }

    pub fn bookmarkComposerBackspace(self: *App) void {
        const composer = if (self.bookmark_composer) |*value| value else return;
        if (composer.buffer.items.len == 0) return;
        var start = composer.buffer.items.len - 1;
        while (start > 0 and (composer.buffer.items[start] & 0xc0) == 0x80) start -= 1;
        composer.buffer.shrinkRetainingCapacity(start);
    }

    pub fn cancelBookmarkComposer(self: *App) void {
        if (self.bookmark_composer) |*composer| composer.deinit(self.allocator);
        self.bookmark_composer = null;
    }

    pub fn deleteSelectedBookmark(self: *App) void {
        if (self.bookmarks) |*state_bookmarks| state_bookmarks.deleteSelected();
    }

    pub fn moveBookmarkSelection(self: *App, delta: isize, viewport_rows: usize) void {
        if (self.bookmarks) |*state_bookmarks| state_bookmarks.moveSelection(delta, viewport_rows);
    }

    pub fn hasTrails(self: *const App) bool {
        const state_trails = self.trails orelse return false;
        return state_trails.items.items.len != 0;
    }

    pub fn trailRecording(self: *const App) bool {
        return if (self.trails) |value| value.recording != null else false;
    }

    pub fn captureTrailPoint(self: *App) !?trail_model.Point {
        if (!self.trails_available or self.trails == null or self.sidebar_context == .review or
            (self.sidebar_context == .git and !self.viewing_source)) return null;
        const view = self.activeView() orelse return null;
        if (view.external or view.snapshot.path.len == 0 or view.snapshot.encoding != .utf8) return null;
        const source_offset = if (view.snapshot.graphemes.len == 0) 0 else view.snapshot.graphemes[@min(view.active_grapheme, view.snapshot.graphemes.len - 1)].source.start;
        const line_index = if (view.snapshot.graphemes.len == 0) 0 else view.snapshot.graphemes[@min(view.active_grapheme, view.snapshot.graphemes.len - 1)].line;
        if (line_index >= view.snapshot.lineCount()) return null;
        const start = anchor_model.lineStart(view.snapshot.bytes, source_offset);
        const end = anchor_model.lineEnd(view.snapshot.bytes, source_offset);
        const context = try anchor_model.capture(self.allocator, view.snapshot.bytes, start, end);
        errdefer self.allocator.free(context.bytes);
        const path = try self.allocator.dupe(u8, view.snapshot.path);
        errdefer self.allocator.free(path);
        const content = try self.allocator.dupe(u8, std.mem.trim(u8, view.snapshot.bytes[start..end], " \t\r\n"));
        return .{ .path = path, .line = line_index + 1, .column = if (view.snapshot.graphemes.len == 0) 0 else view.snapshot.graphemes[@min(view.active_grapheme, view.snapshot.graphemes.len - 1)].visual_column, .source_offset = source_offset, .line_offset = source_offset -| context.targetOffset(context.original_start), .content = content, .context = context };
    }

    pub fn startTrailRecording(self: *App) !bool {
        const point = (try self.captureTrailPoint()) orelse return false;
        errdefer trails_state.freePoint(self.allocator, point);
        try self.trails.?.start(point);
        self.feedback = "trail recording started (1 point)";
        return true;
    }

    pub fn addTrailPoint(self: *App) !bool {
        const point = (try self.captureTrailPoint()) orelse return false;
        errdefer trails_state.freePoint(self.allocator, point);
        try self.trails.?.appendPoint(point);
        self.feedback = "trail point added";
        return true;
    }

    pub fn beginTrailComposer(self: *App) bool {
        const state_trails = if (self.trails) |*value| value else return false;
        if (state_trails.pointCount() < 2) {
            self.feedback = "a trail requires at least two points";
            return false;
        }
        if (self.trail_composer) |*previous| previous.deinit(self.allocator);
        self.trail_composer = .{};
        return true;
    }

    pub fn trailComposerInsert(self: *App, codepoint: u21) void {
        const composer = if (self.trail_composer) |*value| value else return;
        var buffer: [4]u8 = undefined;
        const length = std.unicode.utf8Encode(codepoint, &buffer) catch return;
        const target = if (composer.field == .title) &composer.title else &composer.note;
        const limit = if (composer.field == .title) trail_model.max_title_bytes else trail_model.max_note_bytes;
        if (target.items.len + length > limit) {
            self.feedback = if (composer.field == .title) "trail title is limited to 80 bytes" else "trail note is limited to 4096 bytes";
            return;
        }
        target.appendSlice(self.allocator, buffer[0..length]) catch return;
        self.feedback = null;
    }

    pub fn trailComposerNewline(self: *App) void {
        const composer = if (self.trail_composer) |*value| value else return;
        if (composer.field == .title) {
            composer.field = .note;
            return;
        }
        if (composer.note.items.len < trail_model.max_note_bytes) composer.note.append(self.allocator, '\n') catch {};
    }

    pub fn trailComposerBackspace(self: *App) void {
        const composer = if (self.trail_composer) |*value| value else return;
        const target = if (composer.field == .title) &composer.title else &composer.note;
        if (target.items.len == 0) return;
        var start = target.items.len - 1;
        while (start > 0 and (target.items[start] & 0xc0) == 0x80) start -= 1;
        target.shrinkRetainingCapacity(start);
    }

    pub fn cancelTrailComposer(self: *App) void {
        if (self.trail_composer) |*composer| composer.deinit(self.allocator);
        self.trail_composer = null;
        self.feedback = "trail composition cancelled; recording resumed";
    }

    pub fn saveTrailComposer(self: *App) !bool {
        const composer = if (self.trail_composer) |*value| value else return false;
        if (!trail_model.validTitle(composer.title.items)) {
            self.feedback = "trail title is required and limited to 80 bytes";
            return false;
        }
        try self.trails.?.saveDraft(composer.title.items, composer.note.items);
        composer.deinit(self.allocator);
        self.trail_composer = null;
        return true;
    }

    pub fn hasNotes(self: *const App) bool {
        const state_notes = self.notes orelse return false;
        return state_notes.total() != 0;
    }

    /// Begin composing a new note anchored to the current Git diff selection.
    /// Returns false when there is nothing textual selected to annotate.
    pub fn beginNoteFromDiff(self: *App) !bool {
        const review_state = if (self.review) |*value| value else return false;
        const draft = (try review_state.captureAnchor(self.allocator)) orelse return false;
        errdefer self.allocator.free(draft.excerpt);
        errdefer self.allocator.free(draft.context.bytes);
        const path = try self.allocator.dupe(u8, draft.path);
        errdefer self.allocator.free(path);
        const blob = if (draft.blob) |value| try self.allocator.dupe(u8, value) else null;
        self.setComposer(.{ .anchor = .{
            .path = path,
            .group = draft.group,
            .side = draft.side,
            .start_line = draft.start_line,
            .end_line = draft.end_line,
            .blob = blob,
            .excerpt = draft.excerpt,
            .context = draft.context,
        } });
        return true;
    }

    /// Begin a file-anchored thread for the selected Git change.
    pub fn beginThreadFromFile(self: *App) !bool {
        const review_state = if (self.review) |*value| value else return false;
        const index = review_state.selectedChange() orelse return false;
        const change = review_state.changeset.changes[index];
        const fingerprint = try git_review.changeFingerprint(self.allocator, change, review_state.changeset.diffs[index]);
        errdefer self.allocator.free(fingerprint);
        self.setComposer(.{ .anchor = .{
            .path = try self.allocator.dupe(u8, change.path),
            .group = change.group,
            .context = .{ .bytes = fingerprint, .original_start = 0, .target_start = 0, .target_end = fingerprint.len },
        } });
        return true;
    }

    /// Begin appending a reviewer comment to the selected thread.
    pub fn beginThreadReply(self: *App) bool {
        const state_notes = if (self.notes) |*value| value else return false;
        if (state_notes.selectedRef() == null) return false;
        self.setComposer(.{});
        return true;
    }

    pub fn composerInsert(self: *App, codepoint: u21) void {
        const composer = if (self.composer) |*value| value else return;
        var buffer: [4]u8 = undefined;
        const length = std.unicode.utf8Encode(codepoint, &buffer) catch return;
        composer.buffer.appendSlice(self.allocator, buffer[0..length]) catch return;
        composer.modified = true;
        composer.discard_armed = false;
    }

    pub fn composerNewline(self: *App) void {
        const composer = if (self.composer) |*value| value else return;
        composer.buffer.append(self.allocator, '\n') catch return;
        composer.modified = true;
        composer.discard_armed = false;
    }

    pub fn composerBackspace(self: *App) void {
        const composer = if (self.composer) |*value| value else return;
        if (composer.buffer.items.len == 0) return;
        var start = composer.buffer.items.len - 1;
        while (start > 0 and (composer.buffer.items[start] & 0xc0) == 0x80) start -= 1;
        composer.buffer.shrinkRetainingCapacity(start);
        composer.modified = true;
        composer.discard_armed = false;
    }

    pub fn cancelComposer(self: *App) void {
        if (self.composer) |*composer| composer.deinit(self.allocator);
        self.composer = null;
    }

    pub fn resolveSelectedNote(self: *App) void {
        if (self.notes) |*state_notes| state_notes.toggleResolved();
    }

    pub fn deleteSelectedNote(self: *App) !void {
        if (self.notes) |*state_notes| try state_notes.deleteSelected(.reviewer);
    }

    pub fn moveNoteSelection(self: *App, delta: isize, viewport_rows: usize) void {
        if (self.notes) |*state_notes| state_notes.moveSelection(delta, viewport_rows);
    }

    fn setComposer(self: *App, composer: Composer) void {
        if (self.composer) |*previous| previous.deinit(self.allocator);
        self.composer = composer;
    }

    pub fn activeView(self: *const App) ?*const View {
        if (self.preview) |*view| return view;
        if (self.pinned) |*view| return view;
        return null;
    }

    pub fn activeViewMut(self: *App) ?*View {
        if (self.preview) |*view| return view;
        if (self.pinned) |*view| return view;
        return null;
    }

    pub fn activeDocument(self: *const App) ?*const document.Snapshot {
        const view = self.activeView() orelse return null;
        return &view.snapshot;
    }

    pub fn showPreview(self: *App, snapshot: document.Snapshot) void {
        if (self.preview) |*previous| previous.deinit();
        self.preview = .{ .snapshot = snapshot };
        self.feedback = null;
    }

    pub fn positionPreviewAtLine(self: *App, one_based_line: usize, column: usize) void {
        const view = if (self.preview) |*value| value else return;
        const line = one_based_line -| 1;
        const source_start = if (line < view.snapshot.line_starts.len) view.snapshot.line_starts[line] else 0;
        view.active_grapheme = graphemeAtSource(view.snapshot, source_start);
        const range = view.snapshot.graphemeRangeForLine(@min(line, view.snapshot.lineCount() -| 1));
        for (range.start..range.end) |index| {
            view.active_grapheme = index;
            if (view.snapshot.graphemes[index].visual_column >= column) break;
        }
        view.anchor_grapheme = view.active_grapheme;
        view.preferred_column = @intCast(column);
        view.scroll_line = line -| 3;
    }

    pub fn clearPreview(self: *App) void {
        if (self.preview) |*view| view.deinit();
        self.preview = null;
        self.feedback = null;
    }

    /// Publish a completely loaded replacement while preserving the current
    /// source position and scroll. The previous immutable snapshot remains
    /// active until this infallible swap.
    pub fn replaceActiveSnapshot(self: *App, snapshot: document.Snapshot) bool {
        const target = if (self.preview) |*view| view else if (self.pinned) |*view| view else {
            var owned = snapshot;
            owned.deinit();
            return false;
        };
        const source_start = if (target.snapshot.graphemes.len == 0)
            0
        else
            target.snapshot.graphemes[@min(target.active_grapheme, target.snapshot.graphemes.len - 1)].source.start;
        var replacement: View = .{
            .snapshot = snapshot,
            .scroll_line = target.scroll_line,
            .scroll_column = target.scroll_column,
            .external = target.external,
        };
        replacement.active_grapheme = graphemeAtSource(replacement.snapshot, source_start);
        replacement.anchor_grapheme = replacement.active_grapheme;
        if (replacement.snapshot.graphemes.len != 0)
            replacement.preferred_column = replacement.snapshot.graphemes[replacement.active_grapheme].visual_column;
        var previous = target.*;
        target.* = replacement;
        previous.deinit();
        self.feedback = null;
        return true;
    }

    pub fn pinPreview(self: *App) !bool {
        if (self.preview == null) return false;
        try self.syncCurrentHistory();
        if (self.pinned) |*view| view.deinit();
        const pinned = self.preview.?;
        self.preview = null;
        self.pinned = pinned;
        self.focus = .main;
        self.mode = .normal;
        try self.appendPinnedLocation();
        return true;
    }

    pub fn pinSemanticPreview(self: *App) !bool {
        if (self.preview == null) return false;
        // A semantic jump may begin from a pinned view established outside the
        // history list. Capture that origin exactly once before replacing it.
        if (self.history_index == null and self.pinned != null) try self.appendPinnedLocation();
        return self.pinPreview();
    }

    pub fn installHistorySnapshot(self: *App, snapshot: document.Snapshot, location: Location) void {
        self.clearPreview();
        if (self.pinned) |*view| view.deinit();
        self.pinned = .{ .snapshot = snapshot, .external = location.external };
        const view = &self.pinned.?;
        view.active_grapheme = graphemeAtSource(view.snapshot, location.source_start);
        view.anchor_grapheme = view.active_grapheme;
        if (view.snapshot.graphemes.len != 0) {
            view.preferred_column = view.snapshot.graphemes[view.active_grapheme].visual_column;
        }
        view.scroll_line = location.scroll_line;
        view.scroll_column = location.scroll_column;
        self.focus = .main;
        self.mode = .normal;
    }

    pub fn historyBack(self: *App) !?Location {
        const current = self.history_index orelse return null;
        if (current == 0) {
            self.feedback = "start of location history";
            return null;
        }
        try self.syncCurrentHistory();
        self.history_index = current - 1;
        self.feedback = null;
        return self.history.items[current - 1];
    }

    pub fn historyForward(self: *App) !?Location {
        const current = self.history_index orelse return null;
        if (current + 1 >= self.history.items.len) {
            self.feedback = "end of location history";
            return null;
        }
        try self.syncCurrentHistory();
        self.history_index = current + 1;
        self.feedback = null;
        return self.history.items[current + 1];
    }

    pub fn toggleFocus(self: *App) void {
        self.focus = switch (self.focus) {
            .sidebar => .main,
            .main => .sidebar,
        };
    }

    pub fn toggleActiveExtend(self: *App) void {
        if (self.sidebar_context == .git and !self.viewing_source) {
            const review_state = if (self.review) |*value| value else return;
            self.mode = switch (self.mode) {
                .normal => mode: {
                    if (review_state.diff_anchor == null) review_state.diff_anchor = review_state.diff_line;
                    break :mode .extend;
                },
                .extend => mode: {
                    _ = review_state.clearDiffSelection();
                    break :mode .normal;
                },
                .command => .command,
            };
            return;
        }
        self.toggleExtend();
    }

    pub fn toggleExtend(self: *App) void {
        self.mode = switch (self.mode) {
            .normal => .extend,
            .extend => .normal,
            .command => .command,
        };
        if (self.mode == .normal) self.collapseSelection();
    }

    pub fn leaveExtend(self: *App) void {
        if (self.mode != .extend) return;
        self.mode = .normal;
        if (self.clearActiveSelection()) return;
        self.collapseSelection();
    }

    /// Clear an explicit selection while retaining the active cursor. Document
    /// views are selection-first and therefore always retain a collapsed range.
    pub fn clearActiveSelection(self: *App) bool {
        if (self.sidebar_context == .git and !self.viewing_source) {
            if (self.review) |*review_state| return review_state.clearDiffSelection();
        }
        return false;
    }

    pub fn collapseSelection(self: *App) void {
        if (self.sidebar_context == .git and !self.viewing_source) {
            if (self.review) |*review_state| review_state.collapseDiffSelection();
            return;
        }
        const view = self.activeViewMut() orelse return;
        view.anchor_grapheme = view.active_grapheme;
    }

    pub fn reverseSelection(self: *App) void {
        if (self.sidebar_context == .git and !self.viewing_source) {
            if (self.review) |*review_state| review_state.reverseDiffSelection();
            return;
        }
        const view = self.activeViewMut() orelse return;
        std.mem.swap(usize, &view.anchor_grapheme, &view.active_grapheme);
        if (view.snapshot.graphemes.len != 0) {
            view.preferred_column = view.snapshot.graphemes[view.active_grapheme].visual_column;
        }
    }

    pub fn selectActiveLine(self: *App, viewport_rows: usize) void {
        if (self.sidebar_context == .git and !self.viewing_source) {
            if (self.review) |*review_state| review_state.selectDiffLine(viewport_rows);
            return;
        }
        self.selectLine();
    }

    pub fn selectLine(self: *App) void {
        const view = self.activeViewMut() orelse return;
        if (view.snapshot.graphemes.len == 0) return;
        const last = view.snapshot.graphemes.len - 1;
        const anchor = @min(view.anchor_grapheme, last);
        const active = @min(view.active_grapheme, last);
        const top_line = @min(view.snapshot.graphemes[anchor].line, view.snapshot.graphemes[active].line);
        const bottom_line = @max(view.snapshot.graphemes[anchor].line, view.snapshot.graphemes[active].line);

        const top_range = view.snapshot.graphemeRangeForLine(top_line);
        const bottom_range = view.snapshot.graphemeRangeForLine(bottom_line);
        if (top_range.start == top_range.end or bottom_range.start == bottom_range.end) return;

        // When the selection already spans whole lines, another `x` reaches down
        // to swallow the next line; otherwise it snaps to the current line(s).
        const lo = @min(anchor, active);
        const hi = @max(anchor, active);
        const spans_full_lines = lo == top_range.start and hi == bottom_range.end - 1;
        var end_range = bottom_range;
        if (spans_full_lines and bottom_line + 1 < view.snapshot.lineCount()) {
            const next = view.snapshot.graphemeRangeForLine(bottom_line + 1);
            if (next.start != next.end) end_range = next;
        }

        view.anchor_grapheme = top_range.start;
        view.active_grapheme = end_range.end - 1;
        view.preferred_column = view.snapshot.graphemes[view.active_grapheme].visual_column;
    }

    pub fn moveHorizontal(self: *App, delta: isize, viewport_width: usize) void {
        const view = self.activeViewMut() orelse return;
        if (view.snapshot.graphemes.len == 0) return;
        const current: isize = @intCast(view.active_grapheme);
        const last: isize = @intCast(view.snapshot.graphemes.len - 1);
        const target: usize = @intCast(std.math.clamp(current + delta, 0, last));
        self.applyMovement(target, viewport_width);
    }

    pub fn moveVertical(
        self: *App,
        delta: isize,
        viewport_height: usize,
        viewport_width: usize,
    ) void {
        const view = self.activeView() orelse return;
        if (view.snapshot.graphemes.len == 0) return;
        const current = view.snapshot.graphemes[@min(view.active_grapheme, view.snapshot.graphemes.len - 1)];
        const line_count = view.snapshot.lineCount();

        // Step `delta` visible lines, skipping lines hidden by collapsed folds.
        var target_line = current.line;
        const direction: isize = if (delta < 0) -1 else 1;
        var remaining = @abs(delta);
        while (remaining > 0) : (remaining -= 1) {
            const next = view.stepVisibleLine(target_line, direction, line_count) orelse break;
            target_line = next;
        }

        var best_index = view.active_grapheme;
        var fallback_index: ?usize = null;
        var best_distance: u32 = std.math.maxInt(u32);
        const range = view.snapshot.graphemeRangeForLine(target_line);
        for (view.snapshot.graphemes[range.start..range.end], range.start..) |grapheme, index| {
            if (grapheme.width == 0) {
                fallback_index = index;
                continue;
            }
            const distance = if (grapheme.visual_column > view.preferred_column)
                grapheme.visual_column - view.preferred_column
            else
                view.preferred_column - grapheme.visual_column;
            if (distance < best_distance) {
                best_distance = distance;
                best_index = index;
            }
        }
        if (best_distance == std.math.maxInt(u32)) {
            if (fallback_index) |index| best_index = index;
        }
        self.applyMovementPreservingColumn(best_index, viewport_height, viewport_width);
    }

    /// Vertical movement in the main view, routed to the diff cursor when the
    /// Git review is showing a diff rather than a source document.
    pub fn mainVerticalMove(self: *App, delta: isize, viewport_height: usize, viewport_width: usize) void {
        if (self.sidebar_context == .git and !self.viewing_source) {
            if (self.review) |*review_state| {
                review_state.moveDiffLine(delta, viewport_height);
                if (self.mode != .extend) _ = review_state.clearDiffSelection();
            }
            return;
        }
        if (self.sidebar_context == .review) {
            if (self.notes) |*threads| threads.scrollDetail(delta);
            return;
        }
        self.moveVertical(delta, viewport_height, viewport_width);
    }

    /// Page through visual Diff rows so wrapped comments remain reachable.
    pub fn mainPageMove(self: *App, delta: isize, viewport_height: usize, viewport_width: usize) void {
        if (self.sidebar_context == .git and !self.viewing_source) {
            if (self.review) |*review_state| review_state.scrollDiffVisual(delta);
            return;
        }
        self.mainVerticalMove(delta, viewport_height, viewport_width);
    }

    /// Attach syntax analysis to the active view, taking ownership of `data`.
    pub fn installParseData(self: *App, data: syntax.ParseData) void {
        const view = self.activeViewMut() orelse {
            var owned = data;
            owned.deinit();
            return;
        };
        view.setSyntax(data);
    }

    /// Attach analysis to whichever open view still holds the snapshot it was
    /// computed for. Data for a superseded snapshot is dropped.
    pub fn installParseDataForGeneration(self: *App, data: syntax.ParseData, generation: u64) void {
        if (self.preview) |*view| {
            if (view.snapshot.generation == generation) return view.setSyntax(data);
        }
        if (self.pinned) |*view| {
            if (view.snapshot.generation == generation) return view.setSyntax(data);
        }
        var owned = data;
        owned.deinit();
    }

    pub fn foldsAvailable(self: *const App) bool {
        const view = self.activeView() orelse return false;
        const data = view.syntax orelse return false;
        return data.folds.len != 0;
    }

    pub fn outlineAvailable(self: *const App) bool {
        const view = self.activeView() orelse return false;
        const data = view.syntax orelse return false;
        return data.outline.nodes.len != 0;
    }

    pub fn foldClose(self: *App) void {
        const view = self.activeViewMut() orelse return;
        const data = view.syntax orelse return;
        const line = cursorLine(view);
        const index = data.foldContaining(line) orelse {
            self.feedback = "no fold at cursor";
            return;
        };
        const start = data.folds[index].start_line;
        self.addClosedFold(view, start) catch return;
        self.moveActiveToLine(start);
    }

    pub fn foldOpen(self: *App) void {
        const view = self.activeViewMut() orelse return;
        const line = cursorLine(view);
        if (!self.removeClosedFold(view, line)) self.feedback = "no closed fold at cursor";
    }

    pub fn foldToggle(self: *App) void {
        const view = self.activeViewMut() orelse return;
        const line = cursorLine(view);
        if (self.removeClosedFold(view, line)) return;
        self.foldClose();
    }

    pub fn foldCloseAll(self: *App) void {
        const view = self.activeViewMut() orelse return;
        const data = view.syntax orelse return;
        for (data.folds) |fold| {
            if (fold.isFoldable()) self.addClosedFold(view, fold.start_line) catch return;
        }
        const line = cursorLine(view);
        if (view.isLineHidden(line)) self.moveActiveToVisibleLine(line);
    }

    pub fn foldOpenAll(self: *App) void {
        const view = self.activeViewMut() orelse return;
        view.closed_folds.clearRetainingCapacity();
    }

    /// Move the selection toward a structural relation of the enclosing node.
    pub fn structuralMove(self: *App, move: StructuralMove) void {
        const view = self.activeViewMut() orelse return;
        const data = view.syntax orelse {
            self.feedback = "no structure available";
            return;
        };
        const here = data.outline.enclosing(view.selection()) orelse {
            self.feedback = "no node at cursor";
            return;
        };
        const target = switch (move) {
            .parent => data.outline.parent(here),
            .child => data.outline.firstChild(here),
            .next_sibling => data.outline.nextSibling(here),
            .previous_sibling => data.outline.prevSibling(here),
        } orelse {
            self.feedback = switch (move) {
                .parent => "no enclosing node",
                .child => "no child node",
                .next_sibling => "no next node",
                .previous_sibling => "no previous node",
            };
            return;
        };
        self.moveActiveToSource(data.outline.nodes[target].source.start);
    }

    fn addClosedFold(self: *App, view: *View, start_line: usize) !void {
        for (view.closed_folds.items) |existing| if (existing == start_line) return;
        try view.closed_folds.append(self.allocator, start_line);
    }

    fn removeClosedFold(self: *App, view: *View, start_line: usize) bool {
        _ = self;
        for (view.closed_folds.items, 0..) |existing, index| {
            if (existing == start_line) {
                _ = view.closed_folds.orderedRemove(index);
                return true;
            }
        }
        return false;
    }

    fn moveActiveToLine(self: *App, line: usize) void {
        const view = self.activeViewMut() orelse return;
        if (view.snapshot.graphemes.len == 0) return;
        const range = view.snapshot.graphemeRangeForLine(line);
        const target = @min(range.start, view.snapshot.graphemes.len - 1);
        view.active_grapheme = target;
        view.anchor_grapheme = target;
        view.preferred_column = view.snapshot.graphemes[target].visual_column;
    }

    fn moveActiveToVisibleLine(self: *App, line: usize) void {
        const view = self.activeView() orelse return;
        // Snap to the start of the outermost collapsed fold covering `line`.
        const data = view.syntax orelse return;
        var target = line;
        for (view.closed_folds.items) |start| {
            const fold = foldWithStart(data.folds, start) orelse continue;
            if (line > fold.start_line and line <= fold.end_line and fold.start_line < target) {
                target = fold.start_line;
            }
        }
        self.moveActiveToLine(target);
    }

    fn moveActiveToSource(self: *App, source_start: usize) void {
        const view = self.activeViewMut() orelse return;
        if (view.snapshot.graphemes.len == 0) return;
        const target = graphemeAtSource(view.snapshot, source_start);
        view.active_grapheme = target;
        view.anchor_grapheme = target;
        view.preferred_column = view.snapshot.graphemes[target].visual_column;
    }

    fn cursorLine(view: *const View) usize {
        if (view.snapshot.graphemes.len == 0) return 0;
        return view.snapshot.graphemes[@min(view.active_grapheme, view.snapshot.graphemes.len - 1)].line;
    }

    pub fn moveWordForward(self: *App, to_end: bool, viewport_width: usize) void {
        const view = self.activeView() orelse return;
        if (view.snapshot.graphemes.len == 0) return;
        var index = view.active_grapheme;
        if (to_end) {
            while (index < view.snapshot.graphemes.len and wordClass(view.snapshot, index) != .word) : (index += 1) {}
            if (index >= view.snapshot.graphemes.len) index = view.snapshot.graphemes.len - 1;
            while (index + 1 < view.snapshot.graphemes.len and
                wordClass(view.snapshot, index + 1) == .word) : (index += 1)
            {}
        } else {
            while (index < view.snapshot.graphemes.len and wordClass(view.snapshot, index) == .word) : (index += 1) {}
            while (index < view.snapshot.graphemes.len and wordClass(view.snapshot, index) != .word) : (index += 1) {}
            if (index >= view.snapshot.graphemes.len) index = view.snapshot.graphemes.len - 1;
        }
        self.applyMovement(index, viewport_width);
    }

    pub fn moveWordBackward(self: *App, viewport_width: usize) void {
        const view = self.activeView() orelse return;
        if (view.snapshot.graphemes.len == 0) return;
        var index = view.active_grapheme;
        if (index > 0) index -= 1;
        while (index > 0 and wordClass(view.snapshot, index) != .word) : (index -= 1) {}
        while (index > 0 and wordClass(view.snapshot, index - 1) == .word) : (index -= 1) {}
        self.applyMovement(index, viewport_width);
    }

    pub fn moveDocumentBoundary(self: *App, end: bool, viewport_height: usize, viewport_width: usize) void {
        const view = self.activeView() orelse return;
        if (view.snapshot.graphemes.len == 0) return;
        const preferred_column = view.preferred_column;
        var line = if (end) view.snapshot.lineCount() - 1 else 0;
        var target: ?usize = null;
        while (true) {
            target = nearestGraphemeOnLine(view.snapshot, line, preferred_column);
            if (target != null) break;
            if (end) {
                if (line == 0) break;
                line -= 1;
            } else {
                if (line + 1 >= view.snapshot.lineCount()) break;
                line += 1;
            }
        }
        self.applyMovementPreservingColumn(
            target orelse return,
            viewport_height,
            viewport_width,
        );
        const active_view = self.activeViewMut().?;
        active_view.scroll_line = if (end)
            active_view.snapshot.lineCount() -| viewport_height
        else
            0;
    }

    pub fn selection(self: *const App) document.ByteRange {
        const view = self.activeView() orelse return .{ .start = 0, .end = 0 };
        return view.selection();
    }

    pub fn selectAtVisualPosition(
        self: *App,
        line: usize,
        visual_column: u32,
        extend: bool,
        viewport_height: usize,
        viewport_width: usize,
    ) void {
        const view = self.activeView() orelse return;
        if (view.snapshot.graphemes.len == 0) return;
        const range = view.snapshot.graphemeRangeForLine(line);
        if (range.start == range.end) return;
        var target = range.start;
        var best_distance: u32 = std.math.maxInt(u32);
        for (view.snapshot.graphemes[range.start..range.end], range.start..) |grapheme, index| {
            const distance = if (grapheme.visual_column > visual_column)
                grapheme.visual_column - visual_column
            else
                visual_column - grapheme.visual_column;
            if (distance < best_distance) {
                best_distance = distance;
                target = index;
            }
        }
        const active_view = self.activeViewMut().?;
        active_view.active_grapheme = target;
        if (!extend) active_view.anchor_grapheme = target;
        active_view.preferred_column = active_view.snapshot.graphemes[target].visual_column;
        self.mode = if (extend) .extend else .normal;
        self.ensureDocumentVisible(line, viewport_height);
        self.ensureDocumentHorizontallyVisible(viewport_width);
    }

    pub fn ensureCurrentDocumentVisible(self: *App, viewport_height: usize, viewport_width: usize) void {
        const view = self.activeView() orelse return;
        if (view.snapshot.graphemes.len == 0) return;
        const line = view.snapshot.graphemes[@min(view.active_grapheme, view.snapshot.graphemes.len - 1)].line;
        self.ensureDocumentVisible(line, viewport_height);
        self.ensureDocumentHorizontallyVisible(viewport_width);
    }

    fn applyMovement(self: *App, target: usize, viewport_width: usize) void {
        const mode = self.mode;
        const view = self.activeViewMut() orelse return;
        view.active_grapheme = target;
        if (mode != .extend) view.anchor_grapheme = target;
        view.preferred_column = view.snapshot.graphemes[target].visual_column;
        self.ensureDocumentHorizontallyVisible(viewport_width);
    }

    fn applyMovementPreservingColumn(
        self: *App,
        target: usize,
        viewport_height: usize,
        viewport_width: usize,
    ) void {
        const mode = self.mode;
        const view = self.activeViewMut() orelse return;
        view.active_grapheme = target;
        if (mode != .extend) view.anchor_grapheme = target;
        const line = view.snapshot.graphemes[target].line;
        self.ensureDocumentVisible(line, viewport_height);
        self.ensureDocumentHorizontallyVisible(viewport_width);
    }

    fn ensureDocumentHorizontallyVisible(self: *App, viewport_width: usize) void {
        const view = self.activeViewMut() orelse return;
        if (view.snapshot.graphemes.len == 0 or viewport_width == 0) return;
        const selected = view.snapshot.graphemes[@min(view.active_grapheme, view.snapshot.graphemes.len - 1)];
        if (selected.visual_column < view.scroll_column) {
            view.scroll_column = selected.visual_column;
            return;
        }
        const end = selected.visual_column + @max(selected.width, 1);
        const width: u32 = @intCast(viewport_width);
        if (end > view.scroll_column + width) view.scroll_column = end - width;
    }

    fn ensureDocumentVisible(self: *App, line: usize, viewport_height: usize) void {
        const view = self.activeViewMut() orelse return;
        if (viewport_height == 0) return;
        if (line <= view.scroll_line) {
            view.scroll_line = line;
            return;
        }
        // Measure the viewport in visible lines, not raw line numbers, so
        // stepping past a collapsed region does not scroll the whole fold into
        // view. `line` is already visible.
        const line_count = view.snapshot.lineCount();
        var last_visible = view.scroll_line;
        var forward = viewport_height - 1;
        while (forward > 0) : (forward -= 1) {
            last_visible = view.stepVisibleLine(last_visible, 1, line_count) orelse break;
        }
        if (line <= last_visible) return;
        // Scroll down just enough to make `line` the last visible row.
        var top = line;
        var backward = viewport_height - 1;
        while (backward > 0) : (backward -= 1) {
            top = view.stepVisibleLine(top, -1, line_count) orelse break;
        }
        view.scroll_line = top;
    }

    fn syncCurrentHistory(self: *App) !void {
        const index = self.history_index orelse return;
        const view = self.pinned orelse return;
        if (index >= self.history.items.len) return;
        const selected_range = view.selection();
        self.history.items[index].source_start = selected_range.start;
        self.history.items[index].scroll_line = view.scroll_line;
        self.history.items[index].scroll_column = view.scroll_column;
        self.history.items[index].external = view.external;
    }

    fn appendPinnedLocation(self: *App) !void {
        const view = self.pinned orelse return;
        if (self.history_index) |index| {
            var remove_index = index + 1;
            while (remove_index < self.history.items.len) {
                self.allocator.free(self.history.items[remove_index].path);
                remove_index += 1;
            }
            self.history.shrinkRetainingCapacity(index + 1);
        }
        const selected_range = view.selection();
        const owned_path = try self.allocator.dupe(u8, view.snapshot.path);
        self.history.append(self.allocator, .{
            .path = owned_path,
            .source_start = selected_range.start,
            .scroll_line = view.scroll_line,
            .scroll_column = view.scroll_column,
            .external = view.external,
        }) catch |err| {
            self.allocator.free(owned_path);
            return err;
        };
        self.history_index = self.history.items.len - 1;
    }

    fn nearestGraphemeOnLine(
        snapshot: document.Snapshot,
        line: usize,
        preferred_column: u32,
    ) ?usize {
        const range = snapshot.graphemeRangeForLine(line);
        if (range.start == range.end) return null;
        var target: ?usize = null;
        var fallback: ?usize = null;
        var best_distance: u32 = std.math.maxInt(u32);
        for (snapshot.graphemes[range.start..range.end], range.start..) |grapheme, index| {
            if (grapheme.width == 0) {
                fallback = index;
                continue;
            }
            const distance = if (grapheme.visual_column > preferred_column)
                grapheme.visual_column - preferred_column
            else
                preferred_column - grapheme.visual_column;
            if (distance < best_distance) {
                best_distance = distance;
                target = index;
            }
        }
        return target orelse fallback;
    }

    fn graphemeAtSource(snapshot: document.Snapshot, source_start: usize) usize {
        for (snapshot.graphemes, 0..) |grapheme, index| {
            if (grapheme.source.start >= source_start or
                (source_start >= grapheme.source.start and source_start < grapheme.source.end)) return index;
        }
        return snapshot.graphemes.len -| 1;
    }

    const WordClass = enum { whitespace, word, punctuation };

    fn wordClass(snapshot: document.Snapshot, index: usize) WordClass {
        const grapheme = snapshot.graphemes[@min(index, snapshot.graphemes.len - 1)];
        const bytes = snapshot.display_bytes[grapheme.display.start..grapheme.display.end];
        if (bytes.len == 0) return .whitespace;
        const sequence_length = std.unicode.utf8ByteSequenceLength(bytes[0]) catch return .punctuation;
        const codepoint = std.unicode.utf8Decode(bytes[0..sequence_length]) catch return .punctuation;
        if (std.ascii.isWhitespace(@intCast(@min(codepoint, 0x7f)))) return .whitespace;
        if (codepoint == '_' or (codepoint < 128 and std.ascii.isAlphanumeric(@intCast(codepoint))) or
            codepoint >= 128) return .word;
        return .punctuation;
    }
};

fn foldWithStart(folds: []const syntax.FoldRange, start_line: usize) ?syntax.FoldRange {
    for (folds) |fold| if (fold.start_line == start_line) return fold;
    return null;
}

fn testSnapshot(path: []const u8, bytes: []const u8) !document.Snapshot {
    return document.Snapshot.init(
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

fn testApp() !App {
    const Static = struct {
        var nodes = [_]project.Node{.{ .path = "a.txt", .depth = 1, .kind = .file }};
        var tree: project.Tree = .{
            .allocator = std.testing.allocator,
            .nodes = &nodes,
            .file_count = 1,
        };
    };
    return App.init(std.testing.allocator, &Static.tree);
}

test "Git refresh preserves the selected changed file and sidebar scroll" {
    const Fixture = struct {
        fn changeset() !git.ChangeSet {
            const changes = try std.testing.allocator.alloc(git.Change, 2);
            changes[0] = .{
                .group = .unstaged,
                .kind = .modified,
                .content = .text,
                .path = try std.testing.allocator.dupe(u8, "a.zig"),
            };
            changes[1] = .{
                .group = .unstaged,
                .kind = .modified,
                .content = .text,
                .path = try std.testing.allocator.dupe(u8, "b.zig"),
            };
            const diffs = try std.testing.allocator.alloc(git.FileDiff, 2);
            for (diffs) |*diff| diff.* = .{
                .allocator = std.testing.allocator,
                .text = try std.testing.allocator.alloc(u8, 0),
                .hunks = try std.testing.allocator.alloc(git.Hunk, 0),
                .lines = try std.testing.allocator.alloc(git.DiffLine, 0),
            };
            return .{ .allocator = std.testing.allocator, .changes = changes, .diffs = diffs };
        }
    };

    var app = try testApp();
    defer app.deinit();
    app.openReview(try git_review.Review.init(std.testing.allocator, try Fixture.changeset()));
    app.review.?.moveSelection(1, 1);
    app.focus = .main;
    try std.testing.expectEqualStrings("b.zig", app.review.?.changeset.changes[app.review.?.selectedChange().?].path);
    try std.testing.expectEqual(@as(usize, 2), app.review.?.scroll);

    _ = app.beginGitRefresh();
    try std.testing.expectEqual(Focus.main, app.focus);
    app.openReview(try git_review.Review.init(std.testing.allocator, try Fixture.changeset()));

    try std.testing.expectEqualStrings("b.zig", app.review.?.changeset.changes[app.review.?.selectedChange().?].path);
    try std.testing.expectEqual(@as(usize, 2), app.review.?.scroll);
    try std.testing.expectEqual(Focus.main, app.focus);
}

test "completed reload replaces the snapshot and preserves source location" {
    var app = try testApp();
    defer app.deinit();
    app.pinned = .{ .snapshot = try testSnapshot("reload.txt", "old text\nsecond"), .active_grapheme = 5, .anchor_grapheme = 5, .scroll_line = 1 };

    try std.testing.expect(app.replaceActiveSnapshot(try testSnapshot("reload.txt", "new text\nsecond")));
    try std.testing.expectEqualStrings("new text\nsecond", app.activeDocument().?.bytes);
    try std.testing.expectEqual(@as(usize, 5), app.activeView().?.active_grapheme);
    try std.testing.expectEqual(@as(usize, 1), app.activeView().?.scroll_line);
}

test "preview cancellation restores the pinned selection and scroll" {
    var app = try testApp();
    defer app.deinit();
    app.pinned = .{ .snapshot = try testSnapshot("pinned.txt", "abcdef"), .active_grapheme = 3, .anchor_grapheme = 3, .scroll_column = 2 };
    app.showPreview(try testSnapshot("preview.txt", "preview"));
    app.moveHorizontal(2, 20);
    app.clearPreview();

    try std.testing.expectEqualStrings("pinned.txt", app.activeDocument().?.path);
    try std.testing.expectEqual(@as(usize, 3), app.activeView().?.active_grapheme);
    try std.testing.expectEqual(@as(u32, 2), app.activeView().?.scroll_column);
}

test "extend movement preserves anchor and escape collapses to active" {
    var app = try testApp();
    defer app.deinit();
    app.pinned = .{ .snapshot = try testSnapshot("a.txt", "abcdef") };
    app.toggleExtend();
    app.moveHorizontal(3, 20);

    try std.testing.expectEqual(Mode.extend, app.mode);
    try std.testing.expectEqual(document.ByteRange{ .start = 0, .end = 4 }, app.selection());
    app.leaveExtend();
    try std.testing.expectEqual(Mode.normal, app.mode);
    try std.testing.expectEqual(document.ByteRange{ .start = 3, .end = 4 }, app.selection());
}

test "pinning and history preserve source locations" {
    var app = try testApp();
    defer app.deinit();
    app.showPreview(try testSnapshot("first.txt", "first"));
    try std.testing.expect(try app.pinPreview());
    app.moveHorizontal(2, 20);
    app.showPreview(try testSnapshot("second.txt", "second"));
    try std.testing.expect(try app.pinPreview());

    const previous = (try app.historyBack()).?;
    try std.testing.expectEqualStrings("first.txt", previous.path);
    try std.testing.expectEqual(@as(usize, 2), previous.source_start);
    app.installHistorySnapshot(try testSnapshot("first.txt", "first"), previous);
    try std.testing.expectEqual(@as(usize, 2), app.activeView().?.active_grapheme);

    const next = (try app.historyForward()).?;
    try std.testing.expectEqualStrings("second.txt", next.path);
    app.installHistorySnapshot(try testSnapshot("second.txt", "second"), next);
    try std.testing.expectEqualStrings("second.txt", app.activeDocument().?.path);
}

test "snapshot replacement dismisses visible hover without changing history" {
    var app = try testApp();
    defer app.deinit();
    app.pinned = .{ .snapshot = try testSnapshot("main.zig", "const value = 1;") };
    const content = try hover_state.Content.init(std.testing.allocator, "value: comptime_int", 1);
    try std.testing.expect(app.installHover(app.definition_generation, content));
    const replacement = try document.Snapshot.init(
        std.testing.allocator,
        "main.zig",
        "const value = 2;",
        2,
        .{ .size = 16 },
        .{ .next_fn = scalarNext, .width_fn = scalarWidth },
    );
    try std.testing.expect(app.replaceActiveSnapshot(replacement));
    try std.testing.expect(app.dismissHoverIfDocumentChanged());
    try std.testing.expect(app.hover == null);
    try std.testing.expectEqual(@as(usize, 0), app.history.items.len);
}

test "definition preview cancellation restores an unpinned origin" {
    var app = try testApp();
    defer app.deinit();
    app.pinned = .{ .snapshot = try testSnapshot("older.zig", "older") };
    app.showPreview(try testSnapshot("origin.zig", "origin"));
    app.moveHorizontal(2, 20);
    app.prepareDefinitionPreview();
    app.showPreview(try testSnapshot("target.zig", "target"));
    app.cancelDefinition();
    try std.testing.expectEqualStrings("origin.zig", app.activeDocument().?.path);
    try std.testing.expectEqual(@as(usize, 2), app.activeView().?.active_grapheme);
}

test "definition pin records an unpinned origin and target" {
    var app = try testApp();
    defer app.deinit();
    app.pinned = .{ .snapshot = try testSnapshot("older.zig", "older") };
    app.showPreview(try testSnapshot("origin.zig", "origin"));
    app.prepareDefinitionPreview();
    app.showPreview(try testSnapshot("target.zig", "target"));
    try std.testing.expect(try app.pinDefinitionPreview());
    try std.testing.expectEqual(@as(usize, 2), app.history.items.len);
    try std.testing.expectEqualStrings("origin.zig", app.history.items[0].path);
    try std.testing.expectEqualStrings("target.zig", app.history.items[1].path);
}

test "semantic-style pin captures one previously untracked origin" {
    var app = try testApp();
    defer app.deinit();
    app.pinned = .{ .snapshot = try testSnapshot("origin.zig", "const origin = 1;") };
    app.showPreview(try testSnapshot("target.zig", "const target = 1;"));
    try std.testing.expect(try app.pinSemanticPreview());
    try std.testing.expectEqual(@as(usize, 2), app.history.items.len);
    try std.testing.expectEqualStrings("origin.zig", app.history.items[0].path);
    try std.testing.expectEqualStrings("target.zig", app.history.items[1].path);
    try std.testing.expectEqualStrings("origin.zig", (try app.historyBack()).?.path);
}

test "word and page movement remain on grapheme boundaries" {
    var app = try testApp();
    defer app.deinit();
    app.pinned = .{ .snapshot = try testSnapshot("words.txt", "one  two\nthree") };
    app.moveWordForward(false, 20);
    try std.testing.expectEqual(@as(usize, 5), app.activeView().?.active_grapheme);
    app.moveWordBackward(20);
    try std.testing.expectEqual(@as(usize, 0), app.activeView().?.active_grapheme);
    app.moveVertical(1, 10, 20);
    try std.testing.expectEqual(@as(usize, 9), app.activeView().?.active_grapheme);
}

test "repeated select-line extends the selection one line at a time" {
    var app = try testApp();
    defer app.deinit();
    app.pinned = .{ .snapshot = try testSnapshot("lines.txt", "aaa\nbbb\nccc\nddd\n") };

    // First x snaps to the whole current line (line 0, graphemes 0..3 incl newline).
    app.selectLine();
    const first = app.activeView().?;
    try std.testing.expectEqual(@as(usize, 0), first.snapshot.graphemes[first.anchor_grapheme].line);
    try std.testing.expectEqual(@as(usize, 0), first.snapshot.graphemes[first.active_grapheme].line);

    // Second x reaches down to swallow the next line.
    app.selectLine();
    const second = app.activeView().?;
    try std.testing.expectEqual(@as(usize, 0), second.snapshot.graphemes[second.anchor_grapheme].line);
    try std.testing.expectEqual(@as(usize, 1), second.snapshot.graphemes[second.active_grapheme].line);

    // Third x extends by one more line.
    app.selectLine();
    const third = app.activeView().?;
    try std.testing.expectEqual(@as(usize, 0), third.snapshot.graphemes[third.anchor_grapheme].line);
    try std.testing.expectEqual(@as(usize, 2), third.snapshot.graphemes[third.active_grapheme].line);
}

const fold_sample = "fn main() void {\n    const a = 1;\n    const b = 2;\n}\nafter();\n";

fn foldSampleData() !syntax.ParseData {
    const allocator = std.testing.allocator;
    const folds = try allocator.dupe(syntax.FoldRange, &[_]syntax.FoldRange{
        .{ .start_line = 0, .end_line = 3 },
    });
    errdefer allocator.free(folds);
    const highlights = try allocator.alloc(syntax.HighlightSpan, 0);
    errdefer allocator.free(highlights);
    const nodes = try allocator.dupe(syntax.OutlineNode, &[_]syntax.OutlineNode{
        .{ .source = .{ .start = 0, .end = 62 }, .start_line = 0, .end_line = 5, .parent = null },
        .{ .source = .{ .start = 0, .end = 52 }, .start_line = 0, .end_line = 3, .parent = 0 },
        .{ .source = .{ .start = 17, .end = 33 }, .start_line = 1, .end_line = 1, .parent = 1 },
        .{ .source = .{ .start = 34, .end = 50 }, .start_line = 2, .end_line = 2, .parent = 1 },
    });
    return .{
        .allocator = allocator,
        .highlights = highlights,
        .folds = folds,
        .outline = .{ .allocator = allocator, .nodes = nodes },
    };
}

fn activeLine(app: *const App) usize {
    const view = app.activeView().?;
    return view.snapshot.graphemes[view.active_grapheme].line;
}

test "closing a fold hides interior lines and vertical movement skips them" {
    var app = try testApp();
    defer app.deinit();
    app.pinned = .{ .snapshot = try testSnapshot("main.zig", fold_sample) };
    app.installParseData(try foldSampleData());
    try std.testing.expect(app.foldsAvailable());

    app.foldClose();
    const view = app.activeView().?;
    try std.testing.expect(!view.isLineHidden(0));
    try std.testing.expect(view.isLineHidden(1));
    try std.testing.expect(view.isLineHidden(3));
    try std.testing.expect(!view.isLineHidden(4));
    try std.testing.expectEqual(@as(usize, 0), activeLine(&app));

    // Moving down one visible line skips the collapsed interior to line 4.
    app.moveVertical(1, 20, 80);
    try std.testing.expectEqual(@as(usize, 4), activeLine(&app));

    // Reopening at the fold start reveals the interior again.
    app.moveVertical(-1, 20, 80);
    app.foldOpen();
    try std.testing.expect(!app.activeView().?.isLineHidden(1));
    app.moveVertical(1, 20, 80);
    try std.testing.expectEqual(@as(usize, 1), activeLine(&app));
}

test "close all and open all folds toggle every region" {
    var app = try testApp();
    defer app.deinit();
    app.pinned = .{ .snapshot = try testSnapshot("main.zig", fold_sample) };
    app.installParseData(try foldSampleData());

    app.foldCloseAll();
    try std.testing.expect(app.activeView().?.isLineHidden(2));
    app.foldOpenAll();
    try std.testing.expect(!app.activeView().?.isLineHidden(2));
}

test "structural navigation moves the selection between named nodes" {
    var app = try testApp();
    defer app.deinit();
    app.pinned = .{ .snapshot = try testSnapshot("main.zig", fold_sample) };
    app.installParseData(try foldSampleData());

    // Move onto line 1 (`const a = 1;`), whose enclosing node is the decl.
    app.moveVertical(1, 20, 80);
    try std.testing.expectEqual(@as(usize, 1), activeLine(&app));

    // Ascend to the enclosing function (line 0).
    app.structuralMove(.parent);
    try std.testing.expectEqual(@as(usize, 0), activeLine(&app));

    // Descend to the first child (the first declaration on line 1).
    app.structuralMove(.child);
    try std.testing.expectEqual(@as(usize, 1), activeLine(&app));

    // The next sibling is the second declaration on line 2.
    app.structuralMove(.next_sibling);
    try std.testing.expectEqual(@as(usize, 2), activeLine(&app));

    // And back to the previous sibling on line 1.
    app.structuralMove(.previous_sibling);
    try std.testing.expectEqual(@as(usize, 1), activeLine(&app));
}

test "moving past a large collapsed fold does not jerk the viewport" {
    var app = try testApp();
    defer app.deinit();
    // 200 short lines; a fold spanning lines 0..150 (like a big top-level decl).
    app.pinned = .{ .snapshot = try testSnapshot("big.zig", "a\n" ** 200) };
    const folds = try std.testing.allocator.dupe(syntax.FoldRange, &[_]syntax.FoldRange{
        .{ .start_line = 0, .end_line = 150 },
    });
    app.installParseData(.{
        .allocator = std.testing.allocator,
        .highlights = try std.testing.allocator.alloc(syntax.HighlightSpan, 0),
        .folds = folds,
        .outline = .{ .allocator = std.testing.allocator, .nodes = try std.testing.allocator.alloc(syntax.OutlineNode, 0) },
    });

    // Collapse the fold from its start line; the cursor sits on line 0.
    app.foldClose();
    try std.testing.expect(app.activeView().?.isLineHidden(75));
    try std.testing.expectEqual(@as(usize, 0), app.activeView().?.scroll_line);

    // Step down: the next visible line is 151, which sits right below line 0.
    app.moveVertical(1, 40, 80);
    const view = app.activeView().?;
    try std.testing.expectEqual(@as(usize, 151), view.snapshot.graphemes[view.active_grapheme].line);
    // It is already on screen, so the viewport must not scroll.
    try std.testing.expectEqual(@as(usize, 0), view.scroll_line);
}
