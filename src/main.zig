const std = @import("std");
const terminal = @import("adapters/terminal/vaxis_terminal.zig");

pub fn main(init: std.process.Init) !void {
    const exit_code = try terminal.run(init);
    if (exit_code != 0) std.process.exit(exit_code);
}

test {
    std.testing.refAllDecls(@This());
}
