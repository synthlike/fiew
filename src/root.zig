//! Fiew-owned application types and behavior.

const std = @import("std");

pub const app = @import("app/state.zig");
pub const document = @import("model/document.zig");
pub const filesystem = @import("adapters/filesystem/repository.zig");
pub const project = @import("model/project.zig");
pub const project_browser = @import("app/project_browser.zig");
pub const text_segmentation = @import("ports/text_segmentation.zig");
pub const welcome = @import("view/welcome.zig");
pub const workspace = @import("view/workspace.zig");

test {
    std.testing.refAllDecls(@This());
}
