const std = @import("std");
const app_state = @import("../app/state.zig");
const commands = @import("../app/commands.zig");
const workspace = @import("workspace.zig");

pub const Rect = struct {
    column: u16,
    row: u16,
    width: u16,
    height: u16,
};

pub const Kind = enum {
    unsupported,
    workspace,
};

pub const Plan = struct {
    kind: Kind,
    columns: u16,
    rows: u16,
    sidebar_mode: workspace.SidebarMode,
    sidebar: Rect,
    main: Rect,
    status: Rect,
    mode: app_state.Mode,
    focus: app_state.Focus,
    surface: commands.Surface,
};

/// Pure projection from application state and terminal dimensions.
pub fn build(
    columns: u16,
    rows: u16,
    app: *const app_state.App,
    session: *const commands.Session,
) Plan {
    const dimensions = workspace.layout(columns, rows, app.sidebar_visible);
    if (!dimensions.supported) {
        return .{
            .kind = .unsupported,
            .columns = columns,
            .rows = rows,
            .sidebar_mode = .hidden,
            .sidebar = .{ .column = 0, .row = 0, .width = 0, .height = 0 },
            .main = .{ .column = 0, .row = 0, .width = columns, .height = rows },
            .status = .{ .column = 0, .row = rows, .width = 0, .height = 0 },
            .mode = app.mode,
            .focus = app.focus,
            .surface = session.surface,
        };
    }
    return .{
        .kind = .workspace,
        .columns = columns,
        .rows = rows,
        .sidebar_mode = dimensions.sidebar_mode,
        .sidebar = .{
            .column = 0,
            .row = 0,
            .width = dimensions.sidebar_width,
            .height = dimensions.content_height,
        },
        .main = .{
            .column = dimensions.main_column,
            .row = 0,
            .width = dimensions.main_width,
            .height = dimensions.content_height,
        },
        .status = .{
            .column = 0,
            .row = dimensions.content_height,
            .width = columns,
            .height = 1,
        },
        .mode = app.mode,
        .focus = app.focus,
        .surface = session.surface,
    };
}

pub fn snapshot(plan: Plan, buffer: []u8) ![]const u8 {
    return std.fmt.bufPrint(
        buffer,
        "{s} {d}x{d}\nmain {d},{d} {d}x{d}\nsidebar {s} {d},{d} {d}x{d}\nstatus {d},{d} {d}x{d}\nmode {s} focus {s} surface {s}\n",
        .{
            @tagName(plan.kind),
            plan.columns,
            plan.rows,
            plan.main.column,
            plan.main.row,
            plan.main.width,
            plan.main.height,
            @tagName(plan.sidebar_mode),
            plan.sidebar.column,
            plan.sidebar.row,
            plan.sidebar.width,
            plan.sidebar.height,
            plan.status.column,
            plan.status.row,
            plan.status.width,
            plan.status.height,
            @tagName(plan.mode),
            @tagName(plan.focus),
            @tagName(plan.surface),
        },
    );
}

test "fixed-dimension RenderPlan snapshots cover wide overlay and unsupported workspaces" {
    var app = try testApp();
    defer app.deinit();
    var session = commands.Session.init(std.testing.allocator);
    defer session.deinit();
    var buffer: [512]u8 = undefined;

    try std.testing.expectEqualStrings(
        "workspace 120x30\nmain 36,0 84x29\nsidebar beside 0,0 36x29\nstatus 0,29 120x1\nmode normal focus sidebar surface none\n",
        try snapshot(build(120, 30, &app, &session), &buffer),
    );
    try std.testing.expectEqualStrings(
        "workspace 80x24\nmain 0,0 80x23\nsidebar overlay 0,0 24x23\nstatus 0,23 80x1\nmode normal focus sidebar surface none\n",
        try snapshot(build(80, 24, &app, &session), &buffer),
    );
    try std.testing.expectEqualStrings(
        "unsupported 59x19\nmain 0,0 59x19\nsidebar hidden 0,0 0x0\nstatus 0,19 0x0\nmode normal focus sidebar surface none\n",
        try snapshot(build(59, 19, &app, &session), &buffer),
    );
}

fn testApp() !app_state.App {
    const project = @import("../model/project.zig");
    const Static = struct {
        var nodes = [_]project.Node{};
        var tree: project.Tree = .{ .allocator = std.testing.allocator, .nodes = &nodes, .file_count = 0 };
    };
    return app_state.App.init(std.testing.allocator, &Static.tree);
}
