const std = @import("std");

pub const title = "fiew";
pub const subtitle = "read-first code and diff viewer";
pub const quit_hint = "Press q or Ctrl-C to quit";

pub const Position = struct {
    column: u16,
    row: u16,
};

pub const Layout = struct {
    title: Position,
    subtitle: Position,
    quit_hint: Position,
};

pub fn layout(columns: u16, rows: u16) Layout {
    const middle_row = rows / 2;

    return .{
        .title = .{
            .column = centeredColumn(columns, title.len),
            .row = middle_row -| 1,
        },
        .subtitle = .{
            .column = centeredColumn(columns, subtitle.len),
            .row = middle_row,
        },
        .quit_hint = .{
            .column = centeredColumn(columns, quit_hint.len),
            .row = if (rows == 0) 0 else @min(rows - 1, middle_row +| 2),
        },
    };
}

fn centeredColumn(columns: u16, text_width: usize) u16 {
    const width: u16 = @intCast(@min(text_width, std.math.maxInt(u16)));
    return (columns -| width) / 2;
}

test "welcome content is centered for a typical terminal" {
    const result = layout(80, 24);

    try std.testing.expectEqual(@as(u16, 38), result.title.column);
    try std.testing.expectEqual(@as(u16, 11), result.title.row);
    try std.testing.expectEqual(@as(u16, 24), result.subtitle.column);
    try std.testing.expectEqual(@as(u16, 12), result.subtitle.row);
    try std.testing.expectEqual(@as(u16, 27), result.quit_hint.column);
    try std.testing.expectEqual(@as(u16, 14), result.quit_hint.row);
}

test "welcome content adapts without underflow on a tiny terminal" {
    const result = layout(2, 1);

    try std.testing.expectEqual(@as(u16, 0), result.title.column);
    try std.testing.expectEqual(@as(u16, 0), result.title.row);
    try std.testing.expectEqual(@as(u16, 0), result.subtitle.column);
    try std.testing.expectEqual(@as(u16, 0), result.quit_hint.row);
}
