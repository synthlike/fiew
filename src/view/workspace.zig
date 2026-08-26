const std = @import("std");

pub const minimum_columns: u16 = 60;
pub const minimum_rows: u16 = 20;
pub const overlay_breakpoint: u16 = 100;

pub const SidebarMode = enum {
    hidden,
    beside,
    overlay,
};

pub const Layout = struct {
    supported: bool,
    sidebar_mode: SidebarMode,
    sidebar_width: u16,
    main_column: u16,
    main_width: u16,
    content_height: u16,
};

pub fn layout(columns: u16, rows: u16, sidebar_visible: bool) Layout {
    if (columns < minimum_columns or rows < minimum_rows) {
        return .{
            .supported = false,
            .sidebar_mode = .hidden,
            .sidebar_width = 0,
            .main_column = 0,
            .main_width = columns,
            .content_height = rows,
        };
    }

    const content_height = rows - 1;
    if (!sidebar_visible) {
        return .{
            .supported = true,
            .sidebar_mode = .hidden,
            .sidebar_width = 0,
            .main_column = 0,
            .main_width = columns,
            .content_height = content_height,
        };
    }
    const proportional: u16 = @intCast((@as(u32, columns) * 30) / 100);
    if (columns < overlay_breakpoint) {
        return .{
            .supported = true,
            .sidebar_mode = .overlay,
            .sidebar_width = std.math.clamp(proportional, 24, 40),
            .main_column = 0,
            .main_width = columns,
            .content_height = content_height,
        };
    }

    const sidebar_width = std.math.clamp(proportional, 24, 40);
    return .{
        .supported = true,
        .sidebar_mode = .beside,
        .sidebar_width = sidebar_width,
        .main_column = sidebar_width,
        .main_width = columns - sidebar_width,
        .content_height = content_height,
    };
}

test "wide workspace clamps the thirty percent sidebar" {
    try std.testing.expectEqual(@as(u16, 30), layout(100, 30, true).sidebar_width);
    try std.testing.expectEqual(@as(u16, 40), layout(200, 30, true).sidebar_width);
    try std.testing.expectEqual(SidebarMode.beside, layout(100, 30, true).sidebar_mode);
}

test "narrow workspace overlays and tiny workspace is unsupported" {
    try std.testing.expectEqual(SidebarMode.overlay, layout(99, 20, true).sidebar_mode);
    try std.testing.expectEqual(@as(u16, 29), layout(99, 20, true).sidebar_width);
    try std.testing.expect(!layout(59, 20, true).supported);
    try std.testing.expect(!layout(60, 19, true).supported);
}
