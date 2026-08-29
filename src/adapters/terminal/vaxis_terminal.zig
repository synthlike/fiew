const std = @import("std");
const builtin = @import("builtin");
const vaxis = @import("vaxis");
const fiew = @import("fiew");
const ShutdownSignals = @import("shutdown_signals.zig").ShutdownSignals;

const Event = union(enum) {
    key_press: vaxis.Key,
    mouse: vaxis.Mouse,
    winsize: vaxis.Winsize,
    tick,
    /// A completed parse job, delivered from the worker thread. The main thread
    /// owns and frees the boxed completion.
    parse_done: *fiew.parse_job.Completion,
    git_done: *fiew.git_job.Completion,
    definition_done: *DefinitionCompletion,
    shutdown: u8,
};

const Completion = fiew.parse_job.Completion;
const ParseFuture = std.Io.Future(void);
const GitFuture = std.Io.Future(void);
const ZlsFuture = std.Io.Future(void);
const DefinitionFuture = std.Io.Future(void);

const DefinitionFailure = enum {
    not_installed,
    incompatible,
    unavailable,
    malformed,

    fn message(self: DefinitionFailure) []const u8 {
        return switch (self) {
            .not_installed => "ZLS not installed",
            .incompatible => "ZLS incompatible",
            .unavailable => "ZLS crashed",
            .malformed => "ZLS returned a malformed definition response",
        };
    }
};

const DefinitionCompletion = struct {
    generation: u64,
    document_generation: u64,
    selection: fiew.document.ByteRange,
    result: union(enum) {
        success: fiew.zls_process.DefinitionResponse,
        failure: DefinitionFailure,
    },

    fn deinit(self: *DefinitionCompletion) void {
        switch (self.result) {
            .success => |*response| response.deinit(),
            .failure => {},
        }
        self.* = undefined;
    }
};

const ZlsState = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    status: std.atomic.Value(fiew.lsp.Status) = .init(.untrusted),
    future: ?ZlsFuture = null,
    root_uri: ?[]u8 = null,
    document_uri: ?[]u8 = null,
    document_text: ?[]u8 = null,
    document_generation: ?u64 = null,
    starting_ticks: u8 = 0,
    last_published: fiew.lsp.Status,

    fn init(io: std.Io, allocator: std.mem.Allocator, initial: fiew.lsp.Status) ZlsState {
        return .{ .io = io, .allocator = allocator, .status = .init(initial), .last_published = initial };
    }

    fn deinit(self: *ZlsState) void {
        self.stop(.stopped);
        self.* = undefined;
    }

    fn start(self: *ZlsState, repository: fiew.filesystem.Repository, canonical_path: []const u8, app: *const fiew.app.App) void {
        self.stop(.stopped);
        self.root_uri = fiew.zls_process.fileUri(self.allocator, canonical_path) catch {
            self.status.store(.crashed, .release);
            return;
        };
        var document_version: u64 = 0;
        if (app.activeDocument()) |snapshot| {
            if (snapshot.encoding == .utf8 and std.mem.endsWith(u8, snapshot.path, ".zig")) {
                const absolute = if (std.fs.path.isAbsolute(snapshot.path))
                    self.allocator.dupe(u8, snapshot.path) catch null
                else
                    std.fs.path.join(self.allocator, &.{ canonical_path, snapshot.path }) catch null;
                if (absolute) |path| {
                    defer self.allocator.free(path);
                    self.document_uri = fiew.zls_process.fileUri(self.allocator, path) catch null;
                }
                self.document_text = self.allocator.dupe(u8, snapshot.bytes) catch null;
                document_version = snapshot.generation;
                self.document_generation = snapshot.generation;
            }
        }
        self.starting_ticks = 0;
        self.status.store(.starting, .release);
        self.future = self.io.concurrent(fiew.zls_process.serve, .{
            self.allocator,    repository.io,    repository.root_dir, self.root_uri.?,
            self.document_uri, document_version, self.document_text,  &self.status,
        }) catch {
            self.allocator.free(self.root_uri.?);
            self.root_uri = null;
            if (self.document_uri) |uri| self.allocator.free(uri);
            if (self.document_text) |text| self.allocator.free(text);
            self.document_uri = null;
            self.document_text = null;
            self.document_generation = null;
            self.status.store(.crashed, .release);
            return;
        };
    }

    fn stop(self: *ZlsState, target: fiew.lsp.Status) void {
        if (self.future) |*future| _ = future.cancel(self.io);
        self.future = null;
        if (self.root_uri) |uri| self.allocator.free(uri);
        if (self.document_uri) |uri| self.allocator.free(uri);
        if (self.document_text) |text| self.allocator.free(text);
        self.root_uri = null;
        self.document_uri = null;
        self.document_text = null;
        self.document_generation = null;
        self.starting_ticks = 0;
        self.status.store(target, .release);
    }

    fn syncDocument(self: *ZlsState, repository: fiew.filesystem.Repository, canonical_path: []const u8, app: *const fiew.app.App) void {
        if (self.status.load(.acquire) != .ready) return;
        const active_generation: ?u64 = if (app.activeDocument()) |snapshot|
            if (snapshot.encoding == .utf8 and std.mem.endsWith(u8, snapshot.path, ".zig")) snapshot.generation else null
        else
            null;
        if (active_generation == self.document_generation) return;
        // The lifecycle worker owns its pipes. Replacing the immutable active
        // snapshot therefore closes the previous document and establishes a
        // fresh, single ZLS lifecycle for the new snapshot.
        self.start(repository, canonical_path, app);
    }

    fn publish(self: *ZlsState, app: *fiew.app.App) void {
        const current = self.status.load(.acquire);
        if (current == .starting) {
            self.starting_ticks +|= 1;
            // The shared timer ticks every 100 ms. Bound version validation and
            // initialization together to two seconds.
            if (self.starting_ticks >= 20) {
                self.stop(.crashed);
                app.zls_status = .crashed;
                app.feedback = "ZLS startup timed out";
                return;
            }
        } else {
            self.starting_ticks = 0;
        }
        app.zls_status = current;
        if (current != self.last_published) {
            self.last_published = current;
            app.feedback = fiew.lsp.statusText(current);
        }
    }
};

const DefinitionRequestData = struct {
    allocator: std.mem.Allocator,
    root_uri: []u8,
    document_uri: []u8,
    text: []u8,
    document_generation: u64,
    selection: fiew.document.ByteRange,
    utf8_position: fiew.lsp.Position,
    utf16_position: fiew.lsp.Position,

    fn deinit(self: *DefinitionRequestData) void {
        self.allocator.free(self.root_uri);
        self.allocator.free(self.document_uri);
        self.allocator.free(self.text);
        self.* = undefined;
    }
};

const DefinitionState = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    loop: *vaxis.Loop(Event),
    future: ?DefinitionFuture = null,
    request: ?DefinitionRequestData = null,
    started_nanoseconds: i96 = 0,
    pending_shown: bool = false,
    running_generation: ?u64 = null,

    fn init(io: std.Io, allocator: std.mem.Allocator, loop: *vaxis.Loop(Event)) DefinitionState {
        return .{ .io = io, .allocator = allocator, .loop = loop };
    }

    fn deinit(self: *DefinitionState) void {
        self.cancel();
        self.* = undefined;
    }

    fn submit(
        self: *DefinitionState,
        repository: fiew.filesystem.Repository,
        canonical_path: []const u8,
        app: *fiew.app.App,
        generation: u64,
    ) void {
        self.cancel();
        const snapshot = app.activeDocument() orelse {
            app.failDefinition(generation, "focus an open Zig document");
            return;
        };
        const selection = app.activeView().?.selection();
        const utf8_position = fiew.lsp.positionAt(snapshot.*, selection.start, .utf8) catch {
            app.failDefinition(generation, "definition requires a valid UTF-8 position");
            return;
        };
        const utf16_position = fiew.lsp.positionAt(snapshot.*, selection.start, .utf16) catch {
            app.failDefinition(generation, "definition requires a valid UTF-16 position");
            return;
        };
        const absolute = if (std.fs.path.isAbsolute(snapshot.path))
            self.allocator.dupe(u8, snapshot.path) catch {
                app.failDefinition(generation, "ZLS unavailable");
                return;
            }
        else
            std.fs.path.join(self.allocator, &.{ canonical_path, snapshot.path }) catch {
                app.failDefinition(generation, "ZLS unavailable");
                return;
            };
        defer self.allocator.free(absolute);
        const root_uri = fiew.zls_process.fileUri(self.allocator, canonical_path) catch {
            app.failDefinition(generation, "ZLS unavailable");
            return;
        };
        const document_uri = fiew.zls_process.fileUri(self.allocator, absolute) catch {
            self.allocator.free(root_uri);
            app.failDefinition(generation, "ZLS unavailable");
            return;
        };
        const text = self.allocator.dupe(u8, snapshot.bytes) catch {
            self.allocator.free(root_uri);
            self.allocator.free(document_uri);
            app.failDefinition(generation, "ZLS unavailable");
            return;
        };
        const request: DefinitionRequestData = .{
            .allocator = self.allocator,
            .root_uri = root_uri,
            .document_uri = document_uri,
            .text = text,
            .document_generation = snapshot.generation,
            .selection = selection,
            .utf8_position = utf8_position,
            .utf16_position = utf16_position,
        };
        self.request = request;
        self.started_nanoseconds = std.Io.Timestamp.now(self.io, .real).nanoseconds;
        self.pending_shown = false;
        self.running_generation = generation;
        self.future = self.io.concurrent(definitionWorker, .{
            self.loop, self.allocator, repository.io, repository.root_dir, generation, request,
        }) catch {
            self.request.?.deinit();
            self.request = null;
            self.running_generation = null;
            app.failDefinition(generation, "ZLS unavailable");
            return;
        };
    }

    fn cancel(self: *DefinitionState) void {
        if (self.future) |*future| _ = future.cancel(self.io);
        self.future = null;
        if (self.request) |*request| request.deinit();
        self.request = null;
        self.started_nanoseconds = 0;
        self.pending_shown = false;
        self.running_generation = null;
    }

    fn sync(self: *DefinitionState, app: *fiew.app.App) void {
        const request = self.request orelse return;
        const active = app.activeView() orelse {
            const generation = app.definition_generation;
            self.cancel();
            app.failDefinition(generation, "definition discarded because the document changed");
            return;
        };
        if (active.snapshot.generation != request.document_generation) {
            const generation = app.definition_generation;
            self.cancel();
            app.failDefinition(generation, "definition discarded because the document changed");
            return;
        }
        if (!std.meta.eql(active.selection(), request.selection)) {
            const generation = app.definition_generation;
            self.cancel();
            app.failDefinition(generation, "definition discarded because the selection changed");
        }
    }

    fn onTick(self: *DefinitionState, app: *fiew.app.App) void {
        if (self.future == null) return;
        const elapsed = std.Io.Timestamp.now(self.io, .real).nanoseconds - self.started_nanoseconds;
        if (elapsed >= std.time.ns_per_ms * 100 and app.definition_pending and !self.pending_shown) {
            app.feedback = "ZLS definition pending";
            self.pending_shown = true;
        }
        if (elapsed >= std.time.ns_per_s * 2) {
            const generation = app.definition_generation;
            self.cancel();
            app.failDefinition(generation, "ZLS definition timed out");
        }
    }

    fn finish(self: *DefinitionState, box: *DefinitionCompletion) bool {
        if (self.running_generation != box.generation) return false;
        if (self.future) |*future| _ = future.await(self.io);
        self.future = null;
        if (self.request) |*request| request.deinit();
        self.request = null;
        self.started_nanoseconds = 0;
        self.pending_shown = false;
        self.running_generation = null;
        return true;
    }
};

fn definitionWorker(
    loop: *vaxis.Loop(Event),
    allocator: std.mem.Allocator,
    io: std.Io,
    repository_dir: std.Io.Dir,
    generation: u64,
    request: DefinitionRequestData,
) void {
    const result = fiew.zls_process.requestDefinition(
        allocator,
        io,
        repository_dir,
        request.root_uri,
        request.document_uri,
        request.document_generation,
        request.text,
        request.utf8_position,
        request.utf16_position,
    );
    const box = allocator.create(DefinitionCompletion) catch {
        if (result) |response| {
            var owned = response;
            owned.deinit();
        } else |_| {}
        return;
    };
    box.* = .{
        .generation = generation,
        .document_generation = request.document_generation,
        .selection = request.selection,
        .result = if (result) |response|
            .{ .success = response }
        else |err|
            .{ .failure = definitionFailure(err) },
    };
    loop.postEvent(.{ .definition_done = box }) catch {
        box.deinit();
        allocator.destroy(box);
    };
}

fn definitionFailure(err: anyerror) DefinitionFailure {
    return switch (err) {
        error.NotInstalled, error.FileNotFound => .not_installed,
        error.Incompatible => .incompatible,
        error.MalformedResponse, error.InvalidCharacter, error.UnexpectedEndOfInput => .malformed,
        else => .unavailable,
    };
}

/// Owns the single bounded Git worker slot. New requests supersede old
/// generations; obsolete completions are destroyed without publishing.
const GitLoadState = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    loop: *vaxis.Loop(Event),
    future: ?GitFuture = null,
    running_generation: ?u64 = null,
    queued_generation: ?u64 = null,

    fn init(io: std.Io, allocator: std.mem.Allocator, loop: *vaxis.Loop(Event)) GitLoadState {
        return .{ .io = io, .allocator = allocator, .loop = loop };
    }

    fn deinit(self: *GitLoadState) void {
        // Canceling the task interrupts std.process.run at its next I/O point;
        // its process defer then terminates and reaps the child before this
        // call returns.
        if (self.future) |*future| _ = future.cancel(self.io);
        self.* = undefined;
    }

    fn submit(self: *GitLoadState, repository: fiew.filesystem.Repository, generation: u64) void {
        if (self.future != null) {
            self.queued_generation = generation;
            return;
        }
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

const ParseEngine = union(enum) {
    zig: *fiew.zig_syntax.Engine,
    markdown: *fiew.markdown_syntax.Engine,
};

/// Drives off-render-loop Zig and Markdown parsing for the active document: one
/// worker at a time, results routed by snapshot generation and cancelled past
/// the one-second deadline. Unavailable grammars fall back to plain text.
const ParseState = struct {
    io: std.Io,
    allocator: std.mem.Allocator,
    loop: *vaxis.Loop(Event),
    zig_engine: ?fiew.zig_syntax.Engine,
    markdown_engine: ?fiew.markdown_syntax.Engine,
    coordinator: fiew.parse_job.Coordinator = .{},
    cancel: std.atomic.Value(bool) = .init(false),
    future: ?ParseFuture = null,
    source: ?[]u8 = null,
    parsing_generation: ?u64 = null,
    resolved_generation: ?u64 = null,
    elapsed_ticks: u8 = 0,

    fn init(io: std.Io, allocator: std.mem.Allocator, loop: *vaxis.Loop(Event)) ParseState {
        const zig_engine: ?fiew.zig_syntax.Engine = fiew.zig_syntax.Engine.init(allocator) catch null;
        const markdown_engine: ?fiew.markdown_syntax.Engine = fiew.markdown_syntax.Engine.init(allocator) catch null;
        return .{
            .io = io,
            .allocator = allocator,
            .loop = loop,
            .zig_engine = zig_engine,
            .markdown_engine = markdown_engine,
        };
    }

    fn deinit(self: *ParseState) void {
        self.cancelInFlight();
        if (self.markdown_engine) |*engine| engine.deinit();
        if (self.zig_engine) |*engine| engine.deinit();
        self.* = undefined;
    }

    fn engineFor(self: *ParseState, snapshot: *const fiew.document.Snapshot) ?ParseEngine {
        if (snapshot.encoding != .utf8 or snapshot.bytes.len == 0 or
            snapshot.bytes.len > fiew.zig_syntax.max_parse_bytes) return null;
        if (std.mem.endsWith(u8, snapshot.path, ".zig"))
            return if (self.zig_engine) |*engine| .{ .zig = engine } else null;
        if (std.mem.endsWith(u8, snapshot.path, ".md") or
            std.mem.endsWith(u8, snapshot.path, ".markdown"))
            return if (self.markdown_engine) |*engine| .{ .markdown = engine } else null;
        return null;
    }

    /// Request analysis for the active document if it is an unparsed,
    /// supported snapshot we are not already working on.
    fn drive(self: *ParseState, app: *const fiew.app.App) void {
        const view = app.activeView() orelse return;
        if (view.syntax != null) return;
        const snapshot = &view.snapshot;
        const engine = self.engineFor(snapshot) orelse return;
        if (self.parsing_generation == snapshot.generation) return;
        if (self.resolved_generation == snapshot.generation) return;
        self.submit(snapshot, engine);
    }

    fn submit(self: *ParseState, snapshot: *const fiew.document.Snapshot, engine: ParseEngine) void {
        self.cancelInFlight();
        const copy = self.allocator.dupe(u8, snapshot.bytes) catch return;
        self.cancel.store(false, .release);
        self.coordinator.begin(snapshot.generation);
        const future = self.io.concurrent(parseWorker, .{
            self.io,        self.loop, engine,
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
        // Ticks arrive every 100 ms; ten of them cross the one-second deadline.
        if (self.elapsed_ticks >= 10) self.cancel.store(true, .release);
    }
};

fn parseWorker(
    io: std.Io,
    loop: *vaxis.Loop(Event),
    engine: ParseEngine,
    allocator: std.mem.Allocator,
    source: []const u8,
    generation: u64,
    cancel: *std.atomic.Value(bool),
) void {
    _ = io;
    var context: fiew.zig_syntax.CancelContext = .{ .flag = cancel };
    const request: fiew.parse_job.Request = .{ .generation = generation, .source = source };
    const completion = switch (engine) {
        .zig => |value| fiew.parse_job.run(value, allocator, request, &context),
        .markdown => |value| fiew.parse_job.runMarkdown(value, allocator, request, &context),
    };
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

    var global_diagnostics: fiew.diagnostics.Diagnostics = .init;
    const global_path = try fiew.state_store.globalStateDirectoryPath(
        allocator,
        builtin.os.tag,
        init.environ_map.get("HOME"),
        init.environ_map.get("XDG_STATE_HOME"),
    );
    defer if (global_path) |path| allocator.free(path);
    var global_store: ?fiew.state_store.StateStore = if (global_path) |path|
        fiew.state_store.StateStore.openPath(allocator, init.io, path, &global_diagnostics) catch null
    else
        null;
    defer if (global_store) |*store| store.deinit();
    if (global_store == null)
        app.feedback = "global state unavailable; persistence disabled";

    var canonical_root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const canonical_root_length = try repository.root_dir.realPath(init.io, &canonical_root_buffer);
    var repository_identity = try fiew.repository_identity.RepositoryIdentity.fromCanonicalPath(
        allocator,
        canonical_root_buffer[0..canonical_root_length],
    );
    defer repository_identity.deinit();
    var zls_trust = try fiew.zls_trust.Trust.load(
        allocator,
        if (global_store) |*store| store else null,
    );
    defer zls_trust.deinit();
    app.zls_trust_available = zls_trust.available;
    app.zls_trusted = zls_trust.contains(repository_identity.slug());
    app.zls_status = if (app.zls_trusted) .stopped else .untrusted;

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
    // Keep handled shutdown installed until after Vaxis and the TTY have
    // restored terminal modes; a repeated signal during cleanup stays graceful.
    var shutdown_signals = try ShutdownSignals.install();
    defer shutdown_signals.deinit();
    defer tty.deinit();

    var vx = try vaxis.init(init.io, allocator, init.environ_map, .{
        .kitty_keyboard_flags = .{ .report_events = true },
    });
    defer vx.deinit(allocator, tty.writer());

    var loop: vaxis.Loop(Event) = .init(init.io, &tty, &vx);
    try loop.start();
    defer loop.stop();
    try shutdown_signals.arm(&loop, postShutdown);
    defer shutdown_signals.disarm();

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
    var zls_state = ZlsState.init(init.io, allocator, app.zls_status);
    defer zls_state.deinit();
    var definition_state = DefinitionState.init(init.io, allocator, &loop);
    defer definition_state.deinit();

    try vx.enterAltScreen(tty.writer());
    try tty.writer().flush();
    try vx.queryTerminal(tty.writer(), .fromSeconds(1));
    try vx.setMouseMode(tty.writer(), true);
    try tty.writer().flush();

    var frame_arena = std.heap.ArenaAllocator.init(allocator);
    defer frame_arena.deinit();
    while (true) {
        const event = try loop.nextEvent();
        // The signal pipe watcher wakes this loop without invoking terminal or
        // allocator code from the async signal handler.
        if (ShutdownSignals.requestedExitCode()) |code| return code;
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
                        if (global_store) |*store| store else null,
                        &zls_trust,
                        repository_identity.slug(),
                        repository_identity.canonical_path,
                        &zls_state,
                        &definition_state,
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
                command_session.finder.ensureVisible(fiew.workspace.finderResultRows(dimensions.content_height));
                if (app.definition_results) |*results|
                    results.ensureVisible(fiew.workspace.finderResultRows(dimensions.content_height));
                app.ensureCurrentDocumentVisible(viewport_height, dimensions.main_width -| 6);
            },
            .tick => {
                command_session.tick(&app);
                parse_state.onTick();
                zls_state.publish(&app);
                definition_state.onTick(&app);
            },
            .parse_done => |box| parse_state.onCompletion(&app, box),
            .git_done => |box| git_state.onCompletion(&app, repository, box),
            .definition_done => |box| {
                const owned_by_state = definition_state.finish(box);
                defer {
                    box.deinit();
                    allocator.destroy(box);
                }
                if (!owned_by_state or box.generation != app.definition_generation) continue;
                const active = app.activeView() orelse {
                    app.failDefinition(box.generation, "definition discarded because the document changed");
                    continue;
                };
                if (active.snapshot.generation != box.document_generation) {
                    app.failDefinition(box.generation, "definition discarded because the document changed");
                    continue;
                }
                if (!std.meta.eql(active.selection(), box.selection)) {
                    app.failDefinition(box.generation, "definition discarded because the selection changed");
                    continue;
                }
                switch (box.result) {
                    .failure => |failure| {
                        const status: fiew.lsp.Status = switch (failure) {
                            .not_installed => .not_installed,
                            .incompatible => .incompatible,
                            .unavailable => .crashed,
                            .malformed => .stopped,
                        };
                        zls_state.stop(status);
                        zls_state.last_published = status;
                        app.zls_status = status;
                        app.failDefinition(box.generation, failure.message());
                    },
                    .success => |*response| {
                        var results = validateDefinitionTargets(
                            allocator,
                            repository,
                            repository_identity.canonical_path,
                            segmenter,
                            &generation,
                            response,
                        ) catch |err| {
                            app.failDefinition(box.generation, @errorName(err));
                            continue;
                        };
                        if (results.items.len == 0) {
                            results.deinit();
                            app.failDefinition(box.generation, "no valid definition returned");
                            continue;
                        }
                        _ = app.installDefinitions(box.generation, results);
                        app.prepareDefinitionPreview();
                        if (app.definition_results.?.items.len == 1) {
                            const target = app.definition_results.?.items[0];
                            openDefinitionTarget(&app, repository, segmenter, &generation, target, true) catch |err| {
                                app.dismissDefinitions(false);
                                app.failDefinition(box.generation, @errorName(err));
                            };
                        } else {
                            const effect = command_session.openDefinitions(&app);
                            _ = try applyEffect(
                                &command_session,
                                &app,
                                repository,
                                segmenter,
                                &generation,
                                commandDimensions(vx.window(), &app),
                                effect,
                                review_name,
                                &git_state,
                                if (global_store) |*store| store else null,
                                &zls_trust,
                                repository_identity.slug(),
                                repository_identity.canonical_path,
                                &zls_state,
                                &definition_state,
                            );
                        }
                    },
                }
            },
            .shutdown => |code| return code,
        }

        definition_state.sync(&app);
        parse_state.drive(&app);
        zls_state.syncDocument(repository, repository_identity.canonical_path, &app);
        _ = frame_arena.reset(.retain_capacity);
        try draw(frame_arena.allocator(), vx.window(), &app, &command_session, repository.root_path);
        try vx.render(tty.writer());
        try tty.writer().flush();
    }
}

fn postShutdown(context: *anyopaque, exit_code: u8) void {
    const loop: *vaxis.Loop(Event) = @ptrCast(@alignCast(context));
    loop.postEvent(.{ .shutdown = exit_code }) catch {};
}

fn timerRun(
    io: std.Io,
    loop: *vaxis.Loop(Event),
    stop: *std.atomic.Value(bool),
) void {
    while (!stop.load(.acquire)) {
        io.sleep(.fromMilliseconds(100), .real) catch {
            // A handled shutdown signal may interrupt the sleep. Wake the main
            // loop once so it can observe the atomic request and unwind.
            if (ShutdownSignals.requestedExitCode() != null)
                loop.postEvent(.tick) catch {};
            return;
        };
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
        .finder_rows = fiew.workspace.finderResultRows(dimensions.content_height),
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
        // Shortcut identity follows the physical codepoint. Kitty `text` may
        // contain a control byte (for example ETX for Ctrl-C), while ordinary
        // text input uses the produced shifted glyph.
        .character = if (code == .character)
            if (key.mods.ctrl or key.mods.alt) key.codepoint else producedCharacter(key)
        else
            0,
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

fn validateDefinitionTargets(
    allocator: std.mem.Allocator,
    repository: fiew.filesystem.Repository,
    canonical_root: []const u8,
    segmenter: fiew.text_segmentation.Segmenter,
    snapshot_generation: *u64,
    response: *const fiew.zls_process.DefinitionResponse,
) !fiew.definitions.Results {
    var targets: std.ArrayList(fiew.definitions.Target) = .empty;
    errdefer {
        for (targets.items) |*target| target.deinit(allocator);
        targets.deinit(allocator);
    }
    for (response.locations) |location| {
        const decoded = fiew.zls_process.pathFromFileUri(allocator, location.uri) catch continue;
        defer allocator.free(decoded);
        const canonical_z = std.Io.Dir.realPathFileAbsoluteAlloc(repository.io, decoded, allocator) catch continue;
        defer allocator.free(canonical_z);
        const canonical: []const u8 = canonical_z;
        const stat = std.Io.Dir.cwd().statFile(repository.io, canonical, .{}) catch continue;
        if (stat.kind != .file) continue;
        const root_is_filesystem_root = canonical_root.len == 1 and canonical_root[0] == std.fs.path.sep;
        const internal = if (root_is_filesystem_root)
            canonical.len > 1 and canonical[0] == std.fs.path.sep
        else
            canonical.len > canonical_root.len and
                std.mem.startsWith(u8, canonical, canonical_root) and
                canonical[canonical_root.len] == std.fs.path.sep;
        const relative_start = canonical_root.len + @intFromBool(!root_is_filesystem_root);
        const display_path = if (internal) canonical[relative_start..] else canonical;

        snapshot_generation.* +%= 1;
        var snapshot = if (internal)
            repository.loadDocument(display_path, snapshot_generation.*, segmenter) catch continue
        else
            repository.loadExternalDocument(canonical, snapshot_generation.*, segmenter) catch continue;
        defer snapshot.deinit();
        const source_start = fiew.lsp.byteOffsetAt(snapshot, location.start, response.encoding) catch continue;
        const source_end = fiew.lsp.byteOffsetAt(snapshot, location.end, response.encoding) catch continue;
        if (source_end < source_start) continue;
        var duplicate = false;
        for (targets.items) |target| if (target.source_start == source_start and std.mem.eql(u8, target.path, display_path)) {
            duplicate = true;
            break;
        };
        if (duplicate) continue;

        const line_index: usize = @intCast(location.start.line);
        if (line_index >= snapshot.lineCount()) continue;
        var visual_column: usize = 0;
        const grapheme_range = snapshot.graphemeRangeForLine(line_index);
        for (snapshot.graphemes[grapheme_range.start..grapheme_range.end]) |grapheme| {
            if (grapheme.source.start >= source_start) {
                visual_column = grapheme.visual_column;
                break;
            }
        }
        const preview_range = snapshot.lineDisplayRange(line_index);
        const preview = try allocator.dupe(u8, snapshot.display_bytes[preview_range.start..preview_range.end]);
        errdefer allocator.free(preview);
        const path = try allocator.dupe(u8, display_path);
        errdefer allocator.free(path);
        try targets.append(allocator, .{
            .path = path,
            .line = line_index + 1,
            .column = visual_column,
            .source_start = source_start,
            .preview = preview,
            .external = !internal,
        });
    }
    return fiew.definitions.Results.init(allocator, try targets.toOwnedSlice(allocator));
}

fn openDefinitionTarget(
    app: *fiew.app.App,
    repository: fiew.filesystem.Repository,
    segmenter: fiew.text_segmentation.Segmenter,
    snapshot_generation: *u64,
    target: fiew.definitions.Target,
    pin: bool,
) !void {
    snapshot_generation.* +%= 1;
    const snapshot = if (target.external)
        try repository.loadExternalDocument(target.path, snapshot_generation.*, segmenter)
    else
        try repository.loadDocument(target.path, snapshot_generation.*, segmenter);
    app.showPreview(snapshot);
    app.preview.?.external = target.external;
    app.positionPreviewAtLine(target.line, target.column);
    if (pin) {
        _ = try app.pinDefinitionPreview();
        app.dismissDefinitions(false);
    }
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
    global_store: ?*fiew.state_store.StateStore,
    zls_trust: *fiew.zls_trust.Trust,
    repository_slug: []const u8,
    canonical_path: []const u8,
    zls_state: *ZlsState,
    definition_state: *DefinitionState,
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
        .preview_finder => _ = try previewFinder(session, app, repository, segmenter, generation),
        .activate_finder => {
            if (try previewFinder(session, app, repository, segmenter, generation))
                _ = try app.pinPreview();
        },
        .load_git_finder => {
            var paths = fiew.git_files.load(repository.allocator, repository.io, repository.root_dir) catch |err| {
                app.feedback = @errorName(err);
                return false;
            };
            defer paths.deinit();
            _ = try session.openGitFinder(app, paths.paths);
            _ = try previewFinder(session, app, repository, segmenter, generation);
        },
        .reload_document => |path| {
            generation.* +%= 1;
            const snapshot = repository.loadDocument(path, generation.*, segmenter) catch |err| {
                app.feedback = @errorName(err);
                return false;
            };
            _ = app.replaceActiveSnapshot(snapshot);
            app.ensureCurrentDocumentVisible(dimensions.document_rows, dimensions.document_columns);
        },
        .open_history => |location| {
            generation.* +%= 1;
            const snapshot = (if (location.external)
                repository.loadExternalDocument(location.path, generation.*, segmenter)
            else
                repository.loadDocument(location.path, generation.*, segmenter)) catch |err| {
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
        .zls_status => app.feedback = fiew.lsp.statusText(app.zls_status),
        .zls_trust => {
            const store = global_store orelse {
                app.feedback = "global state unavailable; ZLS trust cannot be persisted";
                return false;
            };
            zls_trust.grant(store, repository_slug) catch |err| {
                app.feedback = @errorName(err);
                return false;
            };
            zls_state.stop(.stopped);
            zls_state.last_published = .stopped;
            app.zls_trusted = true;
            app.zls_status = .stopped;
            app.feedback = "repository trusted for ZLS; ZLS may evaluate repository Zig build logic";
        },
        .zls_revoke => {
            const store = global_store orelse {
                app.feedback = "global state unavailable; ZLS trust cannot be changed";
                return false;
            };
            zls_trust.revoke(store, repository_slug) catch |err| {
                app.feedback = @errorName(err);
                return false;
            };
            definition_state.cancel();
            if (app.definition_pending or app.definition_results != null) app.cancelDefinition();
            zls_state.stop(.untrusted);
            zls_state.last_published = .untrusted;
            app.zls_trusted = false;
            app.zls_status = .untrusted;
            app.feedback = "ZLS trust revoked";
        },
        .zls_restart => {
            definition_state.cancel();
            zls_state.start(repository, canonical_path, app);
            app.zls_status = .starting;
            app.feedback = "ZLS starting";
        },
        .request_definition => |definition_generation| {
            zls_state.stop(.stopped);
            definition_state.submit(repository, canonical_path, app, definition_generation);
        },
        .cancel_definition => definition_state.cancel(),
        .preview_definition => {
            const target = app.definition_results.?.selectedTarget() orelse return false;
            openDefinitionTarget(app, repository, segmenter, generation, target.*, false) catch |err| {
                app.feedback = @errorName(err);
                return false;
            };
        },
        .activate_definition => {
            const target = app.definition_results.?.selectedTarget() orelse return false;
            openDefinitionTarget(app, repository, segmenter, generation, target.*, true) catch |err| {
                _ = session.openDefinitions(app);
                app.feedback = @errorName(err);
                return false;
            };
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

fn previewFinder(
    session: *const fiew.commands.Session,
    app: *fiew.app.App,
    repository: fiew.filesystem.Repository,
    segmenter: fiew.text_segmentation.Segmenter,
    generation: *u64,
) !bool {
    const node = session.selectedFinderNode(app) orelse {
        app.clearPreview();
        return false;
    };
    generation.* +%= 1;
    const snapshot = repository.loadDocument(node.path, generation.*, segmenter) catch |err| {
        app.feedback = @errorName(err);
        return false;
    };
    app.showPreview(snapshot);
    return true;
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

fn wrappedTextRows(allocator: std.mem.Allocator, text: []const u8, width: u16, prefix: []const u8) ![][]const u8 {
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

    const prefix_columns: u16 = @intCast(vaxis.gwidth.gwidth(prefix, .unicode));
    const available: usize = @max(width -| prefix_columns -| 1, 1);
    var rows: std.ArrayList([]const u8) = .empty;
    var row_start: usize = 0;
    while (row_start < safe.items.len) {
        const remaining = safe.items[row_start..];
        var iterator = vaxis.unicode.graphemeIterator(remaining);
        var offset: usize = 0;
        var columns: usize = 0;
        var break_start: ?usize = null;
        var break_end: usize = 0;
        var in_spaces = false;
        var emitted = false;

        while (iterator.next()) |grapheme| {
            const bytes = grapheme.bytes(remaining);
            const grapheme_columns: usize = vaxis.gwidth.gwidth(bytes, .unicode);
            if (columns != 0 and columns + grapheme_columns > available) {
                var row_end = offset;
                var next_start = row_start + offset;
                if (break_start) |space_start| if (space_start != 0) {
                    row_end = space_start;
                    next_start = row_start + break_end;
                    while (next_start < safe.items.len and safe.items[next_start] == ' ') next_start += 1;
                };
                try rows.append(allocator, try std.fmt.allocPrint(allocator, "{s}{s}", .{ prefix, remaining[0..row_end] }));
                row_start = next_start;
                emitted = true;
                break;
            }

            const grapheme_start = offset;
            offset += grapheme.len;
            columns += grapheme_columns;
            const is_space = bytes.len == 1 and bytes[0] == ' ';
            if (is_space) {
                if (!in_spaces) break_start = grapheme_start;
                break_end = offset;
            }
            in_spaces = is_space;
        }

        if (!emitted) {
            try rows.append(allocator, try std.fmt.allocPrint(allocator, "{s}{s}", .{ prefix, remaining }));
            row_start = safe.items.len;
        }
    }
    if (rows.items.len == 0) try rows.append(allocator, try allocator.dupe(u8, prefix));
    return rows.toOwnedSlice(allocator);
}

fn wrappedReviewRows(allocator: std.mem.Allocator, text: []const u8, width: u16) ![][]const u8 {
    return wrappedTextRows(allocator, text, width, "▏ ");
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

fn diffLineStyle(color: vaxis.Cell.Color, selected: bool, cursor: bool) vaxis.Cell.Style {
    return .{
        .fg = color,
        .reverse = selected or cursor,
        .bold = cursor,
        .ul_style = if (cursor) .single else .off,
    };
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
        const selected = review.diffLineSelected(line_index);
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
                    .style = diffLineStyle(color, selected, cursor),
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
        .{ .text = if (view.external) "  External" else "", .style = .{ .bold = view.external } },
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
    const resolved = note.projectedStatus() == .resolved;
    var skipped: usize = 0;
    for (note.comments) |comment| {
        if (skipped < state_notes.detail_scroll) {
            skipped += 1;
        } else if (row < window.height -| 1) {
            _ = window.printSegment(.{
                .text = reviewAuthorLabel(comment.author),
                .style = reviewCommentStyle(comment.author, resolved, true),
            }, .{ .row_offset = row, .col_offset = 2, .wrap = .none });
            row += 1;
        }
        var body_lines = std.mem.splitScalar(u8, comment.body, '\n');
        while (body_lines.next()) |line| {
            const body_rows = try wrappedTextRows(allocator, line, window.width -| 4, "");
            for (body_rows) |body_row| {
                if (skipped < state_notes.detail_scroll) {
                    skipped += 1;
                    continue;
                }
                if (row >= window.height -| 1) continue;
                _ = window.printSegment(.{
                    .text = body_row,
                    .style = reviewCommentStyle(comment.author, resolved, false),
                }, .{ .row_offset = row, .col_offset = 4, .wrap = .none });
                row += 1;
            }
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
    const pending_count = session.pendingCommandCount();
    if (pending_count != 0) {
        const height: u16 = @min(window.height, @as(u16, @intCast(pending_count + 1)));
        const menu = window.child(.{ .y_off = window.height - height, .height = height });
        menu.clear();
        const title = try std.fmt.allocPrint(allocator, " Key · {s} ", .{session.pendingLabel()});
        _ = menu.printSegment(.{ .text = title, .style = .{ .bold = true, .reverse = true } }, .{ .wrap = .none });
        for (0..height -| 1) |index| {
            const id = session.pendingCommand(index).?;
            const reason = fiew.commands.unavailableReason(app, id);
            _ = menu.printSegment(.{
                .text = try continuationHintRow(allocator, app, session, id),
                .style = .{ .dim = reason != null },
            }, .{ .row_offset = @intCast(index + 1), .col_offset = 1, .wrap = .none });
        }
        return;
    }

    switch (session.surface) {
        .none => {},
        .leader => {
            const menu = window.child(.{ .y_off = window.height -| 2, .height = 2 });
            menu.clear();
            _ = menu.printSegment(.{ .text = " Leader ", .style = .{ .bold = true, .reverse = true } }, .{ .wrap = .none });
            _ = menu.printSegment(.{
                .text = "p Project  f Files  r Review  b Bookmarks  ? help  q quit",
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
        .files => {
            const menu = window.child(.{ .y_off = window.height -| 2, .height = 2 });
            menu.clear();
            _ = menu.printSegment(.{ .text = " Files ", .style = .{ .bold = true, .reverse = true } }, .{ .wrap = .none });
            const git_reason = fiew.commands.unavailableReason(app, .file_find_git);
            _ = menu.printSegment(.{
                .text = if (git_reason == null) "a all files  g git files  r reload" else "a all files  g git files (not a Git repository)  r reload",
            }, .{ .row_offset = 1, .col_offset = 1, .wrap = .none });
        },
        .note_composer => try drawComposer(allocator, window, app),
        .bookmark_composer => try drawBookmarkComposer(allocator, window, app),
        .finder => {
            const height: u16 = @min(window.height, fiew.workspace.finder_max_height);
            const box = window.child(.{ .y_off = window.height - height, .height = height });
            box.clear();
            const label = switch (session.finder.scope) {
                .all => "Find all files",
                .git_visible => "Find Git files",
            };
            const query = try std.fmt.allocPrint(allocator, " {s}  {s}", .{ label, session.finder.query.items });
            _ = box.printSegment(.{ .text = try sanitizeLine(allocator, query, box.width), .style = .{ .bold = true, .reverse = true } }, .{ .wrap = .none });
            if (session.finder.matches.items.len == 0) {
                _ = box.printSegment(.{ .text = "No matching repository files", .style = .{ .dim = true } }, .{ .row_offset = 2, .col_offset = 2, .wrap = .none });
            } else {
                const available: usize = height -| 2;
                var row: usize = 0;
                while (row < available and session.finder.scroll + row < session.finder.matches.items.len) : (row += 1) {
                    const index = session.finder.scroll + row;
                    const match = session.finder.matches.items[index];
                    const path = app.browser.tree.nodes[match.node_index].path;
                    _ = box.printSegment(.{
                        .text = try sanitizeLine(allocator, path, box.width -| 2),
                        .style = .{ .reverse = index == session.finder.selected, .bold = index == session.finder.selected },
                    }, .{ .row_offset = @intCast(row + 1), .col_offset = 1, .wrap = .none });
                }
            }
            const hint = if (session.finder.truncated)
                "Results truncated · Tab/Shift-Tab or ↑/↓ select · Enter open · Esc cancel"
            else
                "Tab/Shift-Tab or ↑/↓ select · Enter open · Esc cancel";
            _ = box.printSegment(.{ .text = hint, .style = .{ .dim = true } }, .{ .row_offset = height -| 1, .col_offset = 1, .wrap = .none });
        },
        .definitions => {
            const height: u16 = @min(window.height, fiew.workspace.finder_max_height);
            const box = window.child(.{ .y_off = window.height - height, .height = height });
            box.clear();
            _ = box.printSegment(.{ .text = " Definitions ", .style = .{ .bold = true, .reverse = true } }, .{ .wrap = .none });
            if (app.definition_results) |results| {
                const available: usize = height -| 2;
                var row: usize = 0;
                while (row < available and results.scroll + row < results.items.len) : (row += 1) {
                    const index = results.scroll + row;
                    const target = results.items[index];
                    const label = try definitionResultLabel(allocator, target);
                    _ = box.printSegment(.{
                        .text = try sanitizeLine(allocator, label, box.width -| 2),
                        .style = .{ .reverse = index == results.selected, .bold = index == results.selected },
                    }, .{ .row_offset = @intCast(row + 1), .col_offset = 1, .wrap = .none });
                }
            }
            _ = box.printSegment(.{ .text = "j/k or ↑/↓ preview · Enter open · Esc cancel", .style = .{ .dim = true } }, .{
                .row_offset = height -| 1,
                .col_offset = 1,
                .wrap = .none,
            });
        },
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

fn definitionResultLabel(allocator: std.mem.Allocator, target: fiew.definitions.Target) ![]u8 {
    return std.fmt.allocPrint(allocator, "{s}:{d}  {s}{s}", .{
        target.path,
        target.line,
        target.preview,
        if (target.external) "  External" else "",
    });
}

fn continuationHintRow(
    allocator: std.mem.Allocator,
    app: *const fiew.app.App,
    session: *const fiew.commands.Session,
    id: fiew.commands.Id,
) ![]u8 {
    const command = fiew.commands.definition(id);
    const label = command.hint orelse command.title;
    if (fiew.commands.unavailableReason(app, id)) |reason|
        return std.fmt.allocPrint(allocator, "{s:<3} {s} — {s}", .{ session.continuationKey(id), label, reason });
    return std.fmt.allocPrint(allocator, "{s:<3} {s}", .{ session.continuationKey(id), label });
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

test "Kitty and conventional VT keys translate to the same command input" {
    const conventional = translateKey(.{ .codepoint = '?', .mods = .{ .shift = true } });
    const kitty = translateKey(.{
        .codepoint = '/',
        .text = "?",
        .shifted_codepoint = '?',
        .mods = .{ .shift = true },
    });
    try std.testing.expectEqual(conventional, kitty);
    try std.testing.expectEqual(fiew.commands.Code.character, kitty.code);
    try std.testing.expectEqual(@as(u21, '?'), kitty.character);

    const conventional_ctrl_c = translateKey(.{ .codepoint = 'c', .mods = .{ .ctrl = true } });
    const kitty_ctrl_c = translateKey(.{
        .codepoint = 'c',
        .text = "\x03",
        .mods = .{ .ctrl = true },
    });
    try std.testing.expectEqual(conventional_ctrl_c, kitty_ctrl_c);
}

test "definition target validation distinguishes repository and external files" {
    var repository_tmp = std.testing.tmpDir(.{ .iterate = true });
    defer repository_tmp.cleanup();
    try repository_tmp.dir.writeFile(std.testing.io, .{ .sub_path = "main.zig", .data = "const a = 1;\nconst b = a;\n" });
    var external_tmp = std.testing.tmpDir(.{ .iterate = true });
    defer external_tmp.cleanup();
    try external_tmp.dir.writeFile(std.testing.io, .{ .sub_path = "stdlib.zig", .data = "pub const value = 1;\n" });
    const repository_path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}", .{repository_tmp.sub_path});
    defer std.testing.allocator.free(repository_path);
    var repository = try fiew.filesystem.Repository.open(std.testing.allocator, std.testing.io, repository_path);
    defer repository.deinit();
    var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root_len = try repository.root_dir.realPath(std.testing.io, &root_buffer);
    const canonical_root = root_buffer[0..root_len];
    const internal_path = try std.fs.path.join(std.testing.allocator, &.{ canonical_root, "main.zig" });
    defer std.testing.allocator.free(internal_path);
    var external_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const external_len = try external_tmp.dir.realPath(std.testing.io, &external_buffer);
    const external_path = try std.fs.path.join(std.testing.allocator, &.{ external_buffer[0..external_len], "stdlib.zig" });
    defer std.testing.allocator.free(external_path);
    const locations = try std.testing.allocator.alloc(fiew.zls_process.WireLocation, 3);
    locations[0] = .{ .uri = try fiew.zls_process.fileUri(std.testing.allocator, internal_path), .start = .{ .line = 1, .character = 10 }, .end = .{ .line = 1, .character = 11 } };
    locations[1] = .{ .uri = try fiew.zls_process.fileUri(std.testing.allocator, external_path), .start = .{ .line = 0, .character = 10 }, .end = .{ .line = 0, .character = 15 } };
    locations[2] = .{ .uri = try fiew.zls_process.fileUri(std.testing.allocator, internal_path), .start = .{ .line = 99, .character = 0 }, .end = .{ .line = 99, .character = 1 } };
    var response: fiew.zls_process.DefinitionResponse = .{ .allocator = std.testing.allocator, .encoding = .utf8, .locations = locations };
    defer response.deinit();
    const segmenter: fiew.text_segmentation.Segmenter = .{ .next_fn = nextGrapheme, .width_fn = graphemeWidth };
    var generation: u64 = 0;
    var targets = try validateDefinitionTargets(std.testing.allocator, repository, canonical_root, segmenter, &generation, &response);
    defer targets.deinit();
    try std.testing.expectEqual(@as(usize, 2), targets.items.len);
    try std.testing.expectEqualStrings("main.zig", targets.items[0].path);
    try std.testing.expect(!targets.items[0].external);
    try std.testing.expectEqualStrings("const b = a;", targets.items[0].preview);
    try std.testing.expect(targets.items[1].external);
    try std.testing.expectEqualStrings(external_path, targets.items[1].path);
}

test "definition result render labels include line preview and External state" {
    const internal: fiew.definitions.Target = .{ .path = @constCast("src/main.zig"), .line = 12, .column = 0, .source_start = 0, .preview = @constCast("pub fn main()"), .external = false };
    const external: fiew.definitions.Target = .{ .path = @constCast("/zig/std/process.zig"), .line = 4, .column = 0, .source_start = 0, .preview = @constCast("pub const Init"), .external = true };
    const internal_label = try definitionResultLabel(std.testing.allocator, internal);
    defer std.testing.allocator.free(internal_label);
    const external_label = try definitionResultLabel(std.testing.allocator, external);
    defer std.testing.allocator.free(external_label);
    try std.testing.expectEqualStrings("src/main.zig:12  pub fn main()", internal_label);
    try std.testing.expectEqualStrings("/zig/std/process.zig:4  pub const Init  External", external_label);
}

test "pending continuation rows render every prefix and disabled reason" {
    var nodes: [0]fiew.project.Node = .{};
    const tree: fiew.project.Tree = .{ .allocator = std.testing.allocator, .nodes = &nodes, .file_count = 0 };
    var app = try fiew.app.App.init(std.testing.allocator, &tree);
    defer app.deinit();
    app.focus = .main;
    var session = fiew.commands.Session.init(std.testing.allocator);
    defer session.deinit();
    const dimensions: fiew.commands.Dimensions = .{ .sidebar_rows = 20, .document_rows = 20, .document_columns = 80 };
    const cases = [_]struct { prefix: u21, rows: []const []const u8 }{
        .{ .prefix = 'g', .rows = &.{
            "g   start — no document is open",
            "e   end — no document is open",
            "d   definition — focus an open Zig document",
        } },
        .{ .prefix = 'z', .rows = &.{
            "c   close — Tree-sitter folds are not available",
            "o   open — Tree-sitter folds are not available",
            "a   toggle — Tree-sitter folds are not available",
            "M   close all — Tree-sitter folds are not available",
            "R   open all — Tree-sitter folds are not available",
        } },
        .{ .prefix = ']', .rows = &.{
            "f   file — open the Git view first",
            "h   hunk — open the Git view first",
            "c   change — open the Git view first",
            "n   thread — no notes yet",
            "b   bookmark — no bookmarks yet",
        } },
        .{ .prefix = '[', .rows = &.{
            "f   file — open the Git view first",
            "h   hunk — open the Git view first",
            "c   change — open the Git view first",
            "n   thread — no notes yet",
            "b   bookmark — no bookmarks yet",
        } },
    };

    for (cases) |case| {
        _ = try session.handle(&app, .{ .code = .character, .character = case.prefix }, dimensions);
        try std.testing.expectEqual(case.rows.len, session.pendingCommandCount());
        for (case.rows, 0..) |expected, index| {
            const row = try continuationHintRow(std.testing.allocator, &app, &session, session.pendingCommand(index).?);
            defer std.testing.allocator.free(row);
            try std.testing.expectEqualStrings(expected, row);
        }
        _ = try session.handle(&app, .{ .code = .escape }, dimensions);
    }
}

test "terminal presentation stays usable without optional capabilities" {
    // Fiew emits palette indexes rather than requiring RGB, and every mouse
    // action is an enhancement over command-registry keyboard actions.
    try std.testing.expectEqual(vaxis.Cell.Color{ .index = 5 }, highlightColor(.keyword));
    try std.testing.expectEqual(vaxis.Cell.Color.default, highlightColor(.variable));
    try std.testing.expect(fiew.commands.definition(.quit).binding.len != 0);
    try std.testing.expect(fiew.commands.definition(.focus_next).binding.len != 0);
    try std.testing.expect(fiew.commands.definition(.activate).binding.len != 0);
}

test "Markdown and injected Zig highlights reach the cell-style seam" {
    const source = "# Heading\n\n```zig\nconst answer = 42;\n```\n";
    var engine = try fiew.markdown_syntax.Engine.init(std.testing.allocator);
    defer engine.deinit();
    var data = engine.analyze(std.testing.allocator, source, null) orelse return error.ParseFailed;
    defer data.deinit();

    const heading = std.mem.indexOf(u8, source, "Heading").?;
    try std.testing.expectEqual(fiew.syntax.HighlightKind.label, highlightKindAt(data.highlights, heading).?);
    const number = std.mem.indexOf(u8, source, "42").?;
    try std.testing.expectEqual(fiew.syntax.HighlightKind.number, highlightKindAt(data.highlights, number).?);
    try std.testing.expectEqual(vaxis.Cell.Color{ .index = 6 }, highlightColor(highlightKindAt(data.highlights, number).?));
}

test "Review Diff selection and active cursor styles remain distinct" {
    const color: vaxis.Cell.Color = .{ .index = 2 };
    const selected = diffLineStyle(color, true, false);
    try std.testing.expectEqual(color, selected.fg);
    try std.testing.expect(selected.reverse);
    try std.testing.expect(!selected.bold);
    try std.testing.expectEqual(vaxis.Cell.Style.Underline.off, selected.ul_style);

    const active = diffLineStyle(color, true, true);
    try std.testing.expectEqual(color, active.fg);
    try std.testing.expect(active.reverse);
    try std.testing.expect(active.bold);
    try std.testing.expectEqual(vaxis.Cell.Style.Underline.single, active.ul_style);

    const idle = diffLineStyle(color, false, false);
    try std.testing.expect(!idle.reverse);
    try std.testing.expect(!idle.bold);
}

test "review render labels distinguish statuses and comment roles" {
    try std.testing.expectEqualStrings("• ", reviewStatusMarker(.open));
    try std.testing.expectEqualStrings("✓ ", reviewStatusMarker(.resolved));
    try std.testing.expectEqualStrings("! ", reviewStatusMarker(.outdated));
    try std.testing.expectEqualStrings("reviewer:", reviewAuthorLabel(.reviewer));
    try std.testing.expectEqualStrings("agent:", reviewAuthorLabel(.agent));
}

test "Review Threads renders long comment continuation rows" {
    const allocator = std.testing.allocator;
    var nodes: [0]fiew.project.Node = .{};
    const tree: fiew.project.Tree = .{ .allocator = allocator, .nodes = &nodes, .file_count = 0 };
    var app = try fiew.app.App.init(allocator, &tree);
    defer app.deinit();
    app.sidebar_context = .review;
    app.notes = .{ .allocator = allocator };

    const comments = try allocator.alloc(fiew.review.Comment, 1);
    comments[0] = .{ .author = .reviewer, .body = try allocator.dupe(u8, "abcdefghijklmno") };
    try app.notes.?.addThread(.reviewer, .{
        .filename = "review.md",
        .base_ref = "HEAD",
        .base_sha = "abc",
        .created = "now",
    }, .{
        .id = try allocator.dupe(u8, "t1"),
        .path = try allocator.dupe(u8, "a.zig"),
        .group = .unstaged,
        .status = .open,
        .lifecycle = .open,
        .validity = .current,
        .context = .{
            .bytes = try allocator.dupe(u8, "change\n"),
            .original_start = 0,
            .target_start = 0,
            .target_end = 6,
        },
        .comments = comments,
    });

    var screen = try vaxis.Screen.init(allocator, .{ .rows = 8, .cols = 14, .x_pixel = 0, .y_pixel = 0 });
    defer screen.deinit(allocator);
    const window: vaxis.Window = .{
        .x_off = 0,
        .y_off = 0,
        .parent_x_off = 0,
        .parent_y_off = 0,
        .width = screen.width,
        .height = screen.height,
        .screen = &screen,
    };

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    try drawNoteDetail(arena.allocator(), window, &app);

    try std.testing.expectEqualStrings("a", screen.readCell(4, 4).?.char.grapheme);
    try std.testing.expectEqualStrings("j", screen.readCell(4, 5).?.char.grapheme);
    try std.testing.expectEqualStrings(" ", screen.readCell(13, 4).?.char.grapheme);

    screen.clear();
    app.notes.?.detail_scroll = 2;
    try drawNoteDetail(arena.allocator(), window, &app);
    try std.testing.expectEqualStrings("j", screen.readCell(4, 3).?.char.grapheme);
}

test "narrow inline review comments wrap by grapheme for both authors" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const reviewer_rows = try wrappedReviewRows(allocator, "abcdefghij", 8);
    try std.testing.expectEqual(@as(usize, 2), reviewer_rows.len);
    try std.testing.expectEqualStrings("▏ abcde", reviewer_rows[0]);
    try std.testing.expectEqualStrings("▏ fghij", reviewer_rows[1]);

    const agent_rows = try wrappedReviewRows(allocator, "ab👩‍💻cd", 7);
    try std.testing.expectEqual(@as(usize, 2), agent_rows.len);
    try std.testing.expectEqualStrings("▏ ab👩‍💻", agent_rows[0]);
    try std.testing.expectEqualStrings("▏ cd", agent_rows[1]);

    const word_rows = try wrappedReviewRows(allocator, "alpha beta", 10);
    try std.testing.expectEqual(@as(usize, 2), word_rows.len);
    try std.testing.expectEqualStrings("▏ alpha", word_rows[0]);
    try std.testing.expectEqualStrings("▏ beta", word_rows[1]);

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
    try std.testing.expectEqual(@as(usize, 1), (try wrappedReviewRows(allocator, "abcdefghij", 13)).len);
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
