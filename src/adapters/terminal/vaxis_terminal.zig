const std = @import("std");
const vaxis = @import("vaxis");
const fiew = @import("fiew");

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

pub fn run(init: std.process.Init) !void {
    const allocator = init.gpa;

    var read_buffer: [1024]u8 = undefined;
    var tty: vaxis.Tty = try .init(init.io, &read_buffer);
    defer tty.deinit();

    var vx = try vaxis.init(init.io, allocator, init.environ_map, .{
        .kitty_keyboard_flags = .{ .report_events = true },
    });
    defer vx.deinit(allocator, tty.writer());

    var loop: vaxis.Loop(Event) = .init(init.io, &tty, &vx);
    try loop.start();
    defer loop.stop();

    try vx.enterAltScreen(tty.writer());
    try tty.writer().flush();

    // Capability detection is deliberately bounded so startup cannot wait
    // indefinitely for a terminal response.
    try vx.queryTerminal(tty.writer(), .fromSeconds(1));

    while (true) {
        const event = try loop.nextEvent();
        switch (event) {
            .key_press => |key| {
                if (key.matches('q', .{}) or key.matches('c', .{ .ctrl = true })) {
                    return;
                }
            },
            .winsize => |winsize| try vx.resize(allocator, tty.writer(), winsize),
        }

        drawWelcome(vx.window());
        try vx.render(tty.writer());
        try tty.writer().flush();
    }
}

fn drawWelcome(window: vaxis.Window) void {
    window.clear();
    window.hideCursor();

    const positions = fiew.welcome.layout(window.width, window.height);
    _ = window.printSegment(.{
        .text = fiew.welcome.title,
        .style = .{ .bold = true },
    }, .{
        .row_offset = positions.title.row,
        .col_offset = positions.title.column,
        .wrap = .none,
    });
    _ = window.printSegment(.{
        .text = fiew.welcome.subtitle,
    }, .{
        .row_offset = positions.subtitle.row,
        .col_offset = positions.subtitle.column,
        .wrap = .none,
    });
    _ = window.printSegment(.{
        .text = fiew.welcome.quit_hint,
        .style = .{ .dim = true },
    }, .{
        .row_offset = positions.quit_hint.row,
        .col_offset = positions.quit_hint.column,
        .wrap = .none,
    });
}

test {
    std.testing.refAllDecls(@This());
}
