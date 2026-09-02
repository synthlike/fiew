//! Persisted consent for executing ZLS in canonical repositories.

const std = @import("std");
const state_store = @import("../adapters/storage/state_store.zig");
const repository_identity = @import("../model/repository_identity.zig");

pub const schema = "skaut.global/v1";
pub const version: u32 = 1;

pub const Stored = struct {
    trusted_zls_repositories: []const []const u8 = &.{},
};

pub const Trust = struct {
    allocator: std.mem.Allocator,
    slugs: std.ArrayListUnmanaged([]u8) = .empty,
    available: bool,

    pub fn init(allocator: std.mem.Allocator, available: bool) Trust {
        return .{ .allocator = allocator, .available = available };
    }

    pub fn deinit(self: *Trust) void {
        for (self.slugs.items) |slug| self.allocator.free(slug);
        self.slugs.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn load(allocator: std.mem.Allocator, store: ?*state_store.StateStore) !Trust {
        var result = Trust.init(allocator, store != null);
        errdefer result.deinit();
        const active = store orelse return result;
        var loaded = try active.load(Stored, state_store.globalDescriptor(schema, version), allocator);
        switch (loaded) {
            .loaded => |*record| {
                defer record.deinit();
                for (record.value().trusted_zls_repositories) |slug| {
                    if (!validSlug(slug) or result.contains(slug)) continue;
                    try result.slugs.append(allocator, try allocator.dupe(u8, slug));
                }
            },
            .absent => {},
            .future_version, .unrecoverable => result.available = false,
        }
        return result;
    }

    pub fn contains(self: Trust, slug: []const u8) bool {
        for (self.slugs.items) |candidate| if (std.mem.eql(u8, candidate, slug)) return true;
        return false;
    }

    pub fn grant(self: *Trust, store: *state_store.StateStore, slug: []const u8) !void {
        if (!self.available or !validSlug(slug)) return error.PersistenceUnavailable;
        const inserted = !self.contains(slug);
        if (inserted) try self.slugs.append(self.allocator, try self.allocator.dupe(u8, slug));
        errdefer if (inserted) self.remove(slug);
        try self.persist(store);
    }

    pub fn revoke(self: *Trust, store: *state_store.StateStore, slug: []const u8) !void {
        if (!self.available) return error.PersistenceUnavailable;
        var removed: ?[]u8 = null;
        var index: usize = 0;
        while (index < self.slugs.items.len) : (index += 1) {
            if (std.mem.eql(u8, self.slugs.items[index], slug)) {
                removed = self.slugs.orderedRemove(index);
                break;
            }
        }
        errdefer if (removed) |value| self.slugs.append(self.allocator, value) catch {};
        try self.persist(store);
        if (removed) |value| self.allocator.free(value);
    }

    fn remove(self: *Trust, slug: []const u8) void {
        for (self.slugs.items, 0..) |candidate, index| if (std.mem.eql(u8, candidate, slug)) {
            self.allocator.free(self.slugs.orderedRemove(index));
            return;
        };
    }

    fn persist(self: *Trust, store: *state_store.StateStore) !void {
        try store.save(Stored, state_store.globalDescriptor(schema, version), .{
            .trusted_zls_repositories = self.slugs.items,
        });
    }
};

fn validSlug(slug: []const u8) bool {
    if (slug.len != repository_identity.slug_length) return false;
    for (slug) |byte| if (!std.ascii.isHex(byte) or std.ascii.isUpper(byte)) return false;
    return true;
}

test "ZLS trust is persisted by canonical repository identity and revocable" {
    var temporary = std.testing.tmpDir(.{ .iterate = true });
    defer temporary.cleanup();
    var diagnostics: @import("diagnostics.zig").Diagnostics = .init;
    var store = state_store.StateStore.init(std.testing.allocator, std.testing.io, temporary.dir, &diagnostics);
    const slug = repository_identity.RepositoryIdentity.computeSlug("/tmp/repository");

    var trust = try Trust.load(std.testing.allocator, &store);
    try std.testing.expect(!trust.contains(&slug));
    try trust.grant(&store, &slug);
    try std.testing.expect(trust.contains(&slug));
    trust.deinit();

    var restored = try Trust.load(std.testing.allocator, &store);
    defer restored.deinit();
    try std.testing.expect(restored.contains(&slug));
    try restored.revoke(&store, &slug);
    try std.testing.expect(!restored.contains(&slug));
}

test "trust cannot be granted without durable global state" {
    const slug = repository_identity.RepositoryIdentity.computeSlug("/tmp/repository");
    var trust = Trust.init(std.testing.allocator, false);
    defer trust.deinit();
    var diagnostics: @import("diagnostics.zig").Diagnostics = .init;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var store = state_store.StateStore.init(std.testing.allocator, std.testing.io, temporary.dir, &diagnostics);
    try std.testing.expectError(error.PersistenceUnavailable, trust.grant(&store, &slug));
}
