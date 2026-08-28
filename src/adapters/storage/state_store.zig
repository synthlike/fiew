//! The single serialized adapter for fiew-owned persistent state.
//!
//! Every persistent write in fiew passes through one `StateStore` instance so
//! that global and per-repository JSON records share one atomic, recoverable
//! discipline:
//!
//! * schema-versioned JSON envelopes,
//! * same-directory temporary file, flush, and atomic replacement,
//! * one previous validated backup retained for recovery,
//! * refusal to overwrite unknown future schema versions,
//! * bounded, redacted diagnostics for every degraded outcome.
//!
//! The store never writes inside a repository or Git metadata; it operates only
//! on a fiew-owned base directory supplied by the composition root.

const std = @import("std");
const diagnostics = @import("../../app/diagnostics.zig");

/// Upper bound on a state file we are willing to read. Beyond this a file is
/// treated as unreadable rather than loaded into memory.
pub const max_state_bytes: usize = 4 << 20;

const primary_extension = "json";
const backup_extension = "bak";

/// Identifies one persistent record: its file basename, logical schema, and the
/// version this build writes.
pub const Descriptor = struct {
    /// Filesystem-safe basename without extension (for example `global` or a
    /// repository identity slug).
    name: []const u8,
    /// Logical schema identifier stored in, and validated against, the envelope.
    schema: []const u8,
    /// Schema version this build writes and can read.
    version: u32,
};

/// The name used for the shared global-state record.
pub const global_name = "global";

/// Build a descriptor for the global-state record.
pub fn globalDescriptor(schema: []const u8, version: u32) Descriptor {
    return .{ .name = global_name, .schema = schema, .version = version };
}

/// Build a descriptor for a per-repository record keyed by an identity slug.
pub fn repositoryDescriptor(slug: []const u8, schema: []const u8, version: u32) Descriptor {
    return .{ .name = slug, .schema = schema, .version = version };
}

/// On-disk envelope wrapping typed record data with its schema and version.
pub fn Envelope(comptime T: type) type {
    return struct {
        schema: []const u8,
        version: u32,
        data: T,
    };
}

/// Which file satisfied a successful load.
pub const Source = enum { primary, backup };

/// A successfully loaded record. Owns the parse arena until `deinit`.
pub fn Loaded(comptime T: type) type {
    return struct {
        parsed: std.json.Parsed(Envelope(T)),
        source: Source,

        pub fn value(self: *const @This()) *const T {
            return &self.parsed.value.data;
        }

        pub fn deinit(self: @This()) void {
            self.parsed.deinit();
        }
    };
}

/// Outcome of a load attempt.
pub fn LoadResult(comptime T: type) type {
    return union(enum) {
        /// A valid record was read from the primary or a recovered backup.
        loaded: Loaded(T),
        /// Neither a primary nor a backup file exists yet.
        absent,
        /// A stored file declares a newer schema version; it was left untouched.
        future_version: u32,
        /// A file existed but neither it nor any backup could be decoded.
        unrecoverable,
    };
}

pub const SaveError = error{
    /// The existing primary declares a newer schema version; refusing to
    /// overwrite it protects state written by a future build.
    FutureVersionPresent,
    WriteFailed,
} || std.mem.Allocator.Error || std.Io.Dir.ReadFileAllocError ||
    std.Io.Dir.CreateFileAtomicError || std.Io.File.Atomic.ReplaceError;

pub const LoadError = std.mem.Allocator.Error || std.Io.Dir.ReadFileAllocError;

const Inspection = union(enum) {
    valid: u32,
    future: u32,
    schema_mismatch,
    corrupt,
};

pub const StateStore = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    dir: std.Io.Dir,
    diagnostics: *diagnostics.Diagnostics,
    owns_dir: bool,
    mutex: std.Io.Mutex = .init,

    /// Wrap an already-opened, fiew-owned base directory. The store does not
    /// close a borrowed directory.
    pub fn init(
        allocator: std.mem.Allocator,
        io: std.Io,
        dir: std.Io.Dir,
        log: *diagnostics.Diagnostics,
    ) StateStore {
        return .{
            .allocator = allocator,
            .io = io,
            .dir = dir,
            .diagnostics = log,
            .owns_dir = false,
        };
    }

    /// Create and open a fiew-owned base directory tree, taking ownership so
    /// `deinit` closes it.
    pub fn openPath(
        allocator: std.mem.Allocator,
        io: std.Io,
        base_path: []const u8,
        log: *diagnostics.Diagnostics,
    ) !StateStore {
        const dir = try std.Io.Dir.cwd().createDirPathOpen(io, base_path, .{});
        return .{
            .allocator = allocator,
            .io = io,
            .dir = dir,
            .diagnostics = log,
            .owns_dir = true,
        };
    }

    pub fn deinit(self: *StateStore) void {
        if (self.owns_dir) self.dir.close(self.io);
        self.* = undefined;
    }

    /// Persist `value` for `descriptor`. Rotates a valid current primary into the
    /// backup, then atomically replaces the primary. Refuses to overwrite a
    /// primary that declares a newer schema version.
    pub fn save(
        self: *StateStore,
        comptime T: type,
        descriptor: Descriptor,
        value: T,
    ) SaveError!void {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        const primary = try self.fileName(descriptor.name, primary_extension);
        defer self.allocator.free(primary);
        const backup = try self.fileName(descriptor.name, backup_extension);
        defer self.allocator.free(backup);

        if (try self.readOptional(primary)) |existing| {
            defer self.allocator.free(existing);
            switch (self.inspect(existing, descriptor)) {
                .valid => try self.writeBytes(backup, existing),
                .future => {
                    self.note("save_future_refused", descriptor.name);
                    return error.FutureVersionPresent;
                },
                .schema_mismatch => self.note("save_schema_mismatch", descriptor.name),
                .corrupt => self.note("save_primary_corrupt", descriptor.name),
            }
        }

        const envelope: Envelope(T) = .{
            .schema = descriptor.schema,
            .version = descriptor.version,
            .data = value,
        };
        const bytes = try std.json.Stringify.valueAlloc(
            self.allocator,
            envelope,
            .{ .whitespace = .indent_2 },
        );
        defer self.allocator.free(bytes);
        try self.writeBytes(primary, bytes);
        self.note("saved", descriptor.name);
    }

    /// Load the record for `descriptor`, recovering from the backup when the
    /// primary is missing or unreadable. `result_allocator` owns the returned
    /// parse arena until the caller calls `deinit`.
    pub fn load(
        self: *StateStore,
        comptime T: type,
        descriptor: Descriptor,
        result_allocator: std.mem.Allocator,
    ) LoadError!LoadResult(T) {
        self.mutex.lockUncancelable(self.io);
        defer self.mutex.unlock(self.io);

        const primary = try self.fileName(descriptor.name, primary_extension);
        defer self.allocator.free(primary);
        const backup = try self.fileName(descriptor.name, backup_extension);
        defer self.allocator.free(backup);

        var primary_existed = false;
        if (try self.readOptional(primary)) |bytes| {
            defer self.allocator.free(bytes);
            primary_existed = true;
            switch (self.inspect(bytes, descriptor)) {
                .valid => {
                    if (parse(T, result_allocator, bytes)) |parsed| {
                        return .{ .loaded = .{ .parsed = parsed, .source = .primary } };
                    }
                    self.note("primary_typed_corrupt", descriptor.name);
                },
                .future => |version| {
                    self.note("primary_future_refused", descriptor.name);
                    return .{ .future_version = version };
                },
                .schema_mismatch => self.note("primary_schema_mismatch", descriptor.name),
                .corrupt => self.note("primary_corrupt", descriptor.name),
            }
        }

        if (try self.readOptional(backup)) |bytes| {
            defer self.allocator.free(bytes);
            switch (self.inspect(bytes, descriptor)) {
                .valid => {
                    if (parse(T, result_allocator, bytes)) |parsed| {
                        self.note("recovered_from_backup", descriptor.name);
                        return .{ .loaded = .{ .parsed = parsed, .source = .backup } };
                    }
                    self.note("backup_typed_corrupt", descriptor.name);
                },
                .future => |version| {
                    self.note("backup_future_refused", descriptor.name);
                    return .{ .future_version = version };
                },
                .schema_mismatch => self.note("backup_schema_mismatch", descriptor.name),
                .corrupt => self.note("backup_corrupt", descriptor.name),
            }
        }

        if (primary_existed) {
            self.note("unrecoverable", descriptor.name);
            return .unrecoverable;
        }
        return .absent;
    }

    fn parse(
        comptime T: type,
        result_allocator: std.mem.Allocator,
        bytes: []const u8,
    ) ?std.json.Parsed(Envelope(T)) {
        // `alloc_always` copies every string into the parse arena so the result
        // outlives the temporary file bytes this function is given.
        return std.json.parseFromSlice(
            Envelope(T),
            result_allocator,
            bytes,
            .{ .ignore_unknown_fields = true, .allocate = .alloc_always },
        ) catch null;
    }

    fn inspect(self: *StateStore, bytes: []const u8, descriptor: Descriptor) Inspection {
        const Header = struct { schema: []const u8 = "", version: u32 = 0 };
        const parsed = std.json.parseFromSlice(
            Header,
            self.allocator,
            bytes,
            .{ .ignore_unknown_fields = true },
        ) catch return .corrupt;
        defer parsed.deinit();
        if (!std.mem.eql(u8, parsed.value.schema, descriptor.schema)) return .schema_mismatch;
        if (parsed.value.version > descriptor.version) return .{ .future = parsed.value.version };
        return .{ .valid = parsed.value.version };
    }

    /// Atomically write `bytes` to `name` using a same-directory temporary file,
    /// a flush, a best-effort sync, and an atomic rename into place.
    fn writeBytes(self: *StateStore, name: []const u8, bytes: []const u8) SaveError!void {
        var atomic = try self.dir.createFileAtomic(self.io, name, .{ .replace = true });
        defer atomic.deinit(self.io);

        var write_buffer: [4096]u8 = undefined;
        var writer = atomic.file.writer(self.io, &write_buffer);
        writer.interface.writeAll(bytes) catch return error.WriteFailed;
        writer.flush() catch return error.WriteFailed;
        atomic.file.sync(self.io) catch {};
        try atomic.replace(self.io);
    }

    fn readOptional(self: *StateStore, name: []const u8) LoadError!?[]u8 {
        return self.dir.readFileAlloc(
            self.io,
            name,
            self.allocator,
            .limited64(max_state_bytes),
        ) catch |err| switch (err) {
            error.FileNotFound => null,
            else => err,
        };
    }

    fn fileName(self: *StateStore, name: []const u8, extension: []const u8) ![]u8 {
        return std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ name, extension });
    }

    /// Record a redacted diagnostic. The record name is a safe hash slug or
    /// `global`, never protected content, so it may accompany the event code.
    fn note(self: *StateStore, code: []const u8, name: []const u8) void {
        var buffer: [diagnostics.code_capacity]u8 = undefined;
        const text = std.fmt.bufPrint(&buffer, "{s}:{s}", .{ code, name }) catch code;
        self.diagnostics.record(.state_store, text, null);
    }
};

/// Resolve the platform-owned global state path from already-read environment
/// values. A null result means global persistence is unavailable; callers must
/// not invent another location.
pub fn globalStateDirectoryPath(
    allocator: std.mem.Allocator,
    os_tag: std.Target.Os.Tag,
    home: ?[]const u8,
    xdg_state_home: ?[]const u8,
) !?[]u8 {
    return switch (os_tag) {
        .macos => if (home) |value|
            if (value.len != 0 and std.fs.path.isAbsolute(value))
                try std.fs.path.join(allocator, &.{ value, "Library", "Application Support", "fiew" })
            else
                null
        else
            null,
        .linux => if (xdg_state_home) |value|
            if (value.len != 0 and std.fs.path.isAbsolute(value)) try std.fs.path.join(allocator, &.{ value, "fiew" }) else linuxHomePath(allocator, home)
        else
            linuxHomePath(allocator, home),
        else => null,
    };
}

fn linuxHomePath(allocator: std.mem.Allocator, home: ?[]const u8) !?[]u8 {
    const value = home orelse return null;
    if (value.len == 0 or !std.fs.path.isAbsolute(value)) return null;
    return try std.fs.path.join(allocator, &.{ value, ".local", "state", "fiew" });
}

pub fn dataDirectoryPath(allocator: std.mem.Allocator, home: []const u8) ![]u8 {
    return (try globalStateDirectoryPath(allocator, .macos, home, null)).?;
}

// --- Tests ---------------------------------------------------------------

const TestRecord = struct {
    label: []const u8,
    count: u32,
};

const test_schema = "fiew.test.record";
const test_version: u32 = 1;

fn testDescriptor() Descriptor {
    return .{ .name = "example", .schema = test_schema, .version = test_version };
}

fn openTempStore(
    temporary: *std.testing.TmpDir,
    log: *diagnostics.Diagnostics,
) StateStore {
    return StateStore.init(std.testing.allocator, std.testing.io, temporary.dir, log);
}

test "round trips a record through the primary file" {
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    var log: diagnostics.Diagnostics = .init;
    var store = openTempStore(&temporary, &log);

    try store.save(TestRecord, testDescriptor(), .{ .label = "hello", .count = 3 });

    var result = try store.load(TestRecord, testDescriptor(), std.testing.allocator);
    switch (result) {
        .loaded => |*loaded| {
            defer loaded.deinit();
            try std.testing.expectEqual(Source.primary, loaded.source);
            try std.testing.expectEqualStrings("hello", loaded.value().label);
            try std.testing.expectEqual(@as(u32, 3), loaded.value().count);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "absent record loads as absent" {
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    var log: diagnostics.Diagnostics = .init;
    var store = openTempStore(&temporary, &log);

    const result = try store.load(TestRecord, testDescriptor(), std.testing.allocator);
    try std.testing.expect(result == .absent);
}

test "corrupt primary recovers from the validated backup" {
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    var log: diagnostics.Diagnostics = .init;
    var store = openTempStore(&temporary, &log);

    // First save establishes the primary; the second save rotates the validated
    // "first" primary into the backup before writing "second".
    try store.save(TestRecord, testDescriptor(), .{ .label = "first", .count = 1 });
    try store.save(TestRecord, testDescriptor(), .{ .label = "second", .count = 2 });

    // Corrupt the current primary in place; the backup still holds "first".
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "example.json",
        .data = "{ this is not valid json",
    });

    var result = try store.load(TestRecord, testDescriptor(), std.testing.allocator);
    switch (result) {
        .loaded => |*loaded| {
            defer loaded.deinit();
            try std.testing.expectEqual(Source.backup, loaded.source);
            try std.testing.expectEqualStrings("first", loaded.value().label);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "interrupted write leaves the previous primary readable" {
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    var log: diagnostics.Diagnostics = .init;
    var store = openTempStore(&temporary, &log);

    try store.save(TestRecord, testDescriptor(), .{ .label = "committed", .count = 7 });

    // Simulate an interrupted write: a leftover temporary sibling must never be
    // mistaken for the primary, and the committed primary stays intact.
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "example.json.partial",
        .data = "half-written garbage",
    });

    var result = try store.load(TestRecord, testDescriptor(), std.testing.allocator);
    switch (result) {
        .loaded => |*loaded| {
            defer loaded.deinit();
            try std.testing.expectEqual(Source.primary, loaded.source);
            try std.testing.expectEqualStrings("committed", loaded.value().label);
        },
        else => return error.TestUnexpectedResult,
    }
}

test "unknown future schema is refused and never overwritten" {
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    var log: diagnostics.Diagnostics = .init;
    var store = openTempStore(&temporary, &log);

    const future_bytes =
        \\{ "schema": "fiew.test.record", "version": 99, "data": { "label": "future", "count": 0 } }
    ;
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "example.json",
        .data = future_bytes,
    });

    const result = try store.load(TestRecord, testDescriptor(), std.testing.allocator);
    switch (result) {
        .future_version => |version| try std.testing.expectEqual(@as(u32, 99), version),
        else => return error.TestUnexpectedResult,
    }

    // Saving must refuse rather than clobber the newer file.
    try std.testing.expectError(
        error.FutureVersionPresent,
        store.save(TestRecord, testDescriptor(), .{ .label = "older", .count = 1 }),
    );

    const on_disk = try temporary.dir.readFileAlloc(
        std.testing.io,
        "example.json",
        std.testing.allocator,
        .unlimited,
    );
    defer std.testing.allocator.free(on_disk);
    try std.testing.expectEqualStrings(future_bytes, on_disk);
}

test "unrecoverable when primary is corrupt and no backup exists" {
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    var log: diagnostics.Diagnostics = .init;
    var store = openTempStore(&temporary, &log);

    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "example.json",
        .data = "not json at all",
    });

    const result = try store.load(TestRecord, testDescriptor(), std.testing.allocator);
    try std.testing.expect(result == .unrecoverable);
}

test "diagnostics record recovery without leaking record data" {
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    var log: diagnostics.Diagnostics = .init;
    var store = openTempStore(&temporary, &log);

    try store.save(TestRecord, testDescriptor(), .{ .label = "first", .count = 1 });
    try store.save(TestRecord, testDescriptor(), .{ .label = "second", .count = 2 });
    try temporary.dir.writeFile(std.testing.io, .{
        .sub_path = "example.json",
        .data = "broken",
    });
    var result = try store.load(TestRecord, testDescriptor(), std.testing.allocator);
    switch (result) {
        .loaded => |*loaded| loaded.deinit(),
        else => return error.TestUnexpectedResult,
    }

    var buffer: [diagnostics.capacity]diagnostics.Entry = undefined;
    const entries = log.snapshot(&buffer);
    var saw_recovery = false;
    for (entries) |entry| {
        try std.testing.expectEqual(diagnostics.Category.state_store, entry.category);
        try std.testing.expect(std.mem.indexOf(u8, entry.detail(), "second") == null);
        if (std.mem.startsWith(u8, entry.code(), "recovered_from_backup")) saw_recovery = true;
    }
    try std.testing.expect(saw_recovery);
}

test "platform global state paths follow macOS and Linux contracts" {
    const xdg = (try globalStateDirectoryPath(std.testing.allocator, .linux, "/home/dev", "/state")).?;
    defer std.testing.allocator.free(xdg);
    try std.testing.expectEqualStrings("/state/fiew", xdg);

    const fallback = (try globalStateDirectoryPath(std.testing.allocator, .linux, "/home/dev", "")).?;
    defer std.testing.allocator.free(fallback);
    try std.testing.expectEqualStrings("/home/dev/.local/state/fiew", fallback);

    try std.testing.expect((try globalStateDirectoryPath(std.testing.allocator, .linux, null, null)) == null);
    try std.testing.expect((try globalStateDirectoryPath(std.testing.allocator, .linux, "relative", null)) == null);
    try std.testing.expect((try globalStateDirectoryPath(std.testing.allocator, .macos, null, null)) == null);
}

test "data directory path stays under the fiew-owned application support tree" {
    const path = try dataDirectoryPath(std.testing.allocator, "/Users/dev");
    defer std.testing.allocator.free(path);
    try std.testing.expectEqualStrings(
        "/Users/dev/Library/Application Support/fiew",
        path,
    );
}
