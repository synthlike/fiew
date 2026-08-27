const std = @import("std");
const state = @import("state.zig");

pub const Id = enum {
    move_left,
    move_down,
    move_up,
    move_right,
    word_forward,
    word_backward,
    word_end,
    document_start,
    document_end,
    half_page_up,
    half_page_down,
    page_up,
    page_down,
    toggle_extend,
    select_line,
    collapse_selection,
    reverse_selection,
    activate,
    history_back,
    history_forward,
    focus_next,
    focus_previous,
    project_up,
    project_down,
    project_collapse,
    project_expand,
    project_toggle,
    project_open,
    git_open,
    review_open,
    definition,
    fold_close,
    fold_open,
    fold_toggle,
    fold_close_all,
    fold_open_all,
    structural_parent,
    structural_child,
    structural_next,
    structural_previous,
    diff_file_next,
    diff_file_previous,
    diff_hunk_next,
    diff_hunk_previous,
    diff_line_next,
    diff_line_previous,
    leader_menu,
    file_commands,
    help,
    command_prompt,
    quit,
    cancel,
    close_transient,
    note_save,
    note_discard,
};

pub const Definition = struct {
    id: Id,
    stable_id: []const u8,
    title: []const u8,
    binding: []const u8,
    disabled_reason: ?[]const u8 = null,
};

pub const definitions = [_]Definition{
    .{ .id = .move_left, .stable_id = "move-left", .title = "Move left", .binding = "h" },
    .{ .id = .move_down, .stable_id = "move-down", .title = "Move down", .binding = "j" },
    .{ .id = .move_up, .stable_id = "move-up", .title = "Move up", .binding = "k" },
    .{ .id = .move_right, .stable_id = "move-right", .title = "Move right", .binding = "l" },
    .{ .id = .word_forward, .stable_id = "word-forward", .title = "Next word", .binding = "w" },
    .{ .id = .word_backward, .stable_id = "word-backward", .title = "Previous word", .binding = "b" },
    .{ .id = .word_end, .stable_id = "word-end", .title = "End of word", .binding = "e" },
    .{ .id = .document_start, .stable_id = "document-start", .title = "Document start", .binding = "g g" },
    .{ .id = .document_end, .stable_id = "document-end", .title = "Document end", .binding = "g e" },
    .{ .id = .half_page_up, .stable_id = "half-page-up", .title = "Half page up", .binding = "Ctrl-u" },
    .{ .id = .half_page_down, .stable_id = "half-page-down", .title = "Half page down", .binding = "Ctrl-d" },
    .{ .id = .page_up, .stable_id = "page-up", .title = "Page up", .binding = "PageUp" },
    .{ .id = .page_down, .stable_id = "page-down", .title = "Page down", .binding = "PageDown" },
    .{ .id = .toggle_extend, .stable_id = "toggle-extend", .title = "Toggle Extend mode", .binding = "v" },
    .{ .id = .select_line, .stable_id = "select-line", .title = "Select line", .binding = "x" },
    .{ .id = .collapse_selection, .stable_id = "collapse-selection", .title = "Collapse to active end", .binding = ";" },
    .{ .id = .reverse_selection, .stable_id = "reverse-selection", .title = "Reverse selection", .binding = "Alt-;" },
    .{ .id = .activate, .stable_id = "activate", .title = "Open or activate selection", .binding = "Enter" },
    .{ .id = .history_back, .stable_id = "history-back", .title = "Previous location", .binding = "Ctrl-o" },
    .{ .id = .history_forward, .stable_id = "history-forward", .title = "Next location", .binding = "Ctrl-i" },
    .{ .id = .focus_next, .stable_id = "focus-next", .title = "Focus next region", .binding = "Tab" },
    .{ .id = .focus_previous, .stable_id = "focus-previous", .title = "Focus previous region", .binding = "Shift-Tab" },
    .{ .id = .project_up, .stable_id = "project-up", .title = "Previous Project item", .binding = "k" },
    .{ .id = .project_down, .stable_id = "project-down", .title = "Next Project item", .binding = "j" },
    .{ .id = .project_collapse, .stable_id = "project-collapse", .title = "Collapse or parent", .binding = "h" },
    .{ .id = .project_expand, .stable_id = "project-expand", .title = "Expand or child", .binding = "l" },
    .{ .id = .project_toggle, .stable_id = "project-toggle", .title = "Toggle Project directory", .binding = "Enter" },
    .{ .id = .project_open, .stable_id = "project-open", .title = "Open Project sidebar", .binding = "Space b" },
    .{ .id = .git_open, .stable_id = "git-open", .title = "Open Git sidebar", .binding = "Space g" },
    .{ .id = .diff_file_next, .stable_id = "diff-file-next", .title = "Next changed file", .binding = "] f" },
    .{ .id = .diff_file_previous, .stable_id = "diff-file-previous", .title = "Previous changed file", .binding = "[ f" },
    .{ .id = .diff_hunk_next, .stable_id = "diff-hunk-next", .title = "Next hunk", .binding = "] h" },
    .{ .id = .diff_hunk_previous, .stable_id = "diff-hunk-previous", .title = "Previous hunk", .binding = "[ h" },
    .{ .id = .diff_line_next, .stable_id = "diff-line-next", .title = "Next changed line", .binding = "] c" },
    .{ .id = .diff_line_previous, .stable_id = "diff-line-previous", .title = "Previous changed line", .binding = "[ c" },
    .{ .id = .review_open, .stable_id = "review-open", .title = "Open Review sidebar", .binding = "Space r", .disabled_reason = "Review notes are not implemented" },
    .{ .id = .definition, .stable_id = "definition", .title = "Go to definition", .binding = "g d", .disabled_reason = "trusted ZLS is not available" },
    .{ .id = .fold_close, .stable_id = "fold-close", .title = "Close fold", .binding = "z c" },
    .{ .id = .fold_open, .stable_id = "fold-open", .title = "Open fold", .binding = "z o" },
    .{ .id = .fold_toggle, .stable_id = "fold-toggle", .title = "Toggle fold", .binding = "z a" },
    .{ .id = .fold_close_all, .stable_id = "fold-close-all", .title = "Close all folds", .binding = "z M" },
    .{ .id = .fold_open_all, .stable_id = "fold-open-all", .title = "Open all folds", .binding = "z R" },
    .{ .id = .structural_parent, .stable_id = "structural-parent", .title = "Select enclosing node", .binding = "Alt-o" },
    .{ .id = .structural_child, .stable_id = "structural-child", .title = "Select first child node", .binding = "Alt-i" },
    .{ .id = .structural_next, .stable_id = "structural-next", .title = "Select next sibling node", .binding = "Alt-n" },
    .{ .id = .structural_previous, .stable_id = "structural-previous", .title = "Select previous sibling node", .binding = "Alt-p" },
    .{ .id = .leader_menu, .stable_id = "leader-menu", .title = "Open leader menu", .binding = "Space" },
    .{ .id = .file_commands, .stable_id = "file-commands", .title = "Open file commands", .binding = "Space f" },
    .{ .id = .help, .stable_id = "help", .title = "Show key help", .binding = "Space ?" },
    .{ .id = .command_prompt, .stable_id = "command-prompt", .title = "Search named commands", .binding = ":" },
    .{ .id = .quit, .stable_id = "quit", .title = "Quit fiew", .binding = "Space q / :quit" },
    .{ .id = .cancel, .stable_id = "cancel", .title = "Cancel", .binding = "Esc" },
    .{ .id = .close_transient, .stable_id = "close-transient", .title = "Close transient view", .binding = "q" },
    .{ .id = .note_save, .stable_id = "note-save", .title = "Save note", .binding = "Ctrl-Enter", .disabled_reason = "note composer is not open" },
    .{ .id = .note_discard, .stable_id = "note-discard", .title = "Discard note", .binding = "Esc", .disabled_reason = "note composer is not open" },
};

pub fn definition(id: Id) *const Definition {
    for (&definitions) |*item| if (item.id == id) return item;
    unreachable;
}

pub fn unavailableReason(app: *const state.App, id: Id) ?[]const u8 {
    if (definition(id).disabled_reason) |reason| return reason;
    return switch (id) {
        .move_left,
        .move_down,
        .move_up,
        .move_right,
        .word_forward,
        .word_backward,
        .word_end,
        .document_start,
        .document_end,
        .half_page_up,
        .half_page_down,
        .page_up,
        .page_down,
        .toggle_extend,
        .select_line,
        .collapse_selection,
        .reverse_selection,
        => if (app.focus != .main)
            "focus main view to navigate the document"
        else if (app.activeView() == null)
            "no document is open"
        else if (app.activeDocument().?.graphemes.len == 0)
            "document has no navigable text"
        else
            null,
        .activate => if (app.focus == .sidebar)
            null
        else if (app.sidebar_context == .git and !app.viewing_source)
            null // Enter opens the source of the diff line under the cursor
        else
            "focus Project to activate an item",
        .fold_close,
        .fold_open,
        .fold_toggle,
        .fold_close_all,
        .fold_open_all,
        => if (app.focus != .main)
            "focus main view to fold"
        else if (!app.foldsAvailable())
            "Tree-sitter folds are not available"
        else
            null,
        .structural_parent,
        .structural_child,
        .structural_next,
        .structural_previous,
        => if (app.focus != .main)
            "focus main view to navigate structure"
        else if (!app.outlineAvailable())
            "Tree-sitter structure is not available"
        else
            null,
        .git_open => if (!app.git_enabled) "not a Git repository" else null,
        .diff_file_next,
        .diff_file_previous,
        .diff_hunk_next,
        .diff_hunk_previous,
        .diff_line_next,
        .diff_line_previous,
        => if (app.sidebar_context != .git)
            "open the Git view first"
        else if (app.review == null or app.review.?.isEmpty())
            "no changes to review"
        else
            null,
        else => null,
    };
}

pub const Code = enum {
    character,
    escape,
    enter,
    tab,
    backspace,
    page_up,
    page_down,
    up,
    down,
    left,
    right,
};

pub const Key = struct {
    code: Code,
    character: u21 = 0,
    shift: bool = false,
    alt: bool = false,
    ctrl: bool = false,
};

pub const Dimensions = struct {
    sidebar_rows: usize,
    document_rows: usize,
    document_columns: usize,
};

/// A source location to open in context from a diff line.
pub const SourceLocation = struct { path: []const u8, line: usize };

pub const Effect = union(enum) {
    none,
    preview_selection,
    activate_selection,
    open_history: state.Location,
    /// Load and show the Git working-tree review.
    open_review,
    /// Open a change's source file at a diff line.
    open_source: SourceLocation,
    quit,
};

pub const Surface = enum {
    none,
    leader,
    file,
    command,
    help,
};

const Pending = enum {
    none,
    goto,
    fold,
    bracket_next,
    bracket_previous,
};

pub const Session = struct {
    allocator: std.mem.Allocator,
    surface: Surface = .none,
    pending: Pending = .none,
    pending_ticks: u8 = 0,
    query: std.ArrayListUnmanaged(u8) = .empty,
    selected_command: usize = 0,
    help_scroll: usize = 0,

    pub fn init(allocator: std.mem.Allocator) Session {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Session) void {
        self.query.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn pendingLabel(self: Session) []const u8 {
        return switch (self.pending) {
            .none => switch (self.surface) {
                .leader => "Space",
                .file => "Space f",
                .command => ":",
                .help => "help",
                .none => "",
            },
            .goto => "g",
            .fold => "z",
            .bracket_next => "]",
            .bracket_previous => "[",
        };
    }

    pub fn tick(self: *Session, app: *state.App) void {
        if (self.pending == .none) return;
        self.pending_ticks +|= 1;
        if (self.pending_ticks >= 4) {
            self.pending = .none;
            self.pending_ticks = 0;
            app.mode = .normal;
            app.feedback = "key sequence timed out";
        }
    }

    pub fn handle(self: *Session, app: *state.App, key: Key, dimensions: Dimensions) !Effect {
        if (key.code == .escape) return self.execute(app, .cancel, dimensions);
        if (self.surface == .command) return self.handleCommandInput(app, key, dimensions);
        if (self.surface == .help) {
            if (isCharacter(key, 'q')) return self.execute(app, .close_transient, dimensions);
            if (isCharacter(key, 'j') or key.code == .down) self.help_scroll = @min(self.help_scroll + 1, definitions.len -| 1);
            if (isCharacter(key, 'k') or key.code == .up) self.help_scroll -|= 1;
            if (key.code == .page_down) self.help_scroll = @min(self.help_scroll + dimensions.document_rows, definitions.len -| 1);
            if (key.code == .page_up) self.help_scroll -|= dimensions.document_rows;
            return .none;
        }
        if (self.surface == .leader or self.surface == .file) {
            return self.handleLeader(app, key, dimensions);
        }
        if (self.pending != .none) return self.handlePending(app, key, dimensions);

        if (key.code == .tab) return self.execute(
            app,
            if (key.shift) .focus_previous else .focus_next,
            dimensions,
        );
        if (key.code == .enter) return self.execute(app, .activate, dimensions);
        if (key.code == .page_up) return self.execute(app, .page_up, dimensions);
        if (key.code == .page_down) return self.execute(app, .page_down, dimensions);
        if (key.code == .left) return self.execute(app, if (app.focus == .sidebar) .project_collapse else .move_left, dimensions);
        if (key.code == .right) return self.execute(app, if (app.focus == .sidebar) .project_expand else .move_right, dimensions);
        if (key.code == .up) return self.execute(app, if (app.focus == .sidebar) .project_up else .move_up, dimensions);
        if (key.code == .down) return self.execute(app, if (app.focus == .sidebar) .project_down else .move_down, dimensions);

        if (key.ctrl) {
            if (isCharacter(key, 'c')) return self.execute(app, .quit, dimensions);
            if (isCharacter(key, 'u')) return self.execute(app, .half_page_up, dimensions);
            if (isCharacter(key, 'd')) return self.execute(app, .half_page_down, dimensions);
            if (isCharacter(key, 'o')) return self.execute(app, .history_back, dimensions);
            if (isCharacter(key, 'i')) return self.execute(app, .history_forward, dimensions);
        }
        if (key.alt) {
            if (isCharacter(key, ';')) return self.execute(app, .reverse_selection, dimensions);
            if (isCharacter(key, 'o')) return self.execute(app, .structural_parent, dimensions);
            if (isCharacter(key, 'i')) return self.execute(app, .structural_child, dimensions);
            if (isCharacter(key, 'n')) return self.execute(app, .structural_next, dimensions);
            if (isCharacter(key, 'p')) return self.execute(app, .structural_previous, dimensions);
        }
        if (key.code != .character) return .none;

        return switch (normalizedCharacter(key)) {
            'h' => self.execute(app, if (app.focus == .sidebar) .project_collapse else .move_left, dimensions),
            'j' => self.execute(app, if (app.focus == .sidebar) .project_down else .move_down, dimensions),
            'k' => self.execute(app, if (app.focus == .sidebar) .project_up else .move_up, dimensions),
            'l' => self.execute(app, if (app.focus == .sidebar) .project_expand else .move_right, dimensions),
            'w' => self.execute(app, .word_forward, dimensions),
            'b' => self.execute(app, .word_backward, dimensions),
            'e' => self.execute(app, .word_end, dimensions),
            'v' => self.execute(app, .toggle_extend, dimensions),
            'x' => self.execute(app, .select_line, dimensions),
            ';' => self.execute(app, .collapse_selection, dimensions),
            'g' => self.startPending(.goto, app),
            'z' => self.startPending(.fold, app),
            ']' => self.startPending(.bracket_next, app),
            '[' => self.startPending(.bracket_previous, app),
            ' ' => self.execute(app, .leader_menu, dimensions),
            ':' => self.execute(app, .command_prompt, dimensions),
            'q' => self.execute(app, .close_transient, dimensions),
            else => .none,
        };
    }

    pub fn execute(self: *Session, app: *state.App, id: Id, dimensions: Dimensions) !Effect {
        if (unavailableReason(app, id)) |reason| {
            app.feedback = reason;
            self.resetTransient(app);
            return .none;
        }
        app.feedback = null;
        switch (id) {
            .move_left => app.moveHorizontal(-1, dimensions.document_columns),
            .move_down => app.mainVerticalMove(1, dimensions.document_rows, dimensions.document_columns),
            .move_up => app.mainVerticalMove(-1, dimensions.document_rows, dimensions.document_columns),
            .move_right => app.moveHorizontal(1, dimensions.document_columns),
            .word_forward => app.moveWordForward(false, dimensions.document_columns),
            .word_backward => app.moveWordBackward(dimensions.document_columns),
            .word_end => app.moveWordForward(true, dimensions.document_columns),
            .document_start => app.moveDocumentBoundary(false, dimensions.document_rows, dimensions.document_columns),
            .document_end => app.moveDocumentBoundary(true, dimensions.document_rows, dimensions.document_columns),
            .half_page_up => app.mainVerticalMove(-@as(isize, @intCast(@max(dimensions.document_rows / 2, 1))), dimensions.document_rows, dimensions.document_columns),
            .half_page_down => app.mainVerticalMove(@intCast(@max(dimensions.document_rows / 2, 1)), dimensions.document_rows, dimensions.document_columns),
            .page_up => app.mainVerticalMove(-@as(isize, @intCast(@max(dimensions.document_rows, 1))), dimensions.document_rows, dimensions.document_columns),
            .page_down => app.mainVerticalMove(@intCast(@max(dimensions.document_rows, 1)), dimensions.document_rows, dimensions.document_columns),
            .toggle_extend => app.toggleExtend(),
            .select_line => app.selectLine(),
            .collapse_selection => app.collapseSelection(),
            .reverse_selection => app.reverseSelection(),
            .activate => return activate(app),
            .history_back => {
                // In the Git review, Ctrl-o returns from a source view to its diff.
                if (app.sidebar_context == .git and app.viewing_source) {
                    app.viewing_source = false;
                    app.focus = .main;
                    return .none;
                }
                if (try app.historyBack()) |location| return .{ .open_history = location };
            },
            .history_forward => if (try app.historyForward()) |location| return .{ .open_history = location },
            .focus_next, .focus_previous => app.toggleFocus(),
            .project_up => {
                if (app.sidebar_context == .git) {
                    if (app.review) |*review| review.moveSelection(-1, dimensions.sidebar_rows);
                    app.viewing_source = false;
                    return .none;
                }
                app.browser.move(-1, dimensions.sidebar_rows);
                return .preview_selection;
            },
            .project_down => {
                if (app.sidebar_context == .git) {
                    if (app.review) |*review| review.moveSelection(1, dimensions.sidebar_rows);
                    app.viewing_source = false;
                    return .none;
                }
                app.browser.move(1, dimensions.sidebar_rows);
                return .preview_selection;
            },
            .project_collapse => {
                if (app.sidebar_context == .git) return .none;
                try app.browser.collapseOrParent(dimensions.sidebar_rows);
                return .preview_selection;
            },
            .project_expand => {
                if (app.sidebar_context == .git) return .none;
                try app.browser.expandOrChild(dimensions.sidebar_rows);
                return .preview_selection;
            },
            .project_toggle => {
                _ = try app.browser.toggleSelected(dimensions.sidebar_rows);
                app.clearPreview();
            },
            .project_open => {
                if (app.sidebar_context == .git) {
                    app.showProjectSidebar();
                } else if (app.sidebar_visible and app.focus == .sidebar) {
                    app.collapseSidebar();
                } else {
                    app.showSidebar();
                }
            },
            .leader_menu => {
                self.surface = .leader;
                app.mode = .normal;
            },
            .file_commands => {
                self.surface = .file;
                app.mode = .normal;
            },
            .help => {
                self.surface = .help;
                app.mode = .normal;
            },
            .command_prompt => {
                self.surface = .command;
                app.mode = .command;
            },
            .quit => return .quit,
            .cancel => {
                app.feedback = null;
                if (self.surface != .none or self.pending != .none or app.mode == .command) {
                    self.resetTransient(app);
                } else if (app.mode == .extend) {
                    app.leaveExtend();
                } else if (app.preview != null) {
                    app.clearPreview();
                }
            },
            .close_transient => {
                if (self.surface != .none) self.resetTransient(app) else app.feedback = "no transient view to close";
            },
            .fold_close => app.foldClose(),
            .fold_open => app.foldOpen(),
            .fold_toggle => app.foldToggle(),
            .fold_close_all => app.foldCloseAll(),
            .fold_open_all => app.foldOpenAll(),
            .structural_parent => app.structuralMove(.parent),
            .structural_child => app.structuralMove(.child),
            .structural_next => app.structuralMove(.next_sibling),
            .structural_previous => app.structuralMove(.previous_sibling),
            .git_open => return .open_review,
            .diff_file_next => diffFile(app, true, dimensions),
            .diff_file_previous => diffFile(app, false, dimensions),
            .diff_hunk_next => diffHunk(app, true, dimensions),
            .diff_hunk_previous => diffHunk(app, false, dimensions),
            .diff_line_next => diffChangedLine(app, true, dimensions),
            .diff_line_previous => diffChangedLine(app, false, dimensions),
            .review_open, .definition, .note_save, .note_discard => unreachable,
        }
        // Fold and structural commands can move the cursor far from the current
        // scroll position; keep it on screen.
        switch (id) {
            .fold_close,
            .fold_open,
            .fold_toggle,
            .fold_close_all,
            .fold_open_all,
            .structural_parent,
            .structural_child,
            .structural_next,
            .structural_previous,
            => app.ensureCurrentDocumentVisible(dimensions.document_rows, dimensions.document_columns),
            else => {},
        }
        return .none;
    }

    fn handlePending(self: *Session, app: *state.App, key: Key, dimensions: Dimensions) !Effect {
        const pending = self.pending;
        self.pending = .none;
        self.pending_ticks = 0;
        const character = normalizedCharacter(key);
        const id: ?Id = switch (pending) {
            .goto => switch (character) {
                'g' => .document_start,
                'e' => .document_end,
                'd' => .definition,
                else => null,
            },
            .fold => if (key.shift) switch (character) {
                'm' => .fold_close_all,
                'r' => .fold_open_all,
                else => null,
            } else switch (character) {
                'c' => .fold_close,
                'o' => .fold_open,
                'a' => .fold_toggle,
                else => null,
            },
            .bracket_next => switch (character) {
                'f' => .diff_file_next,
                'h' => .diff_hunk_next,
                'c' => .diff_line_next,
                else => null,
            },
            .bracket_previous => switch (character) {
                'f' => .diff_file_previous,
                'h' => .diff_hunk_previous,
                'c' => .diff_line_previous,
                else => null,
            },
            .none => unreachable,
        };
        if (id) |command| return self.execute(app, command, dimensions);
        app.mode = .normal;
        app.feedback = "invalid key sequence";
        return .none;
    }

    fn handleLeader(self: *Session, app: *state.App, key: Key, dimensions: Dimensions) !Effect {
        if (self.surface == .file) {
            if (key.code == .enter) return self.execute(app, .activate, dimensions);
            app.feedback = "invalid file command";
            self.resetTransient(app);
            return .none;
        }
        return switch (normalizedCharacter(key)) {
            'f' => self.executeAndClose(app, .file_commands, dimensions),
            'b' => self.executeAndClose(app, .project_open, dimensions),
            'g' => self.executeAndClose(app, .git_open, dimensions),
            'r' => self.executeAndClose(app, .review_open, dimensions),
            '?' => self.executeAndClose(app, .help, dimensions),
            'q' => self.executeAndClose(app, .quit, dimensions),
            else => blk: {
                app.feedback = "invalid leader command";
                self.resetTransient(app);
                break :blk .none;
            },
        };
    }

    fn handleCommandInput(self: *Session, app: *state.App, key: Key, dimensions: Dimensions) !Effect {
        if (key.code == .backspace) {
            if (self.query.items.len != 0) {
                var start = self.query.items.len - 1;
                while (start > 0 and (self.query.items[start] & 0xc0) == 0x80) start -= 1;
                self.query.shrinkRetainingCapacity(start);
            }
            self.selected_command = 0;
            return .none;
        }
        if (key.code == .up) {
            self.selected_command -|= 1;
            return .none;
        }
        if (key.code == .down) {
            const count = self.filteredCount();
            if (count != 0) self.selected_command = @min(self.selected_command + 1, count - 1);
            return .none;
        }
        if (key.code == .enter) {
            const id = self.filteredCommand(self.selected_command) orelse {
                app.feedback = "command not found";
                self.resetTransient(app);
                return .none;
            };
            self.surface = .none;
            app.mode = .normal;
            self.query.clearRetainingCapacity();
            self.selected_command = 0;
            return self.execute(app, id, dimensions);
        }
        if (key.code == .character and !key.ctrl and !key.alt) {
            var buffer: [4]u8 = undefined;
            const encoded = std.unicode.utf8Encode(key.character, &buffer) catch return .none;
            try self.query.appendSlice(self.allocator, buffer[0..encoded]);
            self.selected_command = 0;
        }
        return .none;
    }

    pub fn filteredCommand(self: Session, requested_index: usize) ?Id {
        var index: usize = 0;
        for (definitions) |item| {
            if (!matchesQuery(item, self.query.items)) continue;
            if (index == requested_index) return item.id;
            index += 1;
        }
        return null;
    }

    pub fn filteredCount(self: Session) usize {
        var count: usize = 0;
        for (definitions) |item| {
            if (matchesQuery(item, self.query.items)) count += 1;
        }
        return count;
    }

    fn executeAndClose(self: *Session, app: *state.App, id: Id, dimensions: Dimensions) !Effect {
        self.surface = .none;
        return self.execute(app, id, dimensions);
    }

    fn startPending(self: *Session, pending: Pending, app: *state.App) Effect {
        self.pending = pending;
        self.pending_ticks = 0;
        app.feedback = null;
        return .none;
    }

    fn openSurface(self: *Session, surface: Surface, app: *state.App) Effect {
        self.surface = surface;
        self.pending = .none;
        self.pending_ticks = 0;
        self.query.clearRetainingCapacity();
        self.selected_command = 0;
        self.help_scroll = 0;
        app.mode = if (surface == .command) .command else .normal;
        app.feedback = null;
        return .none;
    }

    fn resetTransient(self: *Session, app: *state.App) void {
        self.surface = .none;
        self.pending = .none;
        self.pending_ticks = 0;
        self.query.clearRetainingCapacity();
        self.selected_command = 0;
        self.help_scroll = 0;
        app.mode = .normal;
    }
};

fn activate(app: *state.App) Effect {
    if (app.focus == .sidebar) {
        if (app.sidebar_context == .git) {
            // Focus the diff of the selected change.
            if (app.review != null and app.review.?.selectedChange() != null) {
                app.focus = .main;
                app.viewing_source = false;
            }
            return .none;
        }
        return .activate_selection;
    }
    // In the diff view, Enter opens the change's source in context.
    if (app.sidebar_context == .git and !app.viewing_source) {
        if (app.review) |*review| {
            if (review.sourceTarget()) |target|
                return .{ .open_source = .{ .path = target.path, .line = target.line } };
        }
    }
    return .none;
}

fn diffFile(app: *state.App, forward: bool, dimensions: Dimensions) void {
    const review = &app.review.?;
    if (review.moveFile(forward, dimensions.sidebar_rows)) {
        app.viewing_source = false;
    } else {
        app.feedback = "no more files in this group";
    }
}

fn diffHunk(app: *state.App, forward: bool, dimensions: Dimensions) void {
    const review = &app.review.?;
    if (!review.moveHunk(forward)) app.feedback = "no more hunks";
    review.ensureDiffVisible(dimensions.document_rows);
    app.viewing_source = false;
}

fn diffChangedLine(app: *state.App, forward: bool, dimensions: Dimensions) void {
    const review = &app.review.?;
    if (!review.moveChangedLine(forward)) app.feedback = "no more changed lines";
    review.ensureDiffVisible(dimensions.document_rows);
    app.viewing_source = false;
}

fn matchesQuery(item: Definition, query: []const u8) bool {
    if (query.len == 0) return true;
    return std.ascii.indexOfIgnoreCase(item.stable_id, query) != null or
        std.ascii.indexOfIgnoreCase(item.title, query) != null;
}

fn normalizedCharacter(key: Key) u21 {
    if (key.code != .character) return 0;
    if (key.character >= 'A' and key.character <= 'Z') return key.character + ('a' - 'A');
    return key.character;
}

fn isCharacter(key: Key, character: u21) bool {
    return key.code == .character and normalizedCharacter(key) == character;
}

test "registry stable identifiers are unique" {
    for (definitions, 0..) |left, index| {
        try std.testing.expect(left.stable_id.len != 0);
        for (definitions[index + 1 ..]) |right| {
            try std.testing.expect(!std.mem.eql(u8, left.stable_id, right.stable_id));
        }
    }
}

test "required modal bindings are represented by the command registry" {
    const required = [_][]const u8{
        "h",       "j",       "k",       "l",        "w",   "b",   "e",   "g g",   "g e",
        "Ctrl-u",  "Ctrl-d",  "PageUp",  "PageDown", "v",   "x",   ";",   "Alt-;", "Enter",
        "g d",     "Ctrl-o",  "Ctrl-i",  "z c",      "z o", "z a", "z M", "z R",   "Space b",
        "Space g", "Space r", "Space ?", ":",        "q",
    };
    for (required) |binding| {
        var found = false;
        for (definitions) |item| {
            if (std.mem.eql(u8, item.binding, binding)) {
                found = true;
                break;
            }
        }
        try std.testing.expect(found);
    }
}

test "normal and extend bindings dispatch through the reducer" {
    var app = try testApp();
    defer app.deinit();
    var session = Session.init(std.testing.allocator);
    defer session.deinit();
    const dimensions: Dimensions = .{ .sidebar_rows = 20, .document_rows = 20, .document_columns = 80 };

    _ = try session.handle(&app, charKey('l'), dimensions);
    try std.testing.expectEqual(@as(usize, 1), app.activeView().?.active_grapheme);
    try std.testing.expectEqual(app.activeView().?.anchor_grapheme, app.activeView().?.active_grapheme);
    _ = try session.handle(&app, charKey('v'), dimensions);
    _ = try session.handle(&app, charKey('l'), dimensions);
    try std.testing.expectEqual(state.Mode.extend, app.mode);
    try std.testing.expectEqual(@as(usize, 1), app.activeView().?.anchor_grapheme);
    try std.testing.expectEqual(@as(usize, 2), app.activeView().?.active_grapheme);
    _ = try session.handle(&app, charKey(';'), dimensions);
    try std.testing.expectEqual(app.activeView().?.anchor_grapheme, app.activeView().?.active_grapheme);
    _ = try session.handle(&app, .{ .code = .character, .character = ';', .alt = true }, dimensions);
    try std.testing.expectEqual(@as(usize, 2), app.activeView().?.active_grapheme);
}

test "focus cycling is a reducer transition" {
    var app = try testApp();
    defer app.deinit();
    var session = Session.init(std.testing.allocator);
    defer session.deinit();
    const dimensions: Dimensions = .{ .sidebar_rows = 20, .document_rows = 20, .document_columns = 80 };

    _ = try session.handle(&app, .{ .code = .tab }, dimensions);
    try std.testing.expectEqual(state.Focus.sidebar, app.focus);
    _ = try session.handle(&app, .{ .code = .tab, .shift = true }, dimensions);
    try std.testing.expectEqual(state.Focus.main, app.focus);
}

test "goto and unavailable namespace commands report deterministic outcomes" {
    var app = try testApp();
    defer app.deinit();
    var session = Session.init(std.testing.allocator);
    defer session.deinit();
    const dimensions: Dimensions = .{ .sidebar_rows = 20, .document_rows = 20, .document_columns = 80 };
    app.pinned.?.deinit();
    app.pinned = .{ .snapshot = try testSnapshot("lines.txt", "abcd\nx\nwxyz\n") };
    app.moveHorizontal(2, dimensions.document_columns);

    _ = try session.handle(&app, charKey('g'), dimensions);
    _ = try session.handle(&app, charKey('e'), dimensions);
    try std.testing.expectEqual(@as(usize, 9), app.activeView().?.active_grapheme);
    try std.testing.expectEqual(@as(u32, 2), app.activeView().?.preferred_column);
    _ = try session.handle(&app, charKey('g'), dimensions);
    _ = try session.handle(&app, charKey('g'), dimensions);
    try std.testing.expectEqual(@as(usize, 2), app.activeView().?.active_grapheme);
    _ = try session.handle(&app, charKey('g'), dimensions);
    _ = try session.handle(&app, charKey('d'), dimensions);
    try std.testing.expectEqualStrings("trusted ZLS is not available", app.feedback.?);
    _ = try session.handle(&app, charKey('z'), dimensions);
    _ = try session.handle(&app, charKey('c'), dimensions);
    try std.testing.expectEqualStrings("Tree-sitter folds are not available", app.feedback.?);
    const effect = try session.handle(&app, charKey('q'), dimensions);
    try std.testing.expectEqual(std.meta.Tag(Effect).none, effect);
    try std.testing.expectEqualStrings("no transient view to close", app.feedback.?);
}

test "invalid and timed out sequences preserve selection" {
    var app = try testApp();
    defer app.deinit();
    var session = Session.init(std.testing.allocator);
    defer session.deinit();
    const dimensions: Dimensions = .{ .sidebar_rows = 20, .document_rows = 20, .document_columns = 80 };
    const before = app.selection();

    _ = try session.handle(&app, charKey('g'), dimensions);
    _ = try session.handle(&app, charKey('x'), dimensions);
    try std.testing.expectEqualStrings("invalid key sequence", app.feedback.?);
    try std.testing.expectEqual(before, app.selection());
    _ = try session.handle(&app, charKey('z'), dimensions);
    for (0..4) |_| session.tick(&app);
    try std.testing.expectEqualStrings("key sequence timed out", app.feedback.?);
    try std.testing.expectEqual(before, app.selection());
}

test "leader and named command surfaces use the same registry" {
    var app = try testApp();
    defer app.deinit();
    var session = Session.init(std.testing.allocator);
    defer session.deinit();
    const dimensions: Dimensions = .{ .sidebar_rows = 20, .document_rows = 20, .document_columns = 80 };

    _ = try session.handle(&app, charKey(' '), dimensions);
    _ = try session.handle(&app, charKey('g'), dimensions);
    try std.testing.expectEqualStrings("not a Git repository", app.feedback.?);

    _ = try session.handle(&app, charKey(':'), dimensions);
    for ("quit") |character| _ = try session.handle(&app, charKey(character), dimensions);
    const effect = try session.handle(&app, .{ .code = .enter }, dimensions);
    try std.testing.expectEqual(std.meta.Tag(Effect).quit, effect);
}

fn testSnapshot(path: []const u8, bytes: []const u8) !@import("../model/document.zig").Snapshot {
    const document = @import("../model/document.zig");
    return document.Snapshot.init(
        std.testing.allocator,
        path,
        bytes,
        1,
        .{ .size = bytes.len },
        .{ .next_fn = scalarNext, .width_fn = scalarWidth },
    );
}

fn charKey(character: u21) Key {
    return .{ .code = .character, .character = character };
}

fn testApp() !state.App {
    const project = @import("../model/project.zig");
    const document = @import("../model/document.zig");
    const Static = struct {
        var nodes = [_]project.Node{.{ .path = "a.txt", .depth = 1, .kind = .file }};
        var tree: project.Tree = .{ .allocator = std.testing.allocator, .nodes = &nodes, .file_count = 1 };
    };
    var app = try state.App.init(std.testing.allocator, &Static.tree);
    app.pinned = .{ .snapshot = try document.Snapshot.init(
        std.testing.allocator,
        "a.txt",
        "one two",
        1,
        .{ .size = 7 },
        .{ .next_fn = scalarNext, .width_fn = scalarWidth },
    ) };
    app.focus = .main;
    return app;
}

fn scalarNext(_: ?*const anyopaque, text: []const u8, start: usize) usize {
    return @min(text.len, start + (std.unicode.utf8ByteSequenceLength(text[start]) catch 1));
}

fn scalarWidth(_: ?*const anyopaque, text: []const u8) u16 {
    return if (std.mem.eql(u8, text, "\n")) 0 else 1;
}

test "parsed Zig drives fold and structural commands end to end" {
    const zig_syntax = @import("../adapters/treesitter/zig_syntax.zig");
    var app = try testApp();
    defer app.deinit();
    app.pinned.?.deinit();
    const source = "pub fn main() void {\n    const a = 1;\n    const b = 2;\n}\n";
    app.pinned = .{ .snapshot = try testSnapshot("main.zig", source) };
    app.focus = .main;

    var engine = try zig_syntax.Engine.init(std.testing.allocator);
    defer engine.deinit();
    var tree = engine.parse(source, null) orelse return error.ParseFailed;
    defer tree.deinit();
    app.installParseData(try engine.analyze(std.testing.allocator, &tree));
    try std.testing.expect(app.foldsAvailable());
    try std.testing.expect(app.outlineAvailable());

    var session = Session.init(std.testing.allocator);
    defer session.deinit();
    const dimensions: Dimensions = .{ .sidebar_rows = 20, .document_rows = 20, .document_columns = 80 };

    // `z c` collapses the function body, hiding its interior lines.
    _ = try session.handle(&app, charKey('z'), dimensions);
    _ = try session.handle(&app, charKey('c'), dimensions);
    try std.testing.expect(app.activeView().?.isLineHidden(1));

    // `z o` reopens it.
    _ = try session.handle(&app, charKey('z'), dimensions);
    _ = try session.handle(&app, charKey('o'), dimensions);
    try std.testing.expect(!app.activeView().?.isLineHidden(1));

    // Alt-n moves the selection to a sibling without leaving the document.
    _ = try session.handle(&app, .{ .code = .character, .character = 'n', .alt = true }, dimensions);
    try std.testing.expect(app.activeView() != null);
}

test "structural navigation scrolls the view to a distant target" {
    const syntax = @import("../model/syntax.zig");
    var app = try testApp();
    defer app.deinit();
    app.pinned.?.deinit();
    app.pinned = .{ .snapshot = try testSnapshot("tall.txt", "a\n" ** 30) };
    app.focus = .main;

    // Two sibling nodes 20 lines apart, with no folds or highlights.
    const nodes = try std.testing.allocator.dupe(syntax.OutlineNode, &[_]syntax.OutlineNode{
        .{ .source = .{ .start = 0, .end = 60 }, .start_line = 0, .end_line = 30, .parent = null },
        .{ .source = .{ .start = 0, .end = 2 }, .start_line = 0, .end_line = 0, .parent = 0 },
        .{ .source = .{ .start = 40, .end = 42 }, .start_line = 20, .end_line = 20, .parent = 0 },
    });
    app.installParseData(.{
        .allocator = std.testing.allocator,
        .highlights = try std.testing.allocator.alloc(syntax.HighlightSpan, 0),
        .folds = try std.testing.allocator.alloc(syntax.FoldRange, 0),
        .outline = .{ .allocator = std.testing.allocator, .nodes = nodes },
    });

    var session = Session.init(std.testing.allocator);
    defer session.deinit();
    const dimensions: Dimensions = .{ .sidebar_rows = 5, .document_rows = 5, .document_columns = 80 };

    try std.testing.expectEqual(@as(usize, 0), app.activeView().?.scroll_line);
    _ = try session.handle(&app, .{ .code = .character, .character = 'n', .alt = true }, dimensions);

    const view = app.activeView().?;
    try std.testing.expectEqual(@as(usize, 20), view.snapshot.graphemes[view.active_grapheme].line);
    try std.testing.expect(view.scroll_line > 0);
}

test "git review navigation dispatches through the reducer" {
    const git = @import("../model/git.zig");
    const review_mod = @import("git_review.zig");
    var app = try testApp();
    defer app.deinit();
    app.git_enabled = true;

    const changes = try std.testing.allocator.alloc(git.Change, 1);
    changes[0] = .{ .group = .unstaged, .kind = .modified, .content = .text, .path = try std.testing.allocator.dupe(u8, "m.zig") };
    const diffs = try std.testing.allocator.alloc(git.FileDiff, 1);
    const lines = try std.testing.allocator.dupe(git.DiffLine, &.{
        .{ .kind = .context, .old_line = 1, .new_line = 1, .text = .{ .start = 0, .end = 0 } },
        .{ .kind = .deletion, .old_line = 2, .new_line = null, .text = .{ .start = 0, .end = 0 } },
        .{ .kind = .addition, .old_line = null, .new_line = 2, .text = .{ .start = 0, .end = 0 } },
    });
    const hunks = try std.testing.allocator.dupe(git.Hunk, &.{
        .{ .old_start = 1, .old_count = 2, .new_start = 1, .new_count = 2, .header = .{ .start = 0, .end = 0 }, .first_line = 0, .line_count = 3 },
    });
    diffs[0] = .{ .allocator = std.testing.allocator, .text = "", .hunks = hunks, .lines = lines };
    const review = try review_mod.Review.init(std.testing.allocator, .{ .allocator = std.testing.allocator, .changes = changes, .diffs = diffs });
    app.openReview(review);

    var session = Session.init(std.testing.allocator);
    defer session.deinit();
    const dimensions: Dimensions = .{ .sidebar_rows = 20, .document_rows = 20, .document_columns = 80 };

    // Enter focuses the diff view.
    _ = try session.handle(&app, .{ .code = .enter }, dimensions);
    try std.testing.expectEqual(state.Focus.main, app.focus);

    // ] c moves the diff cursor to the next changed line (the deletion).
    _ = try session.handle(&app, charKey(']'), dimensions);
    _ = try session.handle(&app, charKey('c'), dimensions);
    try std.testing.expectEqual(@as(usize, 1), app.review.?.diff_line);

    // Enter on a diff line requests opening the source in context.
    const effect = try session.handle(&app, .{ .code = .enter }, dimensions);
    try std.testing.expect(effect == .open_source);
    try std.testing.expectEqualStrings("m.zig", effect.open_source.path);
    try std.testing.expectEqual(@as(usize, 2), effect.open_source.line); // deletion -> old side line 2

    // ] f at the only file in the group reports a boundary.
    app.viewing_source = false;
    _ = try session.handle(&app, charKey(']'), dimensions);
    _ = try session.handle(&app, charKey('f'), dimensions);
    try std.testing.expectEqualStrings("no more files in this group", app.feedback.?);
}
