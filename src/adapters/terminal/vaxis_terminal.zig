const std = @import("std");
const vaxis = @import("vaxis");
const fiew = @import("fiew");

const Event = union(enum) {
    key_press: vaxis.Key,
    mouse: vaxis.Mouse,
    winsize: vaxis.Winsize,
    tick,
    /// A completed parse job, delivered from the worker thread. The main thread
    /// owns and frees the boxed completion.
    parse_done: *fiew.parse_job.Completion,
};

const Completion = fiew.parse_job.Completion;
const ParseFuture = std.Io.Future(void);

/// Drives off-render-loop Zig parsing for the active document: one worker at a
/// time, results routed by snapshot generation, cancelled past the one-second
/// deadline. When the grammar is unavailable the whole feature stays dormant
/// and documents render as plain text.
const ParseState = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    loop: *vaxis.Loop(Event),
    engine: ?fiew.zig_syntax.Engine,
    coordinator: fiew.parse_job.Coordinator = .{},
    cancel: std.atomic.Value(bool) = .init(false),
    future: ?ParseFuture = null,
    source: ?[]u8 = null,
    parsing_generation: ?u64 = null,
    resolved_generation: ?u64 = null,
    elapsed_ticks: u8 = 0,

    fn init(io: std.Io, allocator: std.mem.Allocator, loop: *vaxis.Loop(Event)) ParseState {
        const engine: ?fiew.zig_syntax.Engine = fiew.zig_syntax.Engine.init(allocator) catch null;
        return .{ .io = io, .allocator = allocator, .loop = loop, .engine = engine };
    }

    fn deinit(self: *ParseState) void {
        self.cancelInFlight();
        if (self.engine) |*engine| engine.deinit();
        self.* = undefined;
    }

    fn parseable(snapshot: *const fiew.document.Snapshot) bool {
        return snapshot.encoding == .utf8 and
            snapshot.bytes.len > 0 and
            snapshot.bytes.len <= fiew.zig_syntax.max_parse_bytes and
            std.mem.endsWith(u8, snapshot.path, ".zig");
    }

    /// Request analysis for the active document if it is an unparsed, parseable
    /// Zig snapshot we are not already working on.
    fn drive(self: *ParseState, app: *const fiew.app.App) void {
        if (self.engine == null) return;
        const view = app.activeView() orelse return;
        if (view.syntax != null) return;
        const snapshot = &view.snapshot;
        if (!parseable(snapshot)) return;
        if (self.parsing_generation == snapshot.generation) return;
        if (self.resolved_generation == snapshot.generation) return;
        self.submit(snapshot);
    }

    fn submit(self: *ParseState, snapshot: *const fiew.document.Snapshot) void {
        self.cancelInFlight();
        const copy = self.allocator.dupe(u8, snapshot.bytes) catch return;
        self.cancel.store(false, .release);
        self.coordinator.begin(snapshot.generation);
        const future = self.io.concurrent(parseWorker, .{
            self.io,        self.loop, &self.engine.?,
            self.allocator, copy,      snapshot.generation,
            &self.cancel,
        }) catch {
            self.allocator.free(copy);
            return;
        };
        self.source = copy;
        self.future = future;
        self.parsing_generation = snapshot.generation;
        self.elapsed_ticks = 0;
    }

    fn cancelInFlight(self: *ParseState) void {
        if (self.parsing_generation == null) return;
        self.cancel.store(true, .release);
        if (self.future) |*future| {
            _ = future.await(self.io);
            self.future = null;
        }
        if (self.source) |source| {
            self.allocator.free(source);
            self.source = null;
        }
        self.parsing_generation = null;
    }

    fn onCompletion(self: *ParseState, app: *fiew.app.App, box: *Completion) void {
        if (self.parsing_generation == box.generation) {
            if (self.future) |*future| {
                _ = future.await(self.io);
                self.future = null;
            }
            if (self.source) |source| {
                self.allocator.free(source);
                self.source = null;
            }
            self.parsing_generation = null;
            self.resolved_generation = box.generation;
            self.elapsed_ticks = 0;
        }
        if (self.coordinator.accept(box)) |data| {
            app.installParseDataForGeneration(data, box.generation);
        }
        box.deinit();
        self.allocator.destroy(box);
    }

    fn onTick(self: *ParseState) void {
        if (self.parsing_generation == null) return;
        self.elapsed_ticks +|= 1;
        // Ticks arrive every 250 ms; four of them cross the one-second deadline.
        if (self.elapsed_ticks >= 4) self.cancel.store(true, .release);
    }
};

fn parseWorker(
    io: std.Io,
    loop: *vaxis.Loop(Event),
    engine: *fiew.zig_syntax.Engine,
    allocator: std.mem.Allocator,
    source: []const u8,
    generation: u64,
    cancel: *std.atomic.Value(bool),
) void {
    _ = io;
    var context: fiew.zig_syntax.CancelContext = .{ .flag = cancel };
    const completion = fiew.parse_job.run(
        engine,
        allocator,
        .{ .generation = generation, .source = source },
        &context,
    );
    const box = allocator.create(Completion) catch {
        var owned = completion;
        owned.deinit();
        return;
    };
    box.* = completion;
    loop.postEvent(.{ .parse_done = box }) catch {
        box.deinit();
        allocator.destroy(box);
    };
}

pub fn run(init: std.process.Init) !void {
    const allocator = init.gpa;
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.skip();
    const root_path = args.next() orelse ".";

    var repository = try fiew.filesystem.Repository.open(allocator, init.io, root_path);
    defer repository.deinit();
    var app = try fiew.app.App.init(allocator, &repository.tree);
    defer app.deinit();

    // Enable the Git review only for a usable (non-bare) work tree.
    switch (fiew.git.discover(allocator, init.io, repository.root_dir) catch .not_a_repository) {
        .ready => |context| {
            var owned = context;
            owned.deinit();
            app.git_enabled = true;
        },
        else => {},
    }
    var command_session = fiew.commands.Session.init(allocator);
    defer command_session.deinit();

    const segmenter: fiew.text_segmentation.Segmenter = .{
        .next_fn = nextGrapheme,
        .width_fn = graphemeWidth,
    };
    var generation: u64 = 0;
    try previewSelection(&app, repository, segmenter, &generation);

    var read_buffer: [1024]u8 = undefined;
    var tty: vaxis.Tty = try .init(init.io, &read_buffer);
    defer tty.deinit();

    var vx = try vaxis.init(init.io, allocator, init.environ_map, .{
        .kitty_keyboard_flags = .{ .report_events = true },
    });
    defer vx.deinit(allocator, tty.writer());

    var loop: vaxis.Loop(Event) = .init(init.io, &tty, &vx);
    try loop.start();
    defer loop.stop();

    var timer_stop: std.atomic.Value(bool) = .init(false);
    var timer_task = try init.io.concurrent(timerRun, .{ init.io, &loop, &timer_stop });
    defer {
        timer_stop.store(true, .release);
        timer_task.await(init.io);
    }

    var parse_state = ParseState.init(init.io, allocator, &loop);
    defer parse_state.deinit();

    try vx.enterAltScreen(tty.writer());
    try tty.writer().flush();
    try vx.queryTerminal(tty.writer(), .fromSeconds(1));
    try vx.setMouseMode(tty.writer(), true);
    try tty.writer().flush();

    var frame_arena = std.heap.ArenaAllocator.init(allocator);
    defer frame_arena.deinit();
    while (true) {
        const event = try loop.nextEvent();
        switch (event) {
            .key_press => |key| {
                // The Kitty keyboard protocol reports lone modifier presses
                // (e.g. Shift on its way to `?` or the `M`/`R` in `z M`/`z R`).
                // Ignore them so a chord in progress is not treated as invalid.
                if (!key.isModifier()) {
                    const effect = try command_session.handle(
                        &app,
                        translateKey(key),
                        commandDimensions(vx.window(), &app),
                    );
                    if (try applyEffect(
                        &command_session,
                        &app,
                        repository,
                        segmenter,
                        &generation,
                        commandDimensions(vx.window(), &app),
                        effect,
                    )) return;
                }
            },
            .mouse => |mouse| try handleMouse(
                &app,
                repository,
                segmenter,
                &generation,
                mouse,
                vx.window(),
            ),
            .winsize => |winsize| {
                try vx.resize(allocator, tty.writer(), winsize);
                const dimensions = fiew.workspace.layout(winsize.cols, winsize.rows, app.sidebar_visible);
                const viewport_height = dimensions.content_height -| 2;
                app.browser.ensureVisible(viewport_height);
                app.ensureCurrentDocumentVisible(viewport_height, dimensions.main_width -| 6);
            },
            .tick => {
                command_session.tick(&app);
                parse_state.onTick();
            },
            .parse_done => |box| parse_state.onCompletion(&app, box),
        }

        parse_state.drive(&app);
        _ = frame_arena.reset(.retain_capacity);
        try draw(frame_arena.allocator(), vx.window(), &app, &command_session, repository.root_path);
        try vx.render(tty.writer());
        try tty.writer().flush();
    }
}

fn timerRun(
    io: std.Io,
    loop: *vaxis.Loop(Event),
    stop: *std.atomic.Value(bool),
) void {
    while (!stop.load(.acquire)) {
        io.sleep(.fromMilliseconds(250), .real) catch return;
        if (stop.load(.acquire)) return;
        loop.postEvent(.tick) catch return;
    }
}

fn commandDimensions(window: vaxis.Window, app: *const fiew.app.App) fiew.commands.Dimensions {
    const dimensions = fiew.workspace.layout(window.width, window.height, app.sidebar_visible);
    return .{
        .sidebar_rows = dimensions.content_height -| 2,
        .document_rows = dimensions.content_height -| 2,
        .document_columns = dimensions.main_width -| 6,
    };
}

fn translateKey(key: vaxis.Key) fiew.commands.Key {
    const code: fiew.commands.Code = switch (key.codepoint) {
        vaxis.Key.escape => .escape,
        vaxis.Key.enter => .enter,
        vaxis.Key.tab => .tab,
        vaxis.Key.backspace => .backspace,
        vaxis.Key.page_up => .page_up,
        vaxis.Key.page_down => .page_down,
        vaxis.Key.up => .up,
        vaxis.Key.down => .down,
        vaxis.Key.left => .left,
        vaxis.Key.right => .right,
        else => .character,
    };
    return .{
        .code = code,
        .character = if (code == .character) key.codepoint else 0,
        .shift = key.mods.shift,
        .alt = key.mods.alt,
        .ctrl = key.mods.ctrl,
    };
}

fn applyEffect(
    session: *fiew.commands.Session,
    app: *fiew.app.App,
    repository: fiew.filesystem.Repository,
    segmenter: fiew.text_segmentation.Segmenter,
    generation: *u64,
    dimensions: fiew.commands.Dimensions,
    effect: fiew.commands.Effect,
) !bool {
    switch (effect) {
        .none => {},
        .preview_selection => try previewSelection(app, repository, segmenter, generation),
        .activate_selection => {
            const node = app.browser.selectedNode() orelse return false;
            if (node.kind == .directory) {
                _ = try session.execute(app, .project_toggle, dimensions);
            } else if (node.kind == .file) {
                if (app.preview == null) try previewSelection(app, repository, segmenter, generation);
                _ = try app.pinPreview();
            }
        },
        .open_history => |location| {
            generation.* +%= 1;
            const snapshot = repository.loadDocument(location.path, generation.*, segmenter) catch |err| {
                app.feedback = @errorName(err);
                return false;
            };
            app.installHistorySnapshot(snapshot, location);
        },
        .open_review => {
            const changeset = fiew.git.loadChanges(repository.allocator, repository.io, repository.root_dir) catch |err| {
                app.feedback = @errorName(err);
                return false;
            };
            const review = fiew.git_review.Review.init(repository.allocator, changeset) catch |err| {
                var owned = changeset;
                owned.deinit();
                app.feedback = @errorName(err);
                return false;
            };
            app.openReview(review);
        },
        .open_source => |source| {
            generation.* +%= 1;
            const snapshot = repository.loadDocument(source.path, generation.*, segmenter) catch |err| {
                app.feedback = @errorName(err);
                return false;
            };
            const line_index = source.line -| 1;
            const source_start = if (line_index < snapshot.line_starts.len)
                snapshot.line_starts[line_index]
            else
                0;
            app.installHistorySnapshot(snapshot, .{
                .path = source.path,
                .source_start = source_start,
                .scroll_line = line_index -| (dimensions.document_rows / 2),
                .scroll_column = 0,
            });
            app.viewing_source = true;
        },
        .quit => return true,
    }
    return false;
}

fn handleMouse(
    app: *fiew.app.App,
    repository: fiew.filesystem.Repository,
    segmenter: fiew.text_segmentation.Segmenter,
    generation: *u64,
    mouse: vaxis.Mouse,
    window: vaxis.Window,
) !void {
    if ((mouse.type != .press and mouse.type != .drag) or
        mouse.button != .left or mouse.col < 0 or mouse.row < 0) return;
    const dimensions = fiew.workspace.layout(window.width, window.height, app.sidebar_visible);
    if (!dimensions.supported or @as(u16, @intCast(mouse.row)) >= dimensions.content_height) return;
    const column: u16 = @intCast(mouse.col);
    const row: u16 = @intCast(mouse.row);
    if (dimensions.sidebar_mode != .hidden and column < dimensions.sidebar_width) {
        if (mouse.type != .press) return;
        app.focus = .sidebar;
        if (row >= 2) {
            const visible_index = app.browser.scroll + row - 2;
            app.browser.selectVisible(visible_index, dimensions.content_height -| 2);
            try previewSelection(app, repository, segmenter, generation);
        }
    } else {
        app.focus = .main;
        if (row == 0) return;
        const view = app.activeView() orelse return;
        const line = view.scroll_line + row - 1;
        const content_column = column -| dimensions.main_column -| 6;
        app.selectAtVisualPosition(
            line,
            view.scroll_column + content_column,
            mouse.type == .drag,
            dimensions.content_height -| 2,
            dimensions.main_width -| 6,
        );
    }
}

fn previewSelection(
    app: *fiew.app.App,
    repository: fiew.filesystem.Repository,
    segmenter: fiew.text_segmentation.Segmenter,
    generation: *u64,
) !void {
    const node = app.browser.selectedNode() orelse {
        app.clearPreview();
        return;
    };
    if (node.kind != .file) {
        app.clearPreview();
        return;
    }
    generation.* +%= 1;
    const snapshot = repository.loadDocument(node.path, generation.*, segmenter) catch |err| {
        app.clearPreview();
        app.feedback = @errorName(err);
        return;
    };
    app.showPreview(snapshot);
}

fn draw(
    allocator: std.mem.Allocator,
    window: vaxis.Window,
    app: *const fiew.app.App,
    command_session: *const fiew.commands.Session,
    root_path: []const u8,
) !void {
    window.clear();
    window.hideCursor();
    const plan = fiew.render_plan.build(window.width, window.height, app, command_session);
    if (plan.kind == .unsupported) {
        _ = window.printSegment(.{
            .text = "Terminal too small; fiew requires at least 60x20",
            .style = .{ .bold = true },
        }, .{ .row_offset = window.height / 2, .wrap = .none });
        return;
    }

    const content = window.child(.{ .height = plan.main.height });
    const main = content.child(.{
        .x_off = plan.main.column,
        .width = plan.main.width,
    });
    try drawDocument(allocator, main, app);
    if (plan.sidebar_mode != .hidden) {
        const sidebar = content.child(.{
            .width = plan.sidebar.width,
            .border = .{
                .where = .right,
                .style = if (app.focus == .sidebar) .{ .bold = true } else .{},
            },
        });
        try drawSidebar(allocator, sidebar, app, root_path);
    }

    try drawCommandSurface(allocator, content, app, command_session);

    const status = window.child(.{ .y_off = plan.status.row, .height = plan.status.height });
    try drawStatus(allocator, status, app, command_session);
}

fn drawSidebar(
    allocator: std.mem.Allocator,
    window: vaxis.Window,
    app: *const fiew.app.App,
    root_path: []const u8,
) !void {
    if (app.sidebar_context == .git) return drawGitSidebar(allocator, window, app);
    _ = window.printSegment(.{
        .text = " Project ",
        .style = .{ .bold = true, .reverse = app.focus == .sidebar },
    }, .{ .wrap = .none });
    const root_name = try sanitizeLine(allocator, std.fs.path.basename(root_path), window.width -| 1);
    _ = window.printSegment(.{ .text = root_name, .style = .{ .dim = true } }, .{
        .row_offset = 1,
        .col_offset = 1,
        .wrap = .none,
    });

    const available_rows = window.height -| 2;
    const visible = app.browser.visible.items;
    var row: usize = 0;
    while (row < available_rows and app.browser.scroll + row < visible.len) : (row += 1) {
        const visible_index = app.browser.scroll + row;
        const node_index = visible[visible_index];
        const node = app.browser.tree.nodes[node_index];
        const selected = visible_index == app.browser.selected;
        const indent: u16 = @intCast(@min((node.depth -| 1) * 2 + 1, window.width));
        const marker = switch (node.kind) {
            .directory => if (app.browser.expanded[node_index]) "▾ " else "▸ ",
            .file => "  ",
            .symlink => "↗ ",
            .other => "? ",
        };
        const basename = try sanitizeLine(
            allocator,
            std.fs.path.basename(node.path),
            window.width -| indent -| 2,
        );
        _ = window.print(&.{
            .{ .text = marker, .style = .{ .reverse = selected } },
            .{ .text = basename, .style = .{ .reverse = selected, .bold = selected } },
        }, .{
            .row_offset = @intCast(row + 2),
            .col_offset = indent,
            .wrap = .none,
        });
    }
}

fn changeMarker(change: fiew.git_model.Change) []const u8 {
    return switch (change.content) {
        .submodule => "S",
        .binary => "B",
        .text => switch (change.kind) {
            .added => "+",
            .deleted => "-",
            .modified => "~",
            .renamed => "R",
            .copied => "C",
            .type_changed => "T",
            .mode_changed => "±",
            .unmerged => "U",
        },
    };
}

fn changeColor(change: fiew.git_model.Change) vaxis.Cell.Color {
    if (change.content != .text) return .default;
    return switch (change.kind) {
        .added => .{ .index = 2 }, // green
        .deleted => .{ .index = 1 }, // red
        .modified => .{ .index = 3 }, // yellow
        .renamed, .copied => .{ .index = 6 }, // cyan
        else => .default,
    };
}

fn metadataLine(allocator: std.mem.Allocator, change: fiew.git_model.Change) ![]u8 {
    if (change.kind == .mode_changed) {
        return std.fmt.allocPrint(allocator, "Mode changed: {o} → {o}", .{ change.old_mode, change.new_mode });
    }
    return switch (change.content) {
        .binary => std.fmt.allocPrint(allocator, "Binary file — no textual diff", .{}),
        .submodule => std.fmt.allocPrint(allocator, "Submodule change — no textual diff", .{}),
        .text => std.fmt.allocPrint(allocator, "No textual diff", .{}),
    };
}

fn drawGitSidebar(allocator: std.mem.Allocator, window: vaxis.Window, app: *const fiew.app.App) !void {
    _ = window.printSegment(.{
        .text = " Git ",
        .style = .{ .bold = true, .reverse = app.focus == .sidebar },
    }, .{ .wrap = .none });

    const review = if (app.review) |*value| value else {
        _ = window.printSegment(.{ .text = "No repository", .style = .{ .dim = true } }, .{ .row_offset = 2, .col_offset = 1, .wrap = .none });
        return;
    };
    if (review.isEmpty()) {
        _ = window.printSegment(.{ .text = "No changes", .style = .{ .dim = true } }, .{ .row_offset = 2, .col_offset = 1, .wrap = .none });
        return;
    }

    const available = window.height -| 1;
    var row: usize = 0;
    while (row < available and review.scroll + row < review.rows.len) : (row += 1) {
        const row_index = review.scroll + row;
        switch (review.rows[row_index]) {
            .header => |group| {
                const text = try std.fmt.allocPrint(allocator, "{s} ({d})", .{ group.title(), review.changeset.groupCount(group) });
                _ = window.printSegment(.{ .text = text, .style = .{ .bold = true } }, .{ .row_offset = @intCast(row + 1), .wrap = .none });
            },
            .change => |change_index| {
                const change = review.changeset.changes[change_index];
                const selected = row_index == review.selected;
                const name = try sanitizeLine(allocator, std.fs.path.basename(change.path), window.width -| 5);
                _ = window.print(&.{
                    .{ .text = changeMarker(change), .style = .{ .fg = changeColor(change), .bold = true, .reverse = selected } },
                    .{ .text = " " },
                    .{ .text = name, .style = .{ .reverse = selected, .bold = selected } },
                }, .{ .row_offset = @intCast(row + 1), .col_offset = 2, .wrap = .none });
            },
        }
    }
}

fn drawDiff(allocator: std.mem.Allocator, window: vaxis.Window, app: *const fiew.app.App) !void {
    const review = if (app.review) |*value| value else {
        _ = window.printSegment(.{ .text = " Diff", .style = .{ .bold = true } }, .{ .wrap = .none });
        return;
    };
    const change_index = review.selectedChange() orelse {
        _ = window.printSegment(.{ .text = " Diff", .style = .{ .bold = true, .reverse = app.focus == .main } }, .{ .wrap = .none });
        const message = if (review.isEmpty()) "No changes to review" else "Select a change";
        _ = window.printSegment(.{ .text = message, .style = .{ .dim = true } }, .{ .row_offset = 2, .col_offset = 2, .wrap = .none });
        return;
    };
    const change = review.changeset.changes[change_index];
    const diff = &review.changeset.diffs[change_index];

    const heading = try std.fmt.allocPrint(allocator, " {s}  {s}", .{ change.kind.label(), change.path });
    _ = window.print(&.{
        .{ .text = " Diff", .style = .{ .bold = true, .reverse = app.focus == .main } },
        .{ .text = try sanitizeLine(allocator, heading, window.width -| 6) },
    }, .{ .wrap = .none });

    if (!change.showsDiff()) {
        _ = window.printSegment(.{ .text = try metadataLine(allocator, change), .style = .{ .dim = true } }, .{ .row_offset = 2, .col_offset = 2, .wrap = .none });
        return;
    }
    if (diff.lines.len == 0) {
        _ = window.printSegment(.{ .text = "No textual changes", .style = .{ .dim = true } }, .{ .row_offset = 2, .col_offset = 2, .wrap = .none });
        return;
    }

    const body_rows = window.height -| 1;
    var row: usize = 0;
    var line_index = review.diff_scroll;
    while (row < body_rows and line_index < diff.lines.len) {
        for (diff.hunks) |hunk| {
            if (hunk.first_line == line_index) {
                const heading_text = diff.text[hunk.header.start..hunk.header.end];
                const header = try std.fmt.allocPrint(allocator, "@@ -{d},{d} +{d},{d} @@ {s}", .{
                    hunk.old_start, hunk.old_count, hunk.new_start, hunk.new_count, heading_text,
                });
                _ = window.printSegment(.{
                    .text = try sanitizeLine(allocator, header, window.width -| 1),
                    .style = .{ .fg = .{ .index = 6 }, .dim = true },
                }, .{ .row_offset = @intCast(row + 1), .wrap = .none });
                row += 1;
                break;
            }
        }
        if (row >= body_rows) break;

        const line = diff.lines[line_index];
        const cursor = line_index == review.diff_line and app.focus == .main;
        const color: vaxis.Cell.Color = switch (line.kind) {
            .addition => .{ .index = 2 },
            .deletion => .{ .index = 1 },
            .context => .default,
        };
        const old_number = if (line.old_line) |number|
            try std.fmt.allocPrint(allocator, "{d: >4}", .{number})
        else
            "    ";
        const new_number = if (line.new_line) |number|
            try std.fmt.allocPrint(allocator, "{d: >4}", .{number})
        else
            "    ";
        const symbol: []const u8 = switch (line.kind) {
            .addition => "+",
            .deletion => "-",
            .context => " ",
        };
        _ = window.print(&.{
            .{ .text = old_number, .style = .{ .dim = true } },
            .{ .text = " " },
            .{ .text = new_number, .style = .{ .dim = true } },
            .{ .text = " " },
            .{ .text = symbol, .style = .{ .fg = color, .bold = true } },
            .{ .text = " " },
            .{
                .text = try sanitizeLine(allocator, diff.text[line.text.start..line.text.end], window.width -| 12),
                .style = .{ .fg = color, .reverse = cursor },
            },
        }, .{ .row_offset = @intCast(row + 1), .wrap = .none });
        line_index += 1;
        row += 1;
    }
}

fn drawDocument(allocator: std.mem.Allocator, window: vaxis.Window, app: *const fiew.app.App) !void {
    if (app.sidebar_context == .git and !app.viewing_source) return drawDiff(allocator, window, app);
    const view = app.activeView() orelse {
        if (app.feedback) |name| {
            const message = try std.fmt.allocPrint(allocator, "Unable to open selected file: {s}", .{name});
            _ = window.printSegment(.{ .text = message, .style = .{ .dim = true } }, .{
                .row_offset = window.height / 2,
                .col_offset = 2,
                .wrap = .none,
            });
        } else {
            const positions = fiew.welcome.layout(window.width, window.height);
            _ = window.printSegment(.{
                .text = fiew.welcome.title,
                .style = .{ .bold = true },
            }, .{
                .row_offset = positions.title.row,
                .col_offset = positions.title.column,
                .wrap = .none,
            });
            _ = window.printSegment(.{ .text = fiew.welcome.subtitle }, .{
                .row_offset = positions.subtitle.row,
                .col_offset = positions.subtitle.column,
                .wrap = .none,
            });
        }
        return;
    };
    const snapshot = &view.snapshot;
    const safe_path = try sanitizeLine(allocator, snapshot.path, window.width -| 9);
    _ = window.print(&.{
        .{
            .text = if (app.preview != null) " Preview" else " File",
            .style = .{ .bold = true, .reverse = app.focus == .main },
        },
        .{ .text = " " },
        .{ .text = safe_path },
    }, .{ .wrap = .none });

    if (snapshot.encoding == .binary) {
        const metadata = try std.fmt.allocPrint(
            allocator,
            "Binary file — {d} bytes",
            .{snapshot.metadata.size},
        );
        _ = window.printSegment(.{ .text = metadata, .style = .{ .dim = true } }, .{
            .row_offset = 2,
            .col_offset = 2,
            .wrap = .none,
        });
        return;
    }

    const body_rows = window.height -| 2;
    const line_count = snapshot.lineCount();

    // Collect the visible lines, skipping any hidden by collapsed folds.
    var visible_lines: std.ArrayList(usize) = .empty;
    defer visible_lines.deinit(allocator);
    {
        var next = view.firstVisibleLine(view.scroll_line, line_count);
        while (visible_lines.items.len < body_rows) {
            const current = next orelse break;
            try visible_lines.append(allocator, current);
            next = view.firstVisibleLine(current + 1, line_count);
        }
    }

    // Pre-filter highlight spans to the drawn source window. This only reads
    // precomputed spans produced by the parse job — no query runs here.
    var window_spans: std.ArrayList(fiew.syntax.HighlightSpan) = .empty;
    defer window_spans.deinit(allocator);
    if (view.syntax) |data| if (visible_lines.items.len != 0) {
        const first_src = snapshot.line_starts[visible_lines.items[0]];
        const last_line = visible_lines.items[visible_lines.items.len - 1];
        const last_src = if (last_line + 1 < snapshot.line_starts.len)
            snapshot.line_starts[last_line + 1]
        else
            snapshot.bytes.len;
        for (data.highlights) |span| {
            if (span.source.end > first_src and span.source.start < last_src) {
                try window_spans.append(allocator, span);
            }
        }
    };
    const spans = window_spans.items;

    for (visible_lines.items, 0..) |line, row| {
        var range = snapshot.lineDisplayRange(line);
        if (view.scroll_column > 0) {
            const grapheme_range = snapshot.graphemeRangeForLine(line);
            range.start = range.end;
            for (snapshot.graphemes[grapheme_range.start..grapheme_range.end]) |grapheme| {
                if (grapheme.display.start >= range.end) break;
                if (grapheme.visual_column + @max(grapheme.width, 1) > view.scroll_column) {
                    range.start = grapheme.display.start;
                    break;
                }
            }
        }
        const number = try std.fmt.allocPrint(allocator, "{d: >5}", .{line + 1});
        const current_line = snapshot.graphemes.len != 0 and
            snapshot.graphemes[@min(view.active_grapheme, snapshot.graphemes.len - 1)].line == line;
        // Gutter fold marker: a triangle for a collapsed region, a dot for a
        // line that can be folded, and a blank otherwise.
        const gutter = foldGutter(view, line);
        _ = window.print(&.{
            .{
                .text = number,
                .style = .{ .dim = !current_line, .bold = current_line },
            },
            .{
                .text = switch (gutter) {
                    .closed => "▸",
                    .open => "·",
                    .none => " ",
                },
                .style = switch (gutter) {
                    .closed => .{ .fg = .{ .index = 3 }, .bold = true },
                    .open => .{ .dim = true },
                    .none => .{},
                },
            },
        }, .{ .row_offset = @intCast(row + 1), .wrap = .none });

        var segments: std.ArrayList(vaxis.Segment) = .empty;
        defer segments.deinit(allocator);
        const selected_range = view.selection();
        const grapheme_range = snapshot.graphemeRangeForLine(line);
        for (snapshot.graphemes[grapheme_range.start..grapheme_range.end]) |grapheme| {
            const selected = grapheme.source.end > selected_range.start and
                grapheme.source.start < selected_range.end;
            const grapheme_bytes = snapshot.display_bytes[grapheme.display.start..grapheme.display.end];
            const is_line_break = grapheme_bytes.len != 0 and grapheme_bytes[grapheme_bytes.len - 1] == '\n';
            if (is_line_break) {
                if (selectedLineBreakVisible(
                    grapheme,
                    selected_range,
                    view.scroll_column,
                    window.width -| 6,
                )) {
                    try segments.append(allocator, .{
                        .text = " ",
                        .style = .{ .reverse = true },
                    });
                }
                continue;
            }
            if (grapheme.display.end <= range.start or grapheme.display.start >= range.end) continue;
            if (grapheme.visual_column >= view.scroll_column + window.width -| 6) break;
            const display_start = @max(grapheme.display.start, range.start);
            const display_end = @min(grapheme.display.end, range.end);
            var style: vaxis.Cell.Style = .{ .reverse = selected };
            if (!selected) if (highlightKindAt(spans, grapheme.source.start)) |kind| {
                style.fg = highlightColor(kind);
                if (kind == .comment) style.dim = true;
            };
            try segments.append(allocator, .{
                .text = try sanitizeLine(
                    allocator,
                    snapshot.display_bytes[display_start..display_end],
                    window.width -| 6,
                ),
                .style = style,
            });
        }
        if (isClosedFoldStart(view, line)) {
            try segments.append(allocator, .{ .text = " ⋯", .style = .{ .dim = true } });
        }
        if (segments.items.len != 0) {
            _ = window.print(segments.items, .{
                .row_offset = @intCast(row + 1),
                .col_offset = 6,
                .wrap = .none,
            });
        }
    }

    if (snapshot.encoding == .invalid_utf8 and window.height > 1) {
        _ = window.printSegment(.{ .text = "invalid UTF-8", .style = .{ .bold = true } }, .{
            .row_offset = 0,
            .col_offset = window.width -| 13,
            .wrap = .none,
        });
    }
}

fn drawCommandSurface(
    allocator: std.mem.Allocator,
    window: vaxis.Window,
    app: *const fiew.app.App,
    session: *const fiew.commands.Session,
) !void {
    switch (session.surface) {
        .none => {},
        .leader => {
            const menu = window.child(.{ .y_off = window.height -| 2, .height = 2 });
            menu.clear();
            _ = menu.printSegment(.{ .text = " Leader ", .style = .{ .bold = true, .reverse = true } }, .{ .wrap = .none });
            _ = menu.printSegment(.{
                .text = "f files  b Project  g Git  r Review [not implemented]  ? help  q quit",
            }, .{ .row_offset = 1, .col_offset = 1, .wrap = .none });
        },
        .file => {
            const menu = window.child(.{ .y_off = window.height -| 2, .height = 2 });
            menu.clear();
            _ = menu.printSegment(.{ .text = " File commands ", .style = .{ .bold = true, .reverse = true } }, .{ .wrap = .none });
            _ = menu.printSegment(.{ .text = "Enter  open or pin selected Project file" }, .{
                .row_offset = 1,
                .col_offset = 1,
                .wrap = .none,
            });
        },
        .command => {
            const height: u16 = @min(window.height, 10);
            const prompt = window.child(.{ .y_off = window.height - height, .height = height });
            prompt.clear();
            const query = try std.fmt.allocPrint(allocator, ":{s}", .{session.query.items});
            _ = prompt.printSegment(.{ .text = query, .style = .{ .bold = true, .reverse = true } }, .{ .wrap = .none });
            const visible_count = @min(session.filteredCount(), height -| 1);
            const start = if (session.selected_command >= visible_count and visible_count != 0)
                session.selected_command - visible_count + 1
            else
                0;
            for (0..visible_count) |row| {
                const index = start + row;
                const id = session.filteredCommand(index) orelse break;
                const command = fiew.commands.definition(id);
                const selected = index == session.selected_command;
                const reason = fiew.commands.unavailableReason(app, id) orelse "";
                const line = try std.fmt.allocPrint(
                    allocator,
                    "{s:<24} {s:<18} {s}",
                    .{ command.stable_id, command.binding, reason },
                );
                _ = prompt.printSegment(.{
                    .text = line,
                    .style = .{ .reverse = selected, .dim = reason.len != 0 },
                }, .{ .row_offset = @intCast(row + 1), .col_offset = 1, .wrap = .none });
            }
        },
        .help => {
            window.clear();
            _ = window.printSegment(.{ .text = " fiew key help — generated from command registry ", .style = .{ .bold = true, .reverse = true } }, .{ .wrap = .none });
            const available_rows: usize = window.height -| 2;
            const end = @min(session.help_scroll + available_rows, fiew.commands.definitions.len);
            for (fiew.commands.definitions[session.help_scroll..end], 0..) |command, index| {
                const reason = fiew.commands.unavailableReason(app, command.id) orelse "";
                const line = try std.fmt.allocPrint(
                    allocator,
                    "{s:<14} {s:<26} {s}",
                    .{ command.binding, command.title, reason },
                );
                _ = window.printSegment(.{
                    .text = line,
                    .style = .{ .dim = reason.len != 0 },
                }, .{ .row_offset = @intCast(index + 1), .col_offset = 1, .wrap = .none });
            }
            _ = window.printSegment(.{ .text = "j/k scroll · q or Esc closes help", .style = .{ .bold = true } }, .{
                .row_offset = window.height -| 1,
                .col_offset = 1,
                .wrap = .none,
            });
        },
    }
}

fn drawStatus(
    allocator: std.mem.Allocator,
    window: vaxis.Window,
    app: *const fiew.app.App,
    session: *const fiew.commands.Session,
) !void {
    const location = if (app.activeView()) |view| location: {
        if (view.snapshot.graphemes.len == 0) break :location "";
        const active = view.snapshot.graphemes[
            @min(
                view.active_grapheme,
                view.snapshot.graphemes.len - 1,
            )
        ];
        break :location try std.fmt.allocPrint(
            allocator,
            "line {d} col {d}",
            .{ active.line + 1, active.visual_column + 1 },
        );
    } else "";
    const feedback = app.feedback orelse "";
    const text = try std.fmt.allocPrint(
        allocator,
        " {s}  pending:{s}  {s}  {s}",
        .{ @tagName(app.mode), session.pendingLabel(), location, feedback },
    );
    _ = window.printSegment(.{ .text = text, .style = .{ .reverse = true } }, .{ .wrap = .none });
}

fn highlightKindAt(spans: []const fiew.syntax.HighlightSpan, position: usize) ?fiew.syntax.HighlightKind {
    var best: ?fiew.syntax.HighlightKind = null;
    var best_length: usize = std.math.maxInt(usize);
    for (spans) |span| {
        if (span.source.start <= position and span.source.end > position) {
            const length = span.source.end - span.source.start;
            if (length < best_length) {
                best_length = length;
                best = span.kind;
            }
        }
    }
    return best;
}

fn highlightColor(kind: fiew.syntax.HighlightKind) vaxis.Cell.Color {
    return switch (kind) {
        .keyword => .{ .index = 5 }, // magenta
        .type => .{ .index = 3 }, // yellow
        .function => .{ .index = 4 }, // blue
        .string => .{ .index = 2 }, // green
        .number, .constant => .{ .index = 6 }, // cyan
        .comment => .{ .index = 8 }, // bright black
        .label => .{ .index = 1 }, // red
        .operator, .punctuation, .variable => .default,
    };
}

fn isClosedFoldStart(view: *const fiew.app.View, line: usize) bool {
    for (view.closed_folds.items) |start| if (start == line) return true;
    return false;
}

const FoldGutter = enum { none, open, closed };

fn foldGutter(view: *const fiew.app.View, line: usize) FoldGutter {
    const data = view.syntax orelse return .none;
    var foldable = false;
    for (data.folds) |fold| {
        if (fold.start_line == line and fold.isFoldable()) {
            foldable = true;
            break;
        }
    }
    if (!foldable) return .none;
    return if (isClosedFoldStart(view, line)) .closed else .open;
}

fn selectedLineBreakVisible(
    grapheme: fiew.document.Grapheme,
    selection: fiew.document.ByteRange,
    scroll_column: u32,
    viewport_width: u16,
) bool {
    const selected = grapheme.source.end > selection.start and grapheme.source.start < selection.end;
    return selected and grapheme.visual_column >= scroll_column and
        grapheme.visual_column < scroll_column + viewport_width;
}

fn sanitizeLine(allocator: std.mem.Allocator, text: []const u8, max_columns: u16) ![]u8 {
    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(allocator);
    var index: usize = 0;
    var columns: usize = 0;
    while (index < text.len and columns < max_columns) {
        const length = std.unicode.utf8ByteSequenceLength(text[index]) catch 1;
        if (length == 1 and (text[index] < 0x20 or text[index] == 0x7f)) {
            if (text[index] == '\t') {
                const spaces = @min(@as(usize, 4), max_columns - columns);
                try result.appendNTimes(allocator, ' ', spaces);
                columns += spaces;
            } else {
                try result.appendSlice(allocator, "\u{fffd}");
                columns += 1;
            }
            index += 1;
            continue;
        }
        try result.appendSlice(allocator, text[index .. index + length]);
        index += length;
        columns += 1;
    }
    return result.toOwnedSlice(allocator);
}

fn nextGrapheme(_: ?*const anyopaque, text: []const u8, start: usize) usize {
    var iterator = vaxis.unicode.graphemeIterator(text[start..]);
    const grapheme = iterator.next() orelse return text.len;
    return start + grapheme.len;
}

fn graphemeWidth(_: ?*const anyopaque, grapheme: []const u8) u16 {
    return vaxis.gwidth.gwidth(grapheme, .unicode);
}

test "selected end-of-document newline receives a visible marker" {
    const newline: fiew.document.Grapheme = .{
        .source = .{ .start = 5, .end = 6 },
        .display = .{ .start = 5, .end = 6 },
        .line = 0,
        .visual_column = 5,
        .width = 0,
    };
    try std.testing.expect(selectedLineBreakVisible(
        newline,
        .{ .start = 5, .end = 6 },
        0,
        80,
    ));
    try std.testing.expect(!selectedLineBreakVisible(
        newline,
        .{ .start = 0, .end = 1 },
        0,
        80,
    ));
}

test "terminal text sanitization cannot emit control sequences" {
    const sanitized = try sanitizeLine(std.testing.allocator, "ok\x1b[31m\tend", 80);
    defer std.testing.allocator.free(sanitized);
    try std.testing.expect(std.mem.indexOfScalar(u8, sanitized, 0x1b) == null);
    try std.testing.expectEqualStrings("ok\u{fffd}[31m    end", sanitized);
}

test "Unicode grapheme segmentation preserves source byte ranges" {
    var snapshot = try fiew.document.Snapshot.init(
        std.testing.allocator,
        "unicode.txt",
        "a\u{301}👩‍💻x",
        1,
        .{ .size = 15 },
        .{ .next_fn = nextGrapheme, .width_fn = graphemeWidth },
    );
    defer snapshot.deinit();

    try std.testing.expectEqual(@as(usize, 3), snapshot.graphemes.len);
    try std.testing.expectEqual(
        fiew.document.ByteRange{ .start = 0, .end = 3 },
        snapshot.graphemes[0].source,
    );
    try std.testing.expectEqual(
        fiew.document.ByteRange{ .start = 3, .end = 14 },
        snapshot.graphemes[1].source,
    );
    try std.testing.expectEqual(@as(u16, 2), snapshot.graphemes[1].width);
}
