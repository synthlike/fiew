const std = @import("std");
const fiew = @import("fiew");
const terminal = @import("adapters/terminal/vaxis_terminal.zig");

pub fn main(init: std.process.Init) !void {
    const exit_code = run(init) catch |err| blk: {
        writeError(init.io, err);
        break :blk 2;
    };
    if (exit_code != 0) std.process.exit(exit_code);
}

// so far so good!

fn run(init: std.process.Init) !u8 {
    var args: std.ArrayList([]const u8) = .empty;
    defer args.deinit(init.gpa);
    var iterator = std.process.Args.Iterator.init(init.minimal.args);
    _ = iterator.skip();
    while (iterator.next()) |arg| try args.append(init.gpa, arg);

    if (args.items.len == 0) return terminal.run(init, .{});
    if (args.items.len == 1 and (std.mem.eql(u8, args.items[0], "version") or std.mem.eql(u8, args.items[0], "--version"))) {
        try writeVersion(init.io);
        return 0;
    }
    if (isHelp(args.items[0])) {
        try writeStdout(init.io, generalHelp);
        return 0;
    }
    if (std.mem.eql(u8, args.items[0], "help")) {
        try writeStdout(init.io, generalHelp);
        return 0;
    }
    if (!std.mem.eql(u8, args.items[0], "review")) {
        if (args.items.len != 1 or std.mem.startsWith(u8, args.items[0], "-"))
            return error.InvalidArguments;
        return terminal.run(init, .{ .root_path = args.items[0] });
    }

    if (args.items.len == 2 and (std.mem.eql(u8, args.items[1], "help") or isHelp(args.items[1]))) {
        try writeStdout(init.io, reviewHelp);
        return 0;
    }
    const command = try fiew.review_cli.parse(args.items[1..]);
    return runReview(init, command);
}

fn isHelp(arg: []const u8) bool {
    return std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help");
}

const generalHelp =
    \\Usage: fiew [<repository-or-file>]
    \\       fiew review <command> [options]
    \\       fiew version | --version
    \\       fiew help | -h | --help
    \\Open a read-first Git review workspace, optionally focused on a file.
    \\Use Space r d for Review Diff and Space r t for Review Threads.
    \\Run 'fiew review help' for the non-interactive review interface.
;

const reviewHelp =
    \\Usage: fiew review <command> [options]
    \\Commands:
    \\  start [--name <slug>] [--repo <path>]
    \\  open [<review-id>] [--repo <path>]
    \\  show [<review-id>] [--format json|markdown] [--repo <path>]
    \\  reply [<review-id>] <thread-id> --body-file <path> [--repo <path>]
    \\Agents may only append replies. Reviewers create, resolve, reopen, and
    \\delete threads. 'show' and 'reply' use the current review by default.
;

fn runReview(init: std.process.Init, command: fiew.review_cli.Command) !u8 {
    switch (command) {
        .start => |options| {
            var repository = try openRepository(init, options.repo);
            defer repository.deinit();
            const now = std.Io.Timestamp.now(init.io, .real).nanoseconds;
            const seconds: u64 = @intCast(@divFloor(now, std.time.ns_per_s));
            const sha = try headSha(init.gpa, init.io, repository.root_dir);
            defer init.gpa.free(sha);
            var created = try fiew.review_cli.create(
                init.gpa,
                init.io,
                repository.root_dir,
                seconds,
                options.name,
                sha,
            );
            defer created.deinit();
            var handoff: StartHandoff = .{
                .init = init,
                .root_path = repository.root_path,
                .review_filename = created.filename,
            };
            return fiew.review_cli.afterInteractive(
                &handoff,
                created.id,
                StartHandoff.interactive,
                StartHandoff.output,
            );
        },
        .open => |options| {
            var repository = try openRepository(init, options.repo);
            defer repository.deinit();
            const id = try fiew.review_cli.resolveId(init.gpa, init.io, repository.root_dir, options.id);
            defer init.gpa.free(id);
            const filename = try fiew.review_cli.filenameForId(init.gpa, id);
            defer init.gpa.free(filename);
            var checked = try fiew.review_store.loadOne(init.gpa, init.io, repository.root_dir, filename);
            checked.deinit();
            if (options.id != null) try fiew.review_cli.makeCurrent(init.gpa, init.io, repository.root_dir, id);
            return terminal.run(init, .{
                .root_path = repository.root_path,
                .review_filename = filename,
            });
        },
        .show => |options| {
            var repository = try openRepository(init, options.repo);
            defer repository.deinit();
            const id = try fiew.review_cli.resolveId(init.gpa, init.io, repository.root_dir, options.id);
            defer init.gpa.free(id);
            var loaded = try fiew.review_cli.load(init.gpa, init.io, repository.root_dir, id);
            defer loaded.deinit();
            const output = try fiew.review_cli.render(init.gpa, id, loaded.entries[0].review, options.format);
            defer init.gpa.free(output);
            try writeStdout(init.io, output);
            if (options.format == .markdown and (output.len == 0 or output[output.len - 1] != '\n'))
                try writeStdout(init.io, "\n");
            return if (fiew.review_cli.approved(loaded.entries[0].review)) 0 else 1;
        },
        .reply => |options| {
            const body = try std.Io.Dir.cwd().readFileAlloc(
                init.io,
                options.body_file,
                init.gpa,
                .limited64(fiew.review_store.max_review_bytes),
            );
            defer init.gpa.free(body);
            var repository = try openRepository(init, options.repo);
            defer repository.deinit();
            const id = try fiew.review_cli.resolveId(init.gpa, init.io, repository.root_dir, options.id);
            defer init.gpa.free(id);
            try fiew.review_cli.appendAgentReply(
                init.gpa,
                init.io,
                repository.root_dir,
                id,
                options.thread_id,
                body,
            );
            var loaded = try fiew.review_cli.load(init.gpa, init.io, repository.root_dir, id);
            defer loaded.deinit();
            return if (fiew.review_cli.approved(loaded.entries[0].review)) 0 else 1;
        },
    }
}

const StartHandoff = struct {
    init: std.process.Init,
    root_path: []const u8,
    review_filename: []const u8,

    fn interactive(self: *StartHandoff) !u8 {
        return terminal.run(self.init, .{
            .root_path = self.root_path,
            .review_filename = self.review_filename,
        });
    }

    fn output(self: *StartHandoff, id: []const u8) !void {
        // interactive returned through all terminal-restoration defers.
        try writeStdout(self.init.io, id);
        try writeStdout(self.init.io, "\n");
    }
};

fn openRepository(init: std.process.Init, requested_path: []const u8) !fiew.filesystem.Repository {
    var requested = try std.Io.Dir.cwd().openDir(init.io, requested_path, .{});
    defer requested.close(init.io);
    var canonical: ?[]u8 = null;
    defer if (canonical) |path| init.gpa.free(path);
    switch (fiew.git.discover(init.gpa, init.io, requested) catch .not_a_repository) {
        .ready => |context| {
            var owned = context;
            defer owned.deinit();
            canonical = try init.gpa.dupe(u8, owned.toplevel);
        },
        else => {},
    }
    return fiew.filesystem.Repository.open(init.gpa, init.io, canonical orelse requested_path);
}

fn headSha(allocator: std.mem.Allocator, io: std.Io, dir: std.Io.Dir) ![]u8 {
    var result = fiew.git_command.run(allocator, io, dir, &.{ "rev-parse", "HEAD" }) catch
        return allocator.dupe(u8, "");
    defer result.deinit();
    if (!result.succeeded()) return allocator.dupe(u8, "");
    return allocator.dupe(u8, std.mem.trimEnd(u8, std.mem.sliceTo(result.stdout, '\n'), "\r"));
}

fn writeVersion(io: std.Io) !void {
    var buffer: [4096]u8 = undefined;
    var writer = std.Io.File.stdout().writer(io, &buffer);
    try fiew.version.write(&writer.interface);
    try writer.interface.flush();
}

fn writeStdout(io: std.Io, bytes: []const u8) !void {
    var buffer: [4096]u8 = undefined;
    var writer = std.Io.File.stdout().writer(io, &buffer);
    try writer.interface.writeAll(bytes);
    try writer.interface.flush();
}

fn writeError(io: std.Io, err: anyerror) void {
    var buffer: [512]u8 = undefined;
    var writer = std.Io.File.stderr().writer(io, &buffer);
    writer.interface.print("fiew: {s}\n", .{@errorName(err)}) catch return;
    writer.interface.flush() catch {};
}

test {
    std.testing.refAllDecls(@This());
}
