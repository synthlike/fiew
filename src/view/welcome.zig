const std = @import("std");

pub const quotes = [_][]const u8{
    // Dry and playful.
    "No code was harmed during this review.",
    "Look, but don't touch.",
    "Suspicious until explained.",
    "Here be edge cases.",
    "The bug is probably off by one.",
    "Read-only, not opinion-free.",
    "Keep calm and check the unstaged files.",
    "A wild regression appears.",
    "Diff happens.",
    "Works on my branch.",
    "Trust, but git diff.",
    "Measure twice, approve once.",
    "The semicolon knows what it did.",
    "All lines are innocent until reviewed.",

    // Quiet and thoughtful.
    "Read first. Decide second.",
    "Every diff tells on itself.",
    "Trust the change you can explain.",
    "Small lines can carry large consequences.",
    "Review is attention made visible.",
    "Look twice before approving once.",
};

pub const quit_hint = "Press Space-q or Ctrl-c to quit";

pub const Position = struct {
    column: u16,
    row: u16,
};

pub const Layout = struct {
    quote: Position,
    quit_hint: Position,
};

pub fn select(index: usize) []const u8 {
    return quotes[index % quotes.len];
}

/// Mix the clock value before reducing it to a quote index. Real clocks often
/// advance in multiples that would otherwise select the same quote each launch.
pub fn selectSeed(seed: i96) []const u8 {
    const mixed = std.hash.Wyhash.hash(0, std.mem.asBytes(&seed));
    return select(@intCast(mixed % quotes.len));
}

pub fn layout(columns: u16, rows: u16, quote: []const u8) Layout {
    const middle_row = rows / 2;

    return .{
        .quote = .{
            .column = centeredColumn(columns, quote.len),
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

test "quote selection wraps deterministically" {
    try std.testing.expectEqualStrings(quotes[0], select(0));
    try std.testing.expectEqualStrings(quotes[0], select(quotes.len));
    try std.testing.expectEqualStrings(quotes[1], select(quotes.len + 1));
}

test "clock seeds with the same raw remainder vary after mixing" {
    const first = selectSeed(0);
    var varied = false;
    for (1..quotes.len) |step| {
        const seed: i96 = @intCast(step * quotes.len);
        if (!std.mem.eql(u8, first, selectSeed(seed))) {
            varied = true;
            break;
        }
    }
    try std.testing.expect(varied);
}

test "welcome quote and hint are centered for a typical terminal" {
    const quote = "Diff happens.";
    const result = layout(80, 24, quote);

    try std.testing.expectEqual(@as(u16, 33), result.quote.column);
    try std.testing.expectEqual(@as(u16, 12), result.quote.row);
    try std.testing.expectEqual(@as(u16, 24), result.quit_hint.column);
    try std.testing.expectEqual(@as(u16, 14), result.quit_hint.row);
}

test "welcome content adapts without underflow on a tiny terminal" {
    const result = layout(2, 1, quotes[0]);

    try std.testing.expectEqual(@as(u16, 0), result.quote.column);
    try std.testing.expectEqual(@as(u16, 0), result.quote.row);
    try std.testing.expectEqual(@as(u16, 0), result.quit_hint.column);
    try std.testing.expectEqual(@as(u16, 0), result.quit_hint.row);
}
