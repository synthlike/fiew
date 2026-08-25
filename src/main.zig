const terminal = @import("adapters/terminal/vaxis_terminal.zig");

pub fn main(init: @import("std").process.Init) !void {
    try terminal.run(init);
}

test {
    @import("std").testing.refAllDecls(@This());
}
