//! Stable identity for a repository's Skaut-owned state.
//!
//! Per-repository state lives in files named by a deterministic, filesystem-safe
//! slug derived from the repository's canonical path. The slug is a 128-bit hash
//! rendered as lowercase hex so it never collides with path separators or
//! reserved characters, while the canonical path is retained for anchoring and
//! diagnostics.

const std = @import("std");

/// Hex length of a rendered slug (128 bits).
pub const slug_length: usize = 32;

pub const RepositoryIdentity = struct {
    allocator: std.mem.Allocator,
    canonical_path: []const u8,
    slug_buffer: [slug_length]u8,

    /// Build an identity from an already-canonical absolute repository path.
    /// Canonicalization (symlink resolution) is the adapter's responsibility.
    pub fn fromCanonicalPath(
        allocator: std.mem.Allocator,
        path: []const u8,
    ) !RepositoryIdentity {
        const normalized = normalize(path);
        const owned = try allocator.dupe(u8, normalized);
        return .{
            .allocator = allocator,
            .canonical_path = owned,
            .slug_buffer = computeSlug(normalized),
        };
    }

    pub fn deinit(self: *RepositoryIdentity) void {
        self.allocator.free(self.canonical_path);
        self.* = undefined;
    }

    pub fn slug(self: *const RepositoryIdentity) []const u8 {
        return &self.slug_buffer;
    }

    /// Render the slug for arbitrary paths without allocating an identity.
    pub fn computeSlug(path: []const u8) [slug_length]u8 {
        const normalized = normalize(path);
        const high = std.hash.Wyhash.hash(0x1ff1_5ea1_ed57_a7e5, normalized);
        const low = std.hash.Wyhash.hash(0xf1ee_0000_0000_0001, normalized);
        var digest: [16]u8 = undefined;
        std.mem.writeInt(u64, digest[0..8], high, .big);
        std.mem.writeInt(u64, digest[8..16], low, .big);
        return std.fmt.bytesToHex(digest, .lower);
    }

    /// Drop a single trailing separator so equivalent paths share an identity,
    /// while preserving the filesystem root.
    fn normalize(path: []const u8) []const u8 {
        if (path.len > 1 and path[path.len - 1] == std.fs.path.sep) {
            return path[0 .. path.len - 1];
        }
        return path;
    }
};

test "identical canonical paths share a slug" {
    var first = try RepositoryIdentity.fromCanonicalPath(std.testing.allocator, "/Users/dev/project");
    defer first.deinit();
    var second = try RepositoryIdentity.fromCanonicalPath(std.testing.allocator, "/Users/dev/project/");
    defer second.deinit();

    try std.testing.expectEqualStrings(first.slug(), second.slug());
    try std.testing.expectEqualStrings("/Users/dev/project", second.canonical_path);
}

test "distinct paths produce distinct slugs" {
    var first = try RepositoryIdentity.fromCanonicalPath(std.testing.allocator, "/Users/dev/a");
    defer first.deinit();
    var second = try RepositoryIdentity.fromCanonicalPath(std.testing.allocator, "/Users/dev/b");
    defer second.deinit();

    try std.testing.expect(!std.mem.eql(u8, first.slug(), second.slug()));
}

test "slug is filesystem-safe lowercase hex" {
    const slug = RepositoryIdentity.computeSlug("/tmp/some repo/with:weird*chars");
    try std.testing.expectEqual(slug_length, slug.len);
    for (slug) |character| {
        const is_hex = (character >= '0' and character <= '9') or
            (character >= 'a' and character <= 'f');
        try std.testing.expect(is_hex);
    }
}
