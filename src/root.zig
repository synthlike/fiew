//! Fiew-owned application types and behavior.

const std = @import("std");

pub const app = @import("app/state.zig");
pub const commands = @import("app/commands.zig");
pub const diagnostics = @import("app/diagnostics.zig");
pub const document = @import("model/document.zig");
pub const notes = @import("app/notes.zig");
pub const filesystem = @import("adapters/filesystem/repository.zig");
pub const git = @import("adapters/git/repository.zig");
pub const git_job = @import("app/git_job.zig");
pub const git_review = @import("app/git_review.zig");
pub const git_changes = @import("adapters/git/changes.zig");
pub const git_command = @import("adapters/git/command.zig");
pub const git_diff = @import("adapters/git/diff.zig");
pub const git_model = @import("model/git.zig");
pub const project = @import("model/project.zig");
pub const project_browser = @import("app/project_browser.zig");
pub const render_plan = @import("view/render_plan.zig");
pub const repository_identity = @import("model/repository_identity.zig");
pub const review = @import("model/review.zig");
pub const review_cli = @import("app/review_cli.zig");
pub const review_store = @import("adapters/storage/review_store.zig");
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
