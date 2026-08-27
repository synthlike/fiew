//! Fiew-owned application types and behavior.

const std = @import("std");

pub const app = @import("app/state.zig");
pub const commands = @import("app/commands.zig");
pub const diagnostics = @import("app/diagnostics.zig");
pub const document = @import("model/document.zig");
pub const filesystem = @import("adapters/filesystem/repository.zig");
pub const project = @import("model/project.zig");
pub const project_browser = @import("app/project_browser.zig");
pub const render_plan = @import("view/render_plan.zig");
pub const repository_identity = @import("model/repository_identity.zig");
pub const state_store = @import("adapters/storage/state_store.zig");
pub const parse_job = @import("adapters/treesitter/parse_job.zig");
pub const syntax = @import("model/syntax.zig");
pub const text_segmentation = @import("ports/text_segmentation.zig");
pub const zig_syntax = @import("adapters/treesitter/zig_syntax.zig");
pub const welcome = @import("view/welcome.zig");
pub const workspace = @import("view/workspace.zig");

test {
    std.testing.refAllDecls(@This());
}
