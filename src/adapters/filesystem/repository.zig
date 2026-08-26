const std = @import("std");
const document = @import("../../model/document.zig");
const project = @import("../../model/project.zig");
const text_segmentation = @import("../../ports/text_segmentation.zig");

pub const max_supported_files: usize = 10_000;

/// Read-only repository projection. It owns paths but never opens files for writing.
pub const Repository = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    root_path: []const u8,
    root_dir: std.Io.Dir,
    tree: project.Tree,

    pub fn open(
        allocator: std.mem.Allocator,
        io: std.Io,
        root_path: []const u8,
    ) !Repository {
        const owned_root = try allocator.dupe(u8, root_path);
        errdefer allocator.free(owned_root);
        var root_dir = try std.Io.Dir.cwd().openDir(io, root_path, .{
            .iterate = true,
            .follow_symlinks = false,
        });
        errdefer root_dir.close(io);

        var entries: std.ArrayList(project.Node) = .empty;
        defer entries.deinit(allocator);
        errdefer for (entries.items) |entry| allocator.free(entry.path);

        var file_count: usize = 0;
        var walker = try root_dir.walk(allocator);
        defer walker.deinit();
        while (try walker.next(io)) |walked| {
            if (std.mem.eql(u8, walked.basename, ".git")) {
                if (walked.kind == .directory) walker.leave(io);
                continue;
            }

            const kind: project.NodeKind = switch (walked.kind) {
                .directory => .directory,
                .file => .file,
                .sym_link => .symlink,
                else => .other,
            };
            if (kind == .file) file_count += 1;
            const owned_path = try allocator.dupe(u8, walked.path);
            entries.append(allocator, .{
                .path = owned_path,
                .depth = walked.depth(),
                .kind = kind,
            }) catch |err| {
                allocator.free(owned_path);
                return err;
            };
        }

        std.mem.sort(project.Node, entries.items, {}, lessThan);
        return .{
            .allocator = allocator,
            .io = io,
            .root_path = owned_root,
            .root_dir = root_dir,
            .tree = .{
                .allocator = allocator,
                .nodes = try entries.toOwnedSlice(allocator),
                .file_count = file_count,
            },
        };
    }

    pub fn deinit(self: *Repository) void {
        self.tree.deinit();
        self.allocator.free(self.root_path);
        self.root_dir.close(self.io);
        self.* = undefined;
    }

    pub fn loadDocument(
        self: Repository,
        path: []const u8,
        generation: u64,
        segmenter: text_segmentation.Segmenter,
    ) !document.Snapshot {
        const before = try self.root_dir.statFile(self.io, path, .{});
        if (before.kind != .file) return error.NotAFile;
        const bytes = try self.root_dir.readFileAlloc(
            self.io,
            path,
            self.allocator,
            .limited64(before.size +| 1),
        );
        defer self.allocator.free(bytes);
        const after = try self.root_dir.statFile(self.io, path, .{});
        if (before.inode != after.inode or before.size != after.size or
            before.mtime.nanoseconds != after.mtime.nanoseconds)
        {
            return error.FileChangedDuringRead;
        }

        return document.Snapshot.init(
            self.allocator,
            path,
            bytes,
            generation,
            .{
                .size = before.size,
                .modified_nanoseconds = before.mtime.nanoseconds,
            },
            segmenter,
        );
    }

    fn lessThan(_: void, lhs: project.Node, rhs: project.Node) bool {
        var index: usize = 0;
        while (index < lhs.path.len and index < rhs.path.len) : (index += 1) {
            const left = lhs.path[index];
            const right = rhs.path[index];
            if (left == right) continue;
            if (left == std.fs.path.sep) return true;
            if (right == std.fs.path.sep) return false;
            return left < right;
        }
        return lhs.path.len < rhs.path.len;
    }
};

fn scalarNext(_: ?*const anyopaque, text: []const u8, start: usize) usize {
    const length = std.unicode.utf8ByteSequenceLength(text[start]) catch 1;
    return @min(text.len, start + length);
}

fn scalarWidth(_: ?*const anyopaque, text: []const u8) u16 {
    return if (std.mem.eql(u8, text, "\n")) 0 else 1;
}

const scalar_segmenter: text_segmentation.Segmenter = .{
    .next_fn = scalarNext,
    .width_fn = scalarWidth,
};

test "repository scan is sorted and excludes Git metadata" {
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    try temporary.dir.createDir(std.testing.io, "src", .default_dir);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "src/z.zig", .data = "z" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "a.txt", .data = "a" });
    try temporary.dir.createDir(std.testing.io, ".git", .default_dir);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = ".git/index", .data = "private" });

    const root_path = try std.fmt.allocPrint(
        std.testing.allocator,
        ".zig-cache/tmp/{s}",
        .{temporary.sub_path},
    );
    defer std.testing.allocator.free(root_path);
    var repository = try Repository.open(std.testing.allocator, std.testing.io, root_path);
    defer repository.deinit();

    try std.testing.expectEqual(@as(usize, 2), repository.tree.file_count);
    try std.testing.expectEqualStrings("a.txt", repository.tree.nodes[0].path);
    try std.testing.expectEqualStrings("src", repository.tree.nodes[1].path);
    try std.testing.expectEqualStrings("src/z.zig", repository.tree.nodes[2].path);
}

test "loading a document never changes its source file" {
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    const original = "const café = true;\n";
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "main.zig", .data = original });

    const root_path = try std.fmt.allocPrint(
        std.testing.allocator,
        ".zig-cache/tmp/{s}",
        .{temporary.sub_path},
    );
    defer std.testing.allocator.free(root_path);
    var repository = try Repository.open(std.testing.allocator, std.testing.io, root_path);
    defer repository.deinit();
    var snapshot = try repository.loadDocument("main.zig", 1, scalar_segmenter);
    defer snapshot.deinit();
    const after = try temporary.dir.readFileAlloc(
        std.testing.io,
        "main.zig",
        std.testing.allocator,
        .unlimited,
    );
    defer std.testing.allocator.free(after);

    try std.testing.expectEqualStrings(original, snapshot.bytes);
    try std.testing.expectEqualStrings(original, after);
}
