//! Fiew-owned application types and behavior.

const std = @import("std");

pub const welcome = @import("view/welcome.zig");

test {
    std.testing.refAllDecls(@This());
}
