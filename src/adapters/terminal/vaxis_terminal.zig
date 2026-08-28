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
    git_done: *fiew.git_job.Completion,
    git_probe_done: *GitProbeCompletion,
};

const Completion = fiew.parse_job.Completion;
const ParseFuture = std.Io.Future(void);
const GitFuture = std.Io.Future(void);

const GitProbeCompletion = union(enum) {
    success: fiew.git.Fingerprint,
    failure: fiew.git_job.Failure,
};

/// Owns the single bounded Git worker slot. New requests supersede old
/// generations; obsolete completions are destroyed without publishing.
const GitLoadState = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    loop: *vaxis.Loop(Event),
    future: ?GitFuture = null,
    running_generation: ?u64 = null,
    queued_generation: ?u64 = null,
    probing: bool = false,
    last_fingerprint: ?fiew.git.Fingerprint = null,
    probe_ticks: u8 = 0,

    fn init(io: std.Io, allocator: std.mem.Allocator, loop: *vaxis.Loop(Event)) GitLoadState {
        return .{ .io = io, .allocator = allocator, .loop = loop };
    }

    fn deinit(self: *GitLoadState) void {
        if (self.future) |*future| _ = future.await(self.io);
        self.* = undefined;
    }

    fn submit(self: *GitLoadState, repository: fiew.filesystem.Repository, generation: u64) void {
        if (self.future != null) {
            self.queued_generation = generation;
            return;
        }
        self.probing = false;
        self.future = self.io.concurrent(gitWorker, .{
            self.loop, self.allocator, repository.io, repository.root_dir, generation,
        }) catch {
            self.queued_generation = generation;
            return;
        };
        self.running_generation = generation;
    }

    fn onCompletion(
        self: *GitLoadState,
        app: *fiew.app.App,
        repository: fiew.filesystem.Repository,
        box: *fiew.git_job.Completion,
    ) void {
        if (self.running_generation == box.generation) {
            if (self.future) |*future| _ = future.await(self.io);
            self.future = null;
            self.running_generation = null;
        }

        if (box.generation == app.git_generation) switch (box.result) {
            .success => {
                if (fiew.git_job.accept(box, app.git_generation)) |snapshot| {
                    self.last_fingerprint = snapshot.fingerprint;
                    const review = fiew.git_review.Review.init(self.allocator, snapshot.changeset) catch |err| {
                        var owned = snapshot.changeset;
                        owned.deinit();
                        app.failGitRefresh(box.generation, @errorName(err));
                        box.deinit();
                        self.allocator.destroy(box);
                        return;
                    };
                    app.openReview(review);
                    const accepted = app.review.?.changeset;
                    if (app.notes) |*state_notes| {
                        state_notes.reanchor(accepted) catch |err| {
                            app.feedback = @errorName(err);
                        };
                        if (state_notes.hasDirty() and !flushNotes(repository, state_notes))
                            app.feedback = "review re-anchor persistence failed; changes remain dirty";
                    }
                    reanchorBookmarks(repository, app, accepted);
                }
            },
            .failure => |failure| app.failGitRefresh(box.generation, failure.message()),
        };
        box.deinit();
        self.allocator.destroy(box);

        if (self.queued_generation) |generation| {
            self.queued_generation = null;
            if (generation == app.git_generation) self.submit(repository, generation);
        }
    }

    /// Poll a cheap Git fingerprint once per second. A changed fingerprint is
    /// debounced into one generation-gated full refresh.
    fn onTick(self: *GitLoadState, app: *fiew.app.App, repository: fiew.filesystem.Repository) void {
        if (!app.git_enabled or app.review == null or app.git_status == .pending or self.future != null) {
            self.probe_ticks = 0;
            return;
        }
        self.probe_ticks +|= 1;
        if (self.probe_ticks < 4) return;
        self.probe_ticks = 0;
        self.probing = true;
        self.future = self.io.concurrent(gitProbeWorker, .{
            self.loop, self.allocator, repository.io, repository.root_dir,
        }) catch {
            self.probing = false;
            return;
        };
    }

    fn onProbeCompletion(
        self: *GitLoadState,
        app: *fiew.app.App,
        repository: fiew.filesystem.Repository,
        box: *GitProbeCompletion,
    ) void {
        if (self.probing) {
            if (self.future) |*future| _ = future.await(self.io);
            self.future = null;
            self.probing = false;
        }
        const changed = switch (box.*) {
            .success => |fingerprint| if (self.last_fingerprint) |last|
                !std.mem.eql(u8, &last, &fingerprint)
            else
                true,
            .failure => |failure| blk: {
                app.git_status = .stale;
                app.feedback = failure.message();
                break :blk false;
            },
        };
        self.allocator.destroy(box);

        if (self.queued_generation) |generation| {
            self.queued_generation = null;
            if (generation == app.git_generation) self.submit(repository, generation);
        } else if (changed) {
            self.submit(repository, app.beginGitRefresh());
        }
    }
};

fn gitWorker(
    loop: *vaxis.Loop(Event),
    allocator: std.mem.Allocator,
    io: std.Io,
    root_dir: std.Io.Dir,
    generation: u64,
) void {
    const result: fiew.git_job.Result = if (fiew.git.loadSnapshot(allocator, io, root_dir)) |snapshot|
        .{ .success = snapshot }
    else |err|
        .{ .failure = fiew.git_job.failureFromError(err) };
    const box = allocator.create(fiew.git_job.Completion) catch {
        var owned = result;
        owned.deinit();
        return;
    };
    box.* = .{ .generation = generation, .result = result };
    loop.postEvent(.{ .git_done = box }) catch {
        box.deinit();
        allocator.destroy(box);
    };
}

fn gitProbeWorker(
    loop: *vaxis.Loop(Event),
    allocator: std.mem.Allocator,
    io: std.Io,
    root_dir: std.Io.Dir,
) void {
    const result: GitProbeCompletion = if (fiew.git.fingerprint(allocator, io, root_dir)) |value|
        .{ .success = value }
    else |err|
        .{ .failure = fiew.git_job.failureFromError(err) };
    const box = allocator.create(GitProbeCompletion) catch return;
    box.* = result;
    loop.postEvent(.{ .git_probe_done = box }) catch allocator.destroy(box);
}

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

pub const Options = struct {
    root_path: []const u8 = ".",
    review_filename: ?[]const u8 = null,
};

pub fn run(init: std.process.Init, options: Options) !u8 {
    const allocator = init.gpa;
    const root_path = options.root_path;
    const review_name = options.review_filename;

    // Discover once from the requested path, then make the discovered worktree
    // top level the one root used by Project, Git, source, reviews, and state.
    var requested_dir = try std.Io.Dir.cwd().openDir(init.io, root_path, .{});
    defer requested_dir.close(init.io);
    var canonical_root: ?[]u8 = null;
    defer if (canonical_root) |path| allocator.free(path);
    var git_ready = false;
    switch (fiew.git.discover(allocator, init.io, requested_dir) catch .not_a_repository) {
        .ready => |context| {
            var owned = context;
            defer owned.deinit();
            canonical_root = try allocator.dupe(u8, owned.toplevel);
            git_ready = true;
        },
        else => {},
    }

    var repository = try fiew.filesystem.Repository.open(allocator, init.io, canonical_root orelse root_path);
    defer repository.deinit();
    var app = try fiew.app.App.init(allocator, &repository.tree);
    defer app.deinit();
    app.git_enabled = git_ready;
    app.git_status = if (git_ready) .idle else .disabled;
    const quote_time = std.Io.Timestamp.now(init.io, .real).nanoseconds;
    app.welcome_quote = fiew.welcome.selectSeed(quote_time);

    bookmark_setup: {
        var canonical_buffer: [std.fs.max_path_bytes]u8 = undefined;
        const canonical_length = repository.root_dir.realPath(init.io, &canonical_buffer) catch {
            app.feedback = "bookmark repository path unavailable";
            break :bookmark_setup;
        };
        var result = fiew.bookmark_store.load(allocator, init.io, repository.root_dir) catch {
            app.feedback = "bookmark storage unreadable";
            break :bookmark_setup;
        };
        switch (result) {
            .loaded => |*loaded| {
                defer loaded.deinit();
                app.bookmarks = fiew.bookmarks.Bookmarks.fromStored(
                    allocator,
                    canonical_buffer[0..canonical_length],
                    loaded.value().*,
                ) catch {
                    app.feedback = "bookmark storage unavailable";
                    break :bookmark_setup;
                };
            },
            .absent => app.bookmarks = fiew.bookmarks.Bookmarks.init(
                allocator,
                canonical_buffer[0..canonical_length],
            ) catch {
                app.feedback = "bookmark storage unavailable";
                break :bookmark_setup;
            },
            .future_schema => {
                app.feedback = "future bookmark schema refused";
                break :bookmark_setup;
            },
            .unrecoverable => {
                app.feedback = "bookmark state is unrecoverable";
                break :bookmark_setup;
            },
        }
        app.bookmarks_available = true;
    }

    // A named review loads exactly that file. Ordinary browsing loads only the
    // explicit current review, never inferring or mutating historical sessions.
    {
        var loaded: fiew.review_store.Loaded = if (review_name) |name|
            try fiew.review_store.loadOne(allocator, init.io, repository.root_dir, name)
        else current: {
            const id = fiew.review_store.currentId(allocator, init.io, repository.root_dir) catch |err| {
                if (err != error.CurrentReviewMissing) app.feedback = @errorName(err);
                break :current .{ .allocator = allocator, .entries = &.{} };
            };
            defer allocator.free(id);
            const filename = try fiew.review_cli.filenameForId(allocator, id);
            defer allocator.free(filename);
            break :current fiew.review_store.loadOne(allocator, init.io, repository.root_dir, filename) catch |err| {
                app.feedback = @errorName(err);
                break :current .{ .allocator = allocator, .entries = &.{} };
            };
        };
        defer loaded.deinit();
        app.notes = if (review_name != null)
            try fiew.notes.Notes.fromLoaded(allocator, loaded)
        else
            fiew.notes.Notes.fromLoaded(allocator, loaded) catch null;
    }
    if (review_name) |name| {
        if (app.notes) |*state_notes| state_notes.useSession(name);
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
    var git_state = GitLoadState.init(init.io, allocator, &loop);
    defer git_state.deinit();

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
                        review_name,
                        &git_state,
                    )) {
                        // Exit code reports whether the named review has blocking
                        // threads or unsaved state. Cleanup
                        // defers restore the terminal before we return.
                        if (review_name) |name| {
                            if (app.notes) |*state_notes| {
                                if (!state_notes.approved(name)) return 1;
                            }
                        }
                        return 0;
                    }
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
                git_state.onTick(&app, repository);
            },
            .parse_done => |box| parse_state.onCompletion(&app, box),
            .git_done => |box| git_state.onCompletion(&app, repository, box),
            .git_probe_done => |box| git_state.onProbeCompletion(&app, repository, box),
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
        .character = if (code == .character) producedCharacter(key) else 0,
        .shift = key.mods.shift,
        .alt = key.mods.alt,
        .ctrl = key.mods.ctrl,
    };
}

/// The glyph a key event actually produces. Under the Kitty keyboard protocol
/// `codepoint` is the unshifted base key (Shift-1 reports `1`, not `!`), so the
/// produced text lives in `text`/`shifted_codepoint`. Prefer those for insertion
/// while still falling back to the base codepoint for plain keys and shortcuts.
fn producedCharacter(key: vaxis.Key) u21 {
    if (key.text) |text| {
        var it = (std.unicode.Utf8View.init(text) catch return key.codepoint).iterator();
        if (it.nextCodepoint()) |first| {
            // Only trust single-codepoint text; anything longer is not a
            // literal character insert.
            if (it.nextCodepoint() == null) return first;
        }
    }
    return key.shifted_codepoint orelse key.codepoint;
}

fn applyEffect(
    session: *fiew.commands.Session,
    app: *fiew.app.App,
    repository: fiew.filesystem.Repository,
    segmenter: fiew.text_segmentation.Segmenter,
    generation: *u64,
    dimensions: fiew.commands.Dimensions,
    effect: fiew.commands.Effect,
    review_name: ?[]const u8,
    git_state: *GitLoadState,
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
        .open_review => |git_generation| git_state.submit(repository, git_generation),
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
        .preview_bookmark => |source| {
            try openBookmark(
                app,
                repository,
                segmenter,
                generation,
                source,
                false,
                dimensions.document_rows,
            );
        },
        .activate_bookmark => |source| {
            try openBookmark(
                app,
                repository,
                segmenter,
                generation,
                source,
                true,
                dimensions.document_rows,
            );
        },
        .save_bookmark => {
            const state_bookmarks = if (app.bookmarks) |*value| value else {
                app.cancelBookmarkComposer();
                return false;
            };
            const composer = if (app.bookmark_composer) |*value| value else return false;
            generation.* +%= 1;
            var snapshot = repository.loadDocument(composer.target.path, generation.*, segmenter) catch |err| {
                app.feedback = @errorName(err);
                return false;
            };
            defer snapshot.deinit();
            const line_index = composer.target.line -| 1;
            var source_offset = if (line_index < snapshot.line_starts.len)
                snapshot.line_starts[line_index]
            else
                composer.target.source_offset;
            if (line_index < snapshot.lineCount()) {
                const range = snapshot.graphemeRangeForLine(line_index);
                for (snapshot.graphemes[range.start..range.end]) |grapheme| {
                    source_offset = grapheme.source.start;
                    if (grapheme.visual_column >= composer.target.column) break;
                }
            }
            const target_start = fiew.anchor.lineStart(snapshot.bytes, source_offset);
            const target_end = fiew.anchor.lineEnd(snapshot.bytes, source_offset);
            const context = try fiew.anchor.capture(repository.allocator, snapshot.bytes, target_start, target_end);
            defer repository.allocator.free(context.bytes);
            try state_bookmarks.add(
                composer.target.path,
                composer.target.line,
                composer.target.column,
                source_offset,
                context,
                composer.buffer.items,
            );
            app.cancelBookmarkComposer();
            if (!persistBookmarks(repository, state_bookmarks))
                app.feedback = "bookmark persistence failed; changes remain dirty";
        },
        .persist_bookmarks => {
            if (app.bookmarks) |*state_bookmarks| {
                if (!persistBookmarks(repository, state_bookmarks))
                    app.feedback = "bookmark persistence failed; changes remain dirty";
            }
        },
        .save_note => {
            const state_notes = if (app.notes) |*value| value else {
                app.cancelComposer();
                return false;
            };
            if (app.composer) |*composer| {
                if (composer.anchor) |anchor| {
                    var name_buffer: [64]u8 = undefined;
                    var created_buffer: [32]u8 = undefined;
                    var sha_buffer: [64]u8 = undefined;
                    var note_session = buildNoteSession(
                        repository,
                        review_name,
                        &name_buffer,
                        &created_buffer,
                        &sha_buffer,
                    );
                    var created_review: ?fiew.review_cli.Created = null;
                    defer if (created_review) |*created| created.deinit();
                    if (review_name == null and state_notes.session == null) {
                        const now = std.Io.Timestamp.now(repository.io, .real).nanoseconds;
                        const seconds: u64 = @intCast(@divFloor(now, std.time.ns_per_s));
                        created_review = try fiew.review_cli.create(
                            repository.allocator,
                            repository.io,
                            repository.root_dir,
                            seconds,
                            null,
                            note_session.base_sha,
                        );
                        note_session.filename = created_review.?.filename;
                    }
                    const comments = try repository.allocator.alloc(fiew.review.Comment, 1);
                    comments[0] = .{
                        .author = .reviewer,
                        .body = try repository.allocator.dupe(u8, composer.buffer.items),
                    };
                    const anchor_context = anchor.context orelse return error.MissingAnchorContext;
                    const thread: fiew.review.Thread = .{
                        .id = try state_notes.nextId(repository.allocator),
                        .path = try repository.allocator.dupe(u8, anchor.path),
                        .group = anchor.group,
                        .status = .open,
                        .lifecycle = .open,
                        .validity = .current,
                        .context = .{
                            .bytes = try repository.allocator.dupe(u8, anchor_context.bytes),
                            .original_start = anchor_context.original_start,
                            .target_start = anchor_context.target_start,
                            .target_end = anchor_context.target_end,
                        },
                        .side = anchor.side,
                        .start_line = anchor.start_line,
                        .end_line = anchor.end_line,
                        .blob = if (anchor.blob) |blob| try repository.allocator.dupe(u8, blob) else null,
                        .excerpt = if (anchor.excerpt) |excerpt| try repository.allocator.dupe(u8, excerpt) else null,
                        .comments = comments,
                    };
                    try state_notes.addThread(.reviewer, note_session, thread);
                } else if (state_notes.selectedRef()) |ref| {
                    try state_notes.appendComment(ref, .reviewer, try repository.allocator.dupe(u8, composer.buffer.items));
                }
                app.cancelComposer();
            }
            if (!flushNotes(repository, state_notes)) app.feedback = "review persistence failed; changes remain dirty";
        },
        .quit => {
            if (app.notes) |*state_notes| {
                if (state_notes.hasDirty() and !flushNotes(repository, state_notes)) {
                    app.feedback = "review persistence failed; quit cancelled";
                    return false;
                }
            }
            if (app.bookmarks) |*state_bookmarks| {
                if (!persistBookmarks(repository, state_bookmarks)) {
                    app.feedback = "bookmark persistence failed; quit cancelled";
                    return false;
                }
            }
            return true;
        },
    }
    return false;
}

/// Metadata for the session's review file, generated once per note batch.
fn buildNoteSession(
    repository: fiew.filesystem.Repository,
    override_name: ?[]const u8,
    name_buffer: []u8,
    created_buffer: []u8,
    sha_buffer: []u8,
) fiew.notes.SessionInit {
    const nanoseconds = std.Io.Timestamp.now(repository.io, .real).nanoseconds;
    const seconds: u64 = @intCast(@divFloor(nanoseconds, std.time.ns_per_s));
    const created = formatTimestamp(created_buffer, seconds);
    const filename = override_name orelse (std.fmt.bufPrint(name_buffer, "review-{d}.json", .{seconds}) catch "review.json");

    var sha: []const u8 = "";
    var output = fiew.git_command.run(repository.allocator, repository.io, repository.root_dir, &.{ "rev-parse", "HEAD" }) catch null;
    if (output) |*result| {
        defer result.deinit();
        if (result.succeeded()) {
            const line = std.mem.trimEnd(u8, std.mem.sliceTo(result.stdout, '\n'), "\r");
            const length = @min(line.len, sha_buffer.len);
            @memcpy(sha_buffer[0..length], line[0..length]);
            sha = sha_buffer[0..length];
        }
    }
    return .{ .filename = filename, .base_ref = "HEAD", .base_sha = sha, .created = created };
}

fn formatTimestamp(buffer: []u8, unix_seconds: u64) []const u8 {
    const epoch: std.time.epoch.EpochSeconds = .{ .secs = unix_seconds };
    const day = epoch.getEpochDay();
    const year_day = day.calculateYearDay();
    const month_day = year_day.calculateMonthDay();
    const day_seconds = epoch.getDaySeconds();
    return std.fmt.bufPrint(buffer, "{d:0>4}-{d:0>2}-{d:0>2}T{d:0>2}:{d:0>2}:{d:0>2}Z", .{
        year_day.year,
        month_day.month.numeric(),
        month_day.day_index + 1,
        day_seconds.getHoursIntoDay(),
        day_seconds.getMinutesIntoHour(),
        day_seconds.getSecondsIntoMinute(),
    }) catch "1970-01-01T00:00:00Z";
}

/// Persist dirty review files and delete emptied ones.
fn flushNotes(repository: fiew.filesystem.Repository, state_notes: *fiew.notes.Notes) bool {
    var success = true;
    var buffer: [64]fiew.notes.Notes.DirtyFile = undefined;
    const dirty = state_notes.dirtyFiles(&buffer);
    for (dirty) |file| {
        fiew.review_store.save(repository.allocator, repository.io, repository.root_dir, file.filename, file.review) catch {
            success = false;
            continue;
        };
        state_notes.markClean(file.filename);
    }
    var index: usize = 0;
    while (index < state_notes.removedFiles().len) {
        const name = state_notes.removedFiles()[index];
        fiew.review_store.remove(repository.io, repository.root_dir, name) catch {
            success = false;
            index += 1;
            continue;
        };
        state_notes.markRemoved(name);
    }
    return success and !state_notes.hasDirty();
}

fn reanchorBookmarks(repository: fiew.filesystem.Repository, app: *fiew.app.App, changeset: fiew.git_model.ChangeSet) void {
    const state_bookmarks = if (app.bookmarks) |*value| value else return;
    var index: usize = 0;
    while (index < state_bookmarks.items.items.len) : (index += 1) {
        const stored_path = repository.allocator.dupe(u8, state_bookmarks.items.items[index].path) catch continue;
        defer repository.allocator.free(stored_path);
        var candidate_path: []const u8 = stored_path;
        var renamed = false;
        for (changeset.changes) |change| {
            if (change.kind == .renamed and change.old_path != null and std.mem.eql(u8, change.old_path.?, stored_path)) {
                candidate_path = change.path;
                renamed = true;
                break;
            }
        }
        const bytes = repository.root_dir.readFileAlloc(
            repository.io,
            candidate_path,
            repository.allocator,
            .limited64(2 << 20),
        ) catch {
            state_bookmarks.markPathOutdated(stored_path);
            continue;
        };
        defer repository.allocator.free(bytes);
        if (renamed)
            state_bookmarks.reanchorRenamedPath(stored_path, candidate_path, bytes) catch {
                app.feedback = "bookmark rename re-anchor failed";
            }
        else
            state_bookmarks.reanchorPath(stored_path, bytes);
    }
    if (state_bookmarks.dirty and !persistBookmarks(repository, state_bookmarks))
        app.feedback = "bookmark re-anchor persistence failed; changes remain dirty";
}

fn persistBookmarks(repository: fiew.filesystem.Repository, state_bookmarks: *fiew.bookmarks.Bookmarks) bool {
    if (!state_bookmarks.dirty) return true;
    fiew.bookmark_store.save(repository.allocator, repository.io, repository.root_dir, state_bookmarks.stored()) catch return false;
    state_bookmarks.markClean();
    return true;
}

fn openBookmark(
    app: *fiew.app.App,
    repository: fiew.filesystem.Repository,
    segmenter: fiew.text_segmentation.Segmenter,
    generation: *u64,
    source: fiew.commands.SourceLocation,
    activate: bool,
    document_rows: usize,
) !void {
    generation.* +%= 1;
    const snapshot = repository.loadDocument(source.path, generation.*, segmenter) catch |err| {
        if (app.bookmarks) |*state_bookmarks| {
            state_bookmarks.markSelectedOutdated();
            _ = persistBookmarks(repository, state_bookmarks);
        }
        app.feedback = @errorName(err);
        return;
    };
    var effective_line = source.line;
    var effective_column = source.column;
    if (app.bookmarks) |*state_bookmarks| {
        state_bookmarks.reanchorPath(source.path, snapshot.bytes);
        if (state_bookmarks.selectedBookmark()) |item| {
            effective_line = item.line;
            effective_column = item.column;
        }
        _ = persistBookmarks(repository, state_bookmarks);
    }
    app.showPreview(snapshot);
    app.positionPreviewAtLine(effective_line, effective_column);
    if (activate) {
        _ = try app.pinPreview();
        if (app.activeViewMut()) |view| view.scroll_line = effective_line -| 1 -| (document_rows / 2);
    }
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
        if (row >= 1 and app.sidebar_context == .review) {
            if (app.notes) |*threads| threads.selectVisible(row - 1, dimensions.content_height -| 1);
            return;
        }
        if (row >= 1 and app.sidebar_context == .bookmarks) {
            if (app.bookmarks) |*state_bookmarks| {
                state_bookmarks.selectVisible(row - 1, dimensions.content_height -| 1);
                if (state_bookmarks.selectedBookmark()) |item| try openBookmark(
                    app,
                    repository,
                    segmenter,
                    generation,
                    .{ .path = item.path, .line = item.line, .column = item.column },
                    false,
                    dimensions.content_height,
                );
            }
            return;
        }
        if (row >= 2) {
            const visible_index = app.browser.scroll + row - 2;
            app.browser.selectVisible(visible_index, dimensions.content_height -| 2);
            try previewSelection(app, repository, segmenter, generation);
        }
    } else {
        app.focus = .main;
        if (app.sidebar_context == .review) return;
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
    if (app.sidebar_context == .review) return drawReviewSidebar(allocator, window, app);
    if (app.sidebar_context == .bookmarks) return drawBookmarksSidebar(allocator, window, app);
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
    const heading = switch (app.git_status) {
        .pending => " Review · Diff · Git · refreshing ",
        .stale => " Review · Diff · Git · stale ",
        else => " Review · Diff · Git ",
    };
    _ = window.printSegment(.{
        .text = heading,
        .style = .{ .bold = true, .reverse = app.focus == .sidebar },
    }, .{ .wrap = .none });

    const review = if (app.review) |*value| value else {
        const message = if (app.git_status == .pending) "Loading snapshot…" else "No snapshot";
        _ = window.printSegment(.{ .text = message, .style = .{ .dim = true } }, .{ .row_offset = 2, .col_offset = 1, .wrap = .none });
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

fn lineHasNote(app: *const fiew.app.App, change_notes: []fiew.notes.NoteRef, line: fiew.git_model.DiffLine) bool {
    const state_notes = if (app.notes) |*value| value else return false;
    for (change_notes) |ref| {
        const note = state_notes.noteAt(ref);
        const side = note.side orelse continue;
        const number = (if (side == .new) line.new_line else line.old_line) orelse continue;
        const start = note.start_line orelse continue;
        const end = note.end_line orelse start;
        if (number >= start and number <= end) return true;
    }
    return false;
}

fn wrappedReviewRows(allocator: std.mem.Allocator, text: []const u8, width: u16) ![][]const u8 {
    var safe: std.ArrayList(u8) = .empty;
    defer safe.deinit(allocator);
    var index: usize = 0;
    while (index < text.len) {
        const length = std.unicode.utf8ByteSequenceLength(text[index]) catch 1;
        if (length == 1 and (text[index] < 0x20 or text[index] == 0x7f)) {
            if (text[index] == '\t')
                try safe.appendSlice(allocator, "    ")
            else
                try safe.appendSlice(allocator, "\u{fffd}");
            index += 1;
            continue;
        }
        if (index + length > text.len or !std.unicode.utf8ValidateSlice(text[index .. index + length])) {
            try safe.appendSlice(allocator, "\u{fffd}");
            index += 1;
            continue;
        }
        try safe.appendSlice(allocator, text[index .. index + length]);
        index += length;
    }

    const available: usize = @max(width -| 2, 1);
    var rows: std.ArrayList([]const u8) = .empty;
    var iterator = vaxis.unicode.graphemeIterator(safe.items);
    var row_start: usize = 0;
    var offset: usize = 0;
    var columns: usize = 0;
    while (iterator.next()) |grapheme| {
        const grapheme_columns: usize = vaxis.gwidth.gwidth(grapheme.bytes(safe.items), .unicode);
        if (columns != 0 and columns + grapheme_columns > available) {
            try rows.append(allocator, try std.fmt.allocPrint(allocator, "▏ {s}", .{safe.items[row_start..offset]}));
            row_start = offset;
            columns = 0;
        }
        offset += grapheme.len;
        columns += grapheme_columns;
        if (columns >= available) {
            try rows.append(allocator, try std.fmt.allocPrint(allocator, "▏ {s}", .{safe.items[row_start..offset]}));
            row_start = offset;
            columns = 0;
        }
    }
    if (row_start < safe.items.len or rows.items.len == 0)
        try rows.append(allocator, try std.fmt.allocPrint(allocator, "▏ {s}", .{safe.items[row_start..]}));
    return rows.toOwnedSlice(allocator);
}

fn reviewCommentStyle(author: fiew.review.Author, resolved: bool, bold: bool) vaxis.Cell.Style {
    const color: vaxis.Cell.Color = switch (author) {
        .reviewer => .{ .index = 3 },
        .agent => .{ .index = 6 },
    };
    return .{ .fg = color, .bold = bold, .dim = resolved };
}

fn noteEndsOnLine(note: *const fiew.review.Thread, line: fiew.git_model.DiffLine) bool {
    const side = note.side orelse return false;
    const anchor_end = note.end_line orelse return false;
    const line_number = (if (side == .new) line.new_line else line.old_line) orelse return false;
    return line_number == anchor_end;
}

fn diffVisualRowCount(
    allocator: std.mem.Allocator,
    window_width: u16,
    app: *const fiew.app.App,
    change_notes: []const fiew.notes.NoteRef,
    diff: *const fiew.git_model.FileDiff,
    first_line: usize,
) !usize {
    var count: usize = 0;
    for (diff.lines[first_line..], first_line..) |line, line_index| {
        for (diff.hunks) |hunk| if (hunk.first_line == line_index) {
            count += 1;
            break;
        };
        count += 1;
        if (app.notes) |*state_notes| for (change_notes) |ref| {
            const note = state_notes.noteAt(ref);
            if (!noteEndsOnLine(note, line)) continue;
            count += 1;
            for (note.comments) |comment| {
                count += 1;
                var body_lines = std.mem.splitScalar(u8, comment.body, '\n');
                while (body_lines.next()) |body_line| {
                    const rows = try wrappedReviewRows(allocator, body_line, window_width -| 7);
                    count += rows.len;
                }
            }
        };
    }
    return count;
}

fn visibleDiffRow(virtual_row: usize, scroll: usize, body_rows: usize) ?u16 {
    if (virtual_row < scroll or virtual_row >= scroll + body_rows) return null;
    return @intCast(virtual_row - scroll + 1);
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

    // Notes anchored to this change, for gutter markers.
    var note_buffer: [64]fiew.notes.NoteRef = undefined;
    const change_notes: []fiew.notes.NoteRef = if (app.notes) |*value|
        value.forFile(change.path, change.group, &note_buffer)
    else
        &.{};

    const body_rows = window.height -| 1;
    const total_rows = try diffVisualRowCount(allocator, window.width, app, change_notes, diff, review.diff_scroll);
    const visual_scroll = @min(review.diff_visual_scroll, total_rows -| body_rows);
    var virtual_row: usize = 0;
    var line_index = review.diff_scroll;
    render: while (line_index < diff.lines.len) : (line_index += 1) {
        for (diff.hunks) |hunk| {
            if (hunk.first_line == line_index) {
                if (visibleDiffRow(virtual_row, visual_scroll, body_rows)) |screen_row| {
                    const heading_text = diff.text[hunk.header.start..hunk.header.end];
                    const header = try std.fmt.allocPrint(allocator, "@@ -{d},{d} +{d},{d} @@ {s}", .{
                        hunk.old_start, hunk.old_count, hunk.new_start, hunk.new_count, heading_text,
                    });
                    _ = window.printSegment(.{
                        .text = try sanitizeLine(allocator, header, window.width -| 1),
                        .style = .{ .fg = .{ .index = 6 }, .dim = true },
                    }, .{ .row_offset = screen_row, .wrap = .none });
                }
                virtual_row += 1;
                break;
            }
        }
        if (virtual_row >= visual_scroll + body_rows) break :render;

        const line = diff.lines[line_index];
        const cursor = line_index == review.diff_line and app.focus == .main;
        const color: vaxis.Cell.Color = switch (line.kind) {
            .addition => .{ .index = 2 },
            .deletion => .{ .index = 1 },
            .context => .default,
        };
        if (visibleDiffRow(virtual_row, visual_scroll, body_rows)) |screen_row| {
            const old_number = if (line.old_line) |number| try std.fmt.allocPrint(allocator, "{d: >4}", .{number}) else "    ";
            const new_number = if (line.new_line) |number| try std.fmt.allocPrint(allocator, "{d: >4}", .{number}) else "    ";
            const symbol: []const u8 = switch (line.kind) {
                .addition => "+",
                .deletion => "-",
                .context => " ",
            };
            const noted = lineHasNote(app, change_notes, line);
            _ = window.print(&.{
                .{ .text = if (noted) "▸" else " ", .style = .{ .fg = .{ .index = 5 }, .bold = true } },
                .{ .text = old_number, .style = .{ .dim = true } },
                .{ .text = " " },
                .{ .text = new_number, .style = .{ .dim = true } },
                .{ .text = " " },
                .{ .text = symbol, .style = .{ .fg = color, .bold = true } },
                .{ .text = " " },
                .{
                    .text = try sanitizeLine(allocator, diff.text[line.text.start..line.text.end], window.width -| 13),
                    .style = .{ .fg = color, .reverse = cursor },
                },
            }, .{ .row_offset = screen_row, .wrap = .none });
        }
        virtual_row += 1;

        if (app.notes) |*state_notes| for (change_notes) |ref| {
            const note = state_notes.noteAt(ref);
            if (!noteEndsOnLine(note, line)) continue;
            const resolved = note.projectedStatus() == .resolved;
            if (visibleDiffRow(virtual_row, visual_scroll, body_rows)) |screen_row| _ = window.printSegment(.{
                .text = try std.fmt.allocPrint(allocator, "▏ thread · {s}", .{@tagName(note.projectedStatus())}),
                .style = .{ .fg = .{ .index = 5 }, .bold = true, .dim = resolved },
            }, .{ .row_offset = screen_row, .col_offset = 7, .wrap = .none });
            virtual_row += 1;

            for (note.comments) |comment| {
                if (visibleDiffRow(virtual_row, visual_scroll, body_rows)) |screen_row| _ = window.printSegment(.{
                    .text = try std.fmt.allocPrint(allocator, "▏ {s}", .{@tagName(comment.author)}),
                    .style = reviewCommentStyle(comment.author, resolved, true),
                }, .{ .row_offset = screen_row, .col_offset = 7, .wrap = .none });
                virtual_row += 1;

                var body_lines = std.mem.splitScalar(u8, comment.body, '\n');
                while (body_lines.next()) |body_line| {
                    const rows = try wrappedReviewRows(allocator, body_line, window.width -| 7);
                    for (rows) |body_row| {
                        if (visibleDiffRow(virtual_row, visual_scroll, body_rows)) |screen_row| _ = window.printSegment(.{
                            .text = body_row,
                            .style = reviewCommentStyle(comment.author, resolved, false),
                        }, .{ .row_offset = screen_row, .col_offset = 7, .wrap = .none });
                        virtual_row += 1;
                    }
                }
            }
        };
        if (virtual_row >= visual_scroll + body_rows) break :render;
    }
}

fn drawDocument(allocator: std.mem.Allocator, window: vaxis.Window, app: *const fiew.app.App) !void {
    if (app.sidebar_context == .git and !app.viewing_source) return drawDiff(allocator, window, app);
    if (app.sidebar_context == .review) return drawNoteDetail(allocator, window, app);
    const view = app.activeView() orelse {
        if (app.feedback) |name| {
            const message = try std.fmt.allocPrint(allocator, "Unable to open selected file: {s}", .{name});
            _ = window.printSegment(.{ .text = message, .style = .{ .dim = true } }, .{
                .row_offset = window.height / 2,
                .col_offset = 2,
                .wrap = .none,
            });
        } else {
            const quote = if (app.welcome_quote.len == 0) fiew.welcome.select(0) else app.welcome_quote;
            const positions = fiew.welcome.layout(window.width, window.height, quote);
            _ = window.printSegment(.{ .text = quote, .style = .{ .bold = true } }, .{
                .row_offset = positions.quote.row,
                .col_offset = positions.quote.column,
                .wrap = .none,
            });
            _ = window.printSegment(.{ .text = fiew.welcome.quit_hint, .style = .{ .dim = true } }, .{
                .row_offset = positions.quit_hint.row,
                .col_offset = positions.quit_hint.column,
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

fn bookmarkStatusMarker(status: fiew.bookmark.Status) []const u8 {
    return if (status == .outdated) "! " else "• ";
}

fn drawBookmarksSidebar(allocator: std.mem.Allocator, window: vaxis.Window, app: *const fiew.app.App) !void {
    _ = window.printSegment(.{
        .text = " Bookmarks ",
        .style = .{ .bold = true, .reverse = app.focus == .sidebar },
    }, .{ .wrap = .none });
    const state_bookmarks = if (app.bookmarks) |*value| value else {
        _ = window.printSegment(.{ .text = "Unavailable", .style = .{ .dim = true } }, .{ .row_offset = 2, .col_offset = 1, .wrap = .none });
        return;
    };
    if (state_bookmarks.items.items.len == 0) {
        _ = window.printSegment(.{ .text = "No bookmarks yet", .style = .{ .dim = true } }, .{ .row_offset = 2, .col_offset = 1, .wrap = .none });
        return;
    }
    const available = window.height -| 1;
    var row: usize = 0;
    while (row < available and state_bookmarks.scroll + row < state_bookmarks.items.items.len) : (row += 1) {
        const index = state_bookmarks.scroll + row;
        const item = state_bookmarks.items.items[index];
        const selected = index == state_bookmarks.selected;
        const outdated = item.status == .outdated;
        const fallback = try std.fmt.allocPrint(allocator, "{s}:{d}", .{ std.fs.path.basename(item.path), item.line });
        const text = try sanitizeLine(allocator, if (item.label.len == 0) fallback else item.label, window.width -| 4);
        _ = window.print(&.{
            .{ .text = bookmarkStatusMarker(item.status), .style = .{ .fg = if (outdated) .{ .index = 1 } else .{ .index = 6 }, .reverse = selected } },
            .{ .text = text, .style = .{ .reverse = selected, .bold = selected, .dim = item.label.len == 0 or outdated } },
        }, .{ .row_offset = @intCast(row + 1), .col_offset = 1, .wrap = .none });
    }
}

fn reviewStatusMarker(status: fiew.review.Status) []const u8 {
    return switch (status) {
        .open => "• ",
        .resolved => "✓ ",
        .outdated => "! ",
    };
}

fn reviewAuthorLabel(author: fiew.review.Author) []const u8 {
    return switch (author) {
        .reviewer => "reviewer:",
        .agent => "agent:",
    };
}

fn drawReviewSidebar(allocator: std.mem.Allocator, window: vaxis.Window, app: *const fiew.app.App) !void {
    _ = window.printSegment(.{
        .text = " Review · Threads ",
        .style = .{ .bold = true, .reverse = app.focus == .sidebar },
    }, .{ .wrap = .none });
    const state_notes = if (app.notes) |*value| value else {
        _ = window.printSegment(.{ .text = "No threads", .style = .{ .dim = true } }, .{ .row_offset = 2, .col_offset = 1, .wrap = .none });
        return;
    };
    if (state_notes.total() == 0) {
        _ = window.printSegment(.{ .text = "No threads yet", .style = .{ .dim = true } }, .{ .row_offset = 2, .col_offset = 1, .wrap = .none });
        return;
    }
    const available = window.height -| 1;
    var row: usize = 0;
    while (row < available and state_notes.scroll + row < state_notes.total()) : (row += 1) {
        const index = state_notes.scroll + row;
        const ref = state_notes.refAt(index) orelse break;
        const thread = state_notes.threadAt(ref);
        const selected = index == state_notes.selected;
        const status = thread.projectedStatus();
        const resolved = status == .resolved;
        const marker = reviewStatusMarker(status);
        const color: vaxis.Cell.Color = switch (status) {
            .open => .{ .index = 3 },
            .resolved => .{ .index = 2 },
            .outdated => .{ .index = 1 },
        };
        const name = try sanitizeLine(allocator, std.fs.path.basename(thread.path), window.width -| 3);
        _ = window.print(&.{
            .{ .text = marker, .style = .{ .fg = color, .reverse = selected } },
            .{ .text = name, .style = .{ .reverse = selected, .bold = selected, .dim = resolved } },
        }, .{ .row_offset = @intCast(row + 1), .col_offset = 1, .wrap = .none });
    }
}

fn drawNoteDetail(allocator: std.mem.Allocator, window: vaxis.Window, app: *const fiew.app.App) !void {
    const state_notes = if (app.notes) |*value| value else return;
    const ref = state_notes.selectedRef() orelse {
        _ = window.printSegment(.{ .text = " Thread", .style = .{ .bold = true, .reverse = app.focus == .main } }, .{ .wrap = .none });
        _ = window.printSegment(.{ .text = "No thread selected", .style = .{ .dim = true } }, .{ .row_offset = 2, .col_offset = 2, .wrap = .none });
        return;
    };
    const note = state_notes.threadAt(ref);
    const header = try std.fmt.allocPrint(allocator, " {s}  {s}", .{ note.projectedStatus().label(), note.path });
    _ = window.print(&.{
        .{ .text = " Thread", .style = .{ .bold = true, .reverse = app.focus == .main } },
        .{ .text = try sanitizeLine(allocator, header, window.width -| 6) },
    }, .{ .wrap = .none });

    var row: u16 = 2;
    if (note.side) |side| {
        const anchor = try std.fmt.allocPrint(allocator, "{s}/{s} · L{d}–L{d}", .{
            @tagName(note.group), side.label(), note.start_line orelse 0, note.end_line orelse 0,
        });
        _ = window.printSegment(.{ .text = try sanitizeLine(allocator, anchor, window.width -| 2), .style = .{ .dim = true } }, .{ .row_offset = row, .col_offset = 2, .wrap = .none });
        row += 1;
    }
    if (note.excerpt) |excerpt| {
        var lines = std.mem.splitScalar(u8, excerpt, '\n');
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            if (row >= window.height -| 1) break;
            const color: vaxis.Cell.Color = if (line[0] == '+') .{ .index = 2 } else if (line[0] == '-') .{ .index = 1 } else .default;
            _ = window.printSegment(.{ .text = try sanitizeLine(allocator, line, window.width -| 2), .style = .{ .fg = color } }, .{ .row_offset = row, .col_offset = 2, .wrap = .none });
            row += 1;
        }
    }
    row += 1;
    var skipped: usize = 0;
    for (note.comments) |comment| {
        if (skipped < state_notes.detail_scroll) {
            skipped += 1;
        } else if (row < window.height -| 1) {
            _ = window.printSegment(.{ .text = reviewAuthorLabel(comment.author), .style = .{ .bold = true, .fg = .{ .index = 6 } } }, .{ .row_offset = row, .col_offset = 2, .wrap = .none });
            row += 1;
        }
        var body_lines = std.mem.splitScalar(u8, comment.body, '\n');
        while (body_lines.next()) |line| {
            if (skipped < state_notes.detail_scroll) {
                skipped += 1;
                continue;
            }
            if (row >= window.height -| 1) break;
            _ = window.printSegment(.{ .text = try sanitizeLine(allocator, line, window.width -| 4), .style = .{} }, .{ .row_offset = row, .col_offset = 4, .wrap = .none });
            row += 1;
        }
    }
}

fn drawComposer(allocator: std.mem.Allocator, window: vaxis.Window, app: *const fiew.app.App) !void {
    const composer = if (app.composer) |*value| value else return;
    const height: u16 = @min(window.height, 12);
    const box = window.child(.{ .y_off = window.height - height, .height = height });
    box.clear();

    const title = if (composer.anchor) |anchor| if (anchor.side) |side|
        try std.fmt.allocPrint(allocator, " Thread — {s} · {s} · L{d}–L{d} ", .{
            anchor.path, side.label(), anchor.start_line orelse 0, anchor.end_line orelse 0,
        })
    else
        try std.fmt.allocPrint(allocator, " File thread — {s} ", .{anchor.path}) else try allocator.dupe(u8, " Append reviewer comment ");
    _ = box.printSegment(.{
        .text = try sanitizeLine(allocator, title, box.width),
        .style = .{ .bold = true, .reverse = true },
    }, .{ .wrap = .none });

    var row: u16 = 1;
    var lines = std.mem.splitScalar(u8, composer.buffer.items, '\n');
    while (lines.next()) |text| {
        if (row >= height -| 1) break;
        _ = box.printSegment(.{
            .text = try sanitizeLine(allocator, text, box.width -| 1),
            .style = .{},
        }, .{ .row_offset = row, .col_offset = 1, .wrap = .none });
        row += 1;
    }
    _ = box.printSegment(.{
        .text = "Ctrl-Enter save · Esc cancel",
        .style = .{ .dim = true },
    }, .{ .row_offset = height -| 1, .col_offset = 1, .wrap = .none });
}

fn drawBookmarkComposer(allocator: std.mem.Allocator, window: vaxis.Window, app: *const fiew.app.App) !void {
    const composer = if (app.bookmark_composer) |*value| value else return;
    const height: u16 = @min(window.height, 4);
    const box = window.child(.{ .y_off = window.height - height, .height = height });
    box.clear();
    const title = try std.fmt.allocPrint(allocator, " Bookmark — {s}:{d} ", .{ composer.target.path, composer.target.line });
    _ = box.printSegment(.{ .text = try sanitizeLine(allocator, title, box.width), .style = .{ .bold = true, .reverse = true } }, .{ .wrap = .none });
    _ = box.printSegment(.{ .text = try sanitizeLine(allocator, composer.buffer.items, box.width -| 2) }, .{ .row_offset = 1, .col_offset = 1, .wrap = .none });
    _ = box.printSegment(.{ .text = "Optional label (48 bytes) · Enter save · Esc cancel", .style = .{ .dim = true } }, .{ .row_offset = height -| 1, .col_offset = 1, .wrap = .none });
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
                .text = "p Project  r Review  b Bookmarks  ? help  q quit",
            }, .{ .row_offset = 1, .col_offset = 1, .wrap = .none });
        },
        .vcs => {
            const menu = window.child(.{ .y_off = window.height -| 2, .height = 2 });
            menu.clear();
            _ = menu.printSegment(.{ .text = " Review · Diff · Git ", .style = .{ .bold = true, .reverse = true } }, .{ .wrap = .none });
            _ = menu.printSegment(.{ .text = if (app.git_status == .pending) "r refresh (pending)  Enter close" else "r refresh  Enter close" }, .{
                .row_offset = 1,
                .col_offset = 1,
                .wrap = .none,
            });
        },
        .review => {
            const menu = window.child(.{ .y_off = window.height -| 2, .height = 2 });
            menu.clear();
            _ = menu.printSegment(.{ .text = " Review ", .style = .{ .bold = true, .reverse = true } }, .{ .wrap = .none });
            _ = menu.printSegment(.{
                .text = "d Diff  t Threads  n line  f file  a append  r resolve/reopen  x delete",
            }, .{ .row_offset = 1, .col_offset = 1, .wrap = .none });
        },
        .bookmarks => {
            const menu = window.child(.{ .y_off = window.height -| 2, .height = 2 });
            menu.clear();
            _ = menu.printSegment(.{ .text = " Bookmarks ", .style = .{ .bold = true, .reverse = true } }, .{ .wrap = .none });
            _ = menu.printSegment(.{ .text = "n new  d delete  Enter show" }, .{ .row_offset = 1, .col_offset = 1, .wrap = .none });
        },
        .note_composer => try drawComposer(allocator, window, app),
        .bookmark_composer => try drawBookmarkComposer(allocator, window, app),
        .confirm_delete => {
            const menu = window.child(.{ .y_off = window.height -| 2, .height = 2 });
            menu.clear();
            _ = menu.printSegment(.{ .text = " Delete complete thread? ", .style = .{ .bold = true, .reverse = true } }, .{ .wrap = .none });
            _ = menu.printSegment(.{ .text = "y delete  n/Esc cancel" }, .{ .row_offset = 1, .col_offset = 1, .wrap = .none });
        },
        .confirm_bookmark_delete => {
            const menu = window.child(.{ .y_off = window.height -| 2, .height = 2 });
            menu.clear();
            _ = menu.printSegment(.{ .text = " Delete bookmark? ", .style = .{ .bold = true, .reverse = true } }, .{ .wrap = .none });
            _ = menu.printSegment(.{ .text = "y delete  n/Esc cancel" }, .{ .row_offset = 1, .col_offset = 1, .wrap = .none });
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
            "{d}:{d}",
            .{ active.line + 1, active.visual_column + 1 },
        );
    } else "";
    const mode = switch (app.mode) {
        .normal => "NOR",
        .extend => "EXT",
        .command => "CMD",
    };
    const input_path = session.pendingLabel();
    const feedback = app.feedback orelse "";
    const text = if (input_path.len == 0)
        try std.fmt.allocPrint(allocator, " {s}  {s}  {s}", .{ mode, location, feedback })
    else
        try std.fmt.allocPrint(allocator, " {s}  {s}  {s}  {s}", .{ mode, input_path, location, feedback });
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

test "review render labels distinguish statuses and comment roles" {
    try std.testing.expectEqualStrings("• ", reviewStatusMarker(.open));
    try std.testing.expectEqualStrings("✓ ", reviewStatusMarker(.resolved));
    try std.testing.expectEqualStrings("! ", reviewStatusMarker(.outdated));
    try std.testing.expectEqualStrings("reviewer:", reviewAuthorLabel(.reviewer));
    try std.testing.expectEqualStrings("agent:", reviewAuthorLabel(.agent));
}

test "narrow inline review comments wrap by grapheme for both authors" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const reviewer_rows = try wrappedReviewRows(allocator, "abcdefghij", 8);
    try std.testing.expectEqual(@as(usize, 2), reviewer_rows.len);
    try std.testing.expectEqualStrings("▏ abcdef", reviewer_rows[0]);
    try std.testing.expectEqualStrings("▏ ghij", reviewer_rows[1]);

    const agent_rows = try wrappedReviewRows(allocator, "ab👩‍💻cd", 6);
    try std.testing.expectEqual(@as(usize, 2), agent_rows.len);
    try std.testing.expectEqualStrings("▏ ab👩‍💻", agent_rows[0]);
    try std.testing.expectEqualStrings("▏ cd", agent_rows[1]);

    const reviewer_style = reviewCommentStyle(.reviewer, false, false);
    const agent_style = reviewCommentStyle(.agent, false, false);
    try std.testing.expectEqual(vaxis.Cell.Color{ .index = 3 }, reviewer_style.fg);
    try std.testing.expectEqual(vaxis.Cell.Color{ .index = 6 }, agent_style.fg);
    try std.testing.expect(reviewCommentStyle(.reviewer, true, true).dim);
    try std.testing.expect(reviewCommentStyle(.agent, true, true).dim);
}

test "inline review comment layout reflows and exposes scrolled rows" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    try std.testing.expectEqual(@as(usize, 2), (try wrappedReviewRows(allocator, "abcdefghij", 8)).len);
    try std.testing.expectEqual(@as(usize, 1), (try wrappedReviewRows(allocator, "abcdefghij", 12)).len);
    try std.testing.expectEqual(@as(?u16, 1), visibleDiffRow(5, 5, 3));
    try std.testing.expectEqual(@as(?u16, 3), visibleDiffRow(7, 5, 3));
    try std.testing.expectEqual(@as(?u16, null), visibleDiffRow(8, 5, 3));
}

test "bookmark render distinguishes current and Outdated state" {
    try std.testing.expectEqualStrings("• ", bookmarkStatusMarker(.current));
    try std.testing.expectEqualStrings("! ", bookmarkStatusMarker(.outdated));
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
