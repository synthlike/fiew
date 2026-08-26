const std = @import("std");
const vaxis = @import("vaxis");
const fiew = @import("fiew");

const Event = union(enum) {
    key_press: vaxis.Key,
    mouse: vaxis.Mouse,
    winsize: vaxis.Winsize,
};

pub fn run(init: std.process.Init) !void {
    const allocator = init.gpa;
    var args = std.process.Args.Iterator.init(init.minimal.args);
    _ = args.skip();
    const root_path = args.next() orelse ".";

    var repository = try fiew.filesystem.Repository.open(allocator, init.io, root_path);
    defer repository.deinit();
    var app = try fiew.app.App.init(allocator, &repository.tree);
    defer app.deinit();

    const segmenter: fiew.text_segmentation.Segmenter = .{
        .next_fn = nextGrapheme,
        .width_fn = graphemeWidth,
    };
    var generation: u64 = 0;
    try previewSelection(&app, repository, segmenter, &generation);

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
    try vx.queryTerminal(tty.writer(), .fromSeconds(1));
    try vx.setMouseMode(tty.writer(), true);
    try tty.writer().flush();

    var frame_arena = std.heap.ArenaAllocator.init(allocator);
    defer frame_arena.deinit();
    while (true) {
        const event = try loop.nextEvent();
        switch (event) {
            .key_press => |key| {
                if (key.matches('q', .{}) or key.matches('c', .{ .ctrl = true })) return;
                try handleKey(&app, repository, segmenter, &generation, key, vx.window());
            },
            .mouse => |mouse| try handleMouse(
                &app,
                repository,
                segmenter,
                &generation,
                mouse,
                vx.window(),
            ),
            .winsize => |winsize| {
                try vx.resize(allocator, tty.writer(), winsize);
                const dimensions = fiew.workspace.layout(winsize.cols, winsize.rows, app.sidebar_visible);
                const viewport_height = dimensions.content_height -| 2;
                app.browser.ensureVisible(viewport_height);
                app.ensureCurrentDocumentVisible(viewport_height, dimensions.main_width -| 6);
            },
        }

        _ = frame_arena.reset(.retain_capacity);
        try draw(frame_arena.allocator(), vx.window(), &app, repository.root_path);
        try vx.render(tty.writer());
        try tty.writer().flush();
    }
}

fn handleKey(
    app: *fiew.app.App,
    repository: fiew.filesystem.Repository,
    segmenter: fiew.text_segmentation.Segmenter,
    generation: *u64,
    key: vaxis.Key,
    window: vaxis.Window,
) !void {
    const dimensions = fiew.workspace.layout(window.width, window.height, app.sidebar_visible);
    const sidebar_rows = dimensions.content_height -| 2;
    const document_rows = dimensions.content_height -| 2;
    const document_columns = dimensions.main_width -| 6;

    if (key.matches(vaxis.Key.tab, .{}) or key.matches(vaxis.Key.tab, .{ .shift = true })) {
        app.toggleFocus();
        return;
    }
    if (key.matches('b', .{})) {
        if (app.sidebar_visible) app.collapseSidebar() else app.showSidebar();
        return;
    }

    switch (app.focus) {
        .sidebar => {
            if (key.matches('j', .{}) or key.matches(vaxis.Key.down, .{})) {
                app.browser.move(1, sidebar_rows);
                try previewSelection(app, repository, segmenter, generation);
            } else if (key.matches('k', .{}) or key.matches(vaxis.Key.up, .{})) {
                app.browser.move(-1, sidebar_rows);
                try previewSelection(app, repository, segmenter, generation);
            } else if (key.matches('h', .{}) or key.matches(vaxis.Key.left, .{})) {
                try app.browser.collapseOrParent(sidebar_rows);
                try previewSelection(app, repository, segmenter, generation);
            } else if (key.matches('l', .{}) or key.matches(vaxis.Key.right, .{})) {
                try app.browser.expandOrChild(sidebar_rows);
                try previewSelection(app, repository, segmenter, generation);
            } else if (key.matches(vaxis.Key.enter, .{})) {
                const node = app.browser.selectedNode() orelse return;
                if (node.kind == .directory) {
                    _ = try app.browser.toggleSelected(sidebar_rows);
                    app.clearPreview();
                } else if (node.kind == .file) {
                    if (app.preview == null) try previewSelection(app, repository, segmenter, generation);
                    _ = app.pinPreview();
                }
            } else if (key.matches(vaxis.Key.escape, .{})) {
                app.clearPreview();
            }
        },
        .main => {
            if (key.matches('h', .{}) or key.matches(vaxis.Key.left, .{})) {
                app.moveHorizontal(-1, document_columns);
            } else if (key.matches('l', .{}) or key.matches(vaxis.Key.right, .{})) {
                app.moveHorizontal(1, document_columns);
            } else if (key.matches('j', .{}) or key.matches(vaxis.Key.down, .{})) {
                app.moveVertical(1, document_rows, document_columns);
            } else if (key.matches('k', .{}) or key.matches(vaxis.Key.up, .{})) {
                app.moveVertical(-1, document_rows, document_columns);
            } else if (key.matches(vaxis.Key.escape, .{})) {
                app.showSidebar();
            }
        },
    }
}

fn handleMouse(
    app: *fiew.app.App,
    repository: fiew.filesystem.Repository,
    segmenter: fiew.text_segmentation.Segmenter,
    generation: *u64,
    mouse: vaxis.Mouse,
    window: vaxis.Window,
) !void {
    if (mouse.type != .press or mouse.button != .left or mouse.col < 0 or mouse.row < 0) return;
    const dimensions = fiew.workspace.layout(window.width, window.height, app.sidebar_visible);
    if (!dimensions.supported or @as(u16, @intCast(mouse.row)) >= dimensions.content_height) return;
    const column: u16 = @intCast(mouse.col);
    const row: u16 = @intCast(mouse.row);
    if (dimensions.sidebar_mode != .hidden and column < dimensions.sidebar_width) {
        app.focus = .sidebar;
        if (row >= 2) {
            const visible_index = app.browser.scroll + row - 2;
            app.browser.selectVisible(visible_index, dimensions.content_height -| 2);
            try previewSelection(app, repository, segmenter, generation);
        }
    } else {
        app.focus = .main;
    }
}

fn previewSelection(
    app: *fiew.app.App,
    repository: fiew.filesystem.Repository,
    segmenter: fiew.text_segmentation.Segmenter,
    generation: *u64,
) !void {
    const node = app.browser.selectedNode() orelse {
        app.clearPreview();
        return;
    };
    if (node.kind != .file) {
        app.clearPreview();
        return;
    }
    generation.* +%= 1;
    const snapshot = repository.loadDocument(node.path, generation.*, segmenter) catch |err| {
        app.clearPreview();
        app.feedback = @errorName(err);
        return;
    };
    app.showPreview(snapshot);
}

fn draw(
    allocator: std.mem.Allocator,
    window: vaxis.Window,
    app: *const fiew.app.App,
    root_path: []const u8,
) !void {
    window.clear();
    window.hideCursor();
    const dimensions = fiew.workspace.layout(window.width, window.height, app.sidebar_visible);
    if (!dimensions.supported) {
        _ = window.printSegment(.{
            .text = "Terminal too small; fiew requires at least 60x20",
            .style = .{ .bold = true },
        }, .{ .row_offset = window.height / 2, .wrap = .none });
        return;
    }

    const content = window.child(.{ .height = dimensions.content_height });
    const main = content.child(.{
        .x_off = dimensions.main_column,
        .width = dimensions.main_width,
    });
    try drawDocument(allocator, main, app);
    if (dimensions.sidebar_mode != .hidden) {
        const sidebar = content.child(.{
            .width = dimensions.sidebar_width,
            .border = .{
                .where = .right,
                .style = if (app.focus == .sidebar) .{ .bold = true } else .{},
            },
        });
        try drawSidebar(allocator, sidebar, app, root_path);
    }

    const status = window.child(.{ .y_off = dimensions.content_height, .height = 1 });
    try drawStatus(allocator, status, app);
}

fn drawSidebar(
    allocator: std.mem.Allocator,
    window: vaxis.Window,
    app: *const fiew.app.App,
    root_path: []const u8,
) !void {
    _ = window.printSegment(.{
        .text = " Project ",
        .style = .{ .bold = true, .reverse = app.focus == .sidebar },
    }, .{ .wrap = .none });
    const root_name = try sanitizeLine(allocator, std.fs.path.basename(root_path), window.width -| 1);
    _ = window.printSegment(.{ .text = root_name, .style = .{ .dim = true } }, .{
        .row_offset = 1,
        .col_offset = 1,
        .wrap = .none,
    });

    const available_rows = window.height -| 2;
    const visible = app.browser.visible.items;
    var row: usize = 0;
    while (row < available_rows and app.browser.scroll + row < visible.len) : (row += 1) {
        const visible_index = app.browser.scroll + row;
        const node_index = visible[visible_index];
        const node = app.browser.tree.nodes[node_index];
        const selected = visible_index == app.browser.selected;
        const indent: u16 = @intCast(@min((node.depth -| 1) * 2 + 1, window.width));
        const marker = switch (node.kind) {
            .directory => if (app.browser.expanded[node_index]) "▾ " else "▸ ",
            .file => "  ",
            .symlink => "↗ ",
            .other => "? ",
        };
        const basename = try sanitizeLine(
            allocator,
            std.fs.path.basename(node.path),
            window.width -| indent -| 2,
        );
        _ = window.print(&.{
            .{ .text = marker, .style = .{ .reverse = selected } },
            .{ .text = basename, .style = .{ .reverse = selected, .bold = selected } },
        }, .{
            .row_offset = @intCast(row + 2),
            .col_offset = indent,
            .wrap = .none,
        });
    }
}

fn drawDocument(allocator: std.mem.Allocator, window: vaxis.Window, app: *const fiew.app.App) !void {
    const snapshot = app.activeDocument() orelse {
        if (app.feedback) |name| {
            const message = try std.fmt.allocPrint(allocator, "Unable to open selected file: {s}", .{name});
            _ = window.printSegment(.{ .text = message, .style = .{ .dim = true } }, .{
                .row_offset = window.height / 2,
                .col_offset = 2,
                .wrap = .none,
            });
        } else {
            const positions = fiew.welcome.layout(window.width, window.height);
            _ = window.printSegment(.{
                .text = fiew.welcome.title,
                .style = .{ .bold = true },
            }, .{
                .row_offset = positions.title.row,
                .col_offset = positions.title.column,
                .wrap = .none,
            });
            _ = window.printSegment(.{ .text = fiew.welcome.subtitle }, .{
                .row_offset = positions.subtitle.row,
                .col_offset = positions.subtitle.column,
                .wrap = .none,
            });
        }
        return;
    };
    const safe_path = try sanitizeLine(allocator, snapshot.path, window.width -| 9);
    _ = window.print(&.{
        .{
            .text = if (app.preview != null) " Preview " else " File ",
            .style = .{ .bold = true, .reverse = app.focus == .main },
        },
        .{ .text = safe_path },
    }, .{ .wrap = .none });

    if (snapshot.encoding == .binary) {
        const metadata = try std.fmt.allocPrint(
            allocator,
            "Binary file — {d} bytes",
            .{snapshot.metadata.size},
        );
        _ = window.printSegment(.{ .text = metadata, .style = .{ .dim = true } }, .{
            .row_offset = 2,
            .col_offset = 2,
            .wrap = .none,
        });
        return;
    }

    const body_rows = window.height -| 2;
    var row: usize = 0;
    while (row < body_rows and app.document_scroll_line + row < snapshot.lineCount()) : (row += 1) {
        const line = app.document_scroll_line + row;
        var range = snapshot.lineDisplayRange(line);
        if (app.document_scroll_column > 0) {
            const grapheme_range = snapshot.graphemeRangeForLine(line);
            range.start = range.end;
            for (snapshot.graphemes[grapheme_range.start..grapheme_range.end]) |grapheme| {
                if (grapheme.display.start >= range.end) break;
                if (grapheme.visual_column + @max(grapheme.width, 1) > app.document_scroll_column) {
                    range.start = grapheme.display.start;
                    break;
                }
            }
        }
        const number = try std.fmt.allocPrint(allocator, "{d: >5} ", .{line + 1});
        const current_line = snapshot.graphemes.len != 0 and
            snapshot.graphemes[@min(app.cursor_grapheme, snapshot.graphemes.len - 1)].line == line;
        _ = window.printSegment(.{
            .text = number,
            .style = .{ .dim = !current_line, .bold = current_line },
        }, .{ .row_offset = @intCast(row + 1), .wrap = .none });

        var segments: [3]vaxis.Segment = undefined;
        var segment_count: usize = 0;
        if (current_line) {
            const selected = snapshot.graphemes[@min(app.cursor_grapheme, snapshot.graphemes.len - 1)].display;
            if (selected.start >= range.start and selected.end <= range.end) {
                if (selected.start > range.start) {
                    segments[segment_count] = .{ .text = try sanitizeLine(
                        allocator,
                        snapshot.display_bytes[range.start..selected.start],
                        window.width -| 6,
                    ) };
                    segment_count += 1;
                }
                segments[segment_count] = .{
                    .text = try sanitizeLine(
                        allocator,
                        snapshot.display_bytes[selected.start..selected.end],
                        window.width -| 6,
                    ),
                    .style = .{ .reverse = true },
                };
                segment_count += 1;
                if (selected.end < range.end) {
                    segments[segment_count] = .{ .text = try sanitizeLine(
                        allocator,
                        snapshot.display_bytes[selected.end..range.end],
                        window.width -| 6,
                    ) };
                    segment_count += 1;
                }
            }
        }
        if (segment_count == 0) {
            segments[0] = .{ .text = try sanitizeLine(
                allocator,
                snapshot.display_bytes[range.start..range.end],
                window.width -| 6,
            ) };
            segment_count = 1;
        }
        _ = window.print(segments[0..segment_count], .{
            .row_offset = @intCast(row + 1),
            .col_offset = 6,
            .wrap = .none,
        });
    }

    if (snapshot.encoding == .invalid_utf8 and window.height > 1) {
        _ = window.printSegment(.{ .text = "invalid UTF-8", .style = .{ .bold = true } }, .{
            .row_offset = 0,
            .col_offset = window.width -| 13,
            .wrap = .none,
        });
    }
}

fn drawStatus(allocator: std.mem.Allocator, window: vaxis.Window, app: *const fiew.app.App) !void {
    const selection = app.selection();
    const text = try std.fmt.allocPrint(
        allocator,
        " NORMAL  {s}  bytes {d}..{d} col {d}   Tab focus · b sidebar · Enter pin · q quit",
        .{ @tagName(app.focus), selection.start, selection.end, app.document_scroll_column },
    );
    _ = window.printSegment(.{ .text = text, .style = .{ .reverse = true } }, .{ .wrap = .none });
}

fn sanitizeLine(allocator: std.mem.Allocator, text: []const u8, max_columns: u16) ![]u8 {
    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(allocator);
    var index: usize = 0;
    var columns: usize = 0;
    while (index < text.len and columns < max_columns) {
        const length = std.unicode.utf8ByteSequenceLength(text[index]) catch 1;
        if (length == 1 and (text[index] < 0x20 or text[index] == 0x7f)) {
            if (text[index] == '\t') {
                const spaces = @min(@as(usize, 4), max_columns - columns);
                try result.appendNTimes(allocator, ' ', spaces);
                columns += spaces;
            } else {
                try result.appendSlice(allocator, "\u{fffd}");
                columns += 1;
            }
            index += 1;
            continue;
        }
        try result.appendSlice(allocator, text[index .. index + length]);
        index += length;
        columns += 1;
    }
    return result.toOwnedSlice(allocator);
}

fn nextGrapheme(_: ?*const anyopaque, text: []const u8, start: usize) usize {
    var iterator = vaxis.unicode.graphemeIterator(text[start..]);
    const grapheme = iterator.next() orelse return text.len;
    return start + grapheme.len;
}

fn graphemeWidth(_: ?*const anyopaque, grapheme: []const u8) u16 {
    return vaxis.gwidth.gwidth(grapheme, .unicode);
}

test "terminal text sanitization cannot emit control sequences" {
    const sanitized = try sanitizeLine(std.testing.allocator, "ok\x1b[31m\tend", 80);
    defer std.testing.allocator.free(sanitized);
    try std.testing.expect(std.mem.indexOfScalar(u8, sanitized, 0x1b) == null);
    try std.testing.expectEqualStrings("ok\u{fffd}[31m    end", sanitized);
}

test "Unicode grapheme segmentation preserves source byte ranges" {
    var snapshot = try fiew.document.Snapshot.init(
        std.testing.allocator,
        "unicode.txt",
        "a\u{301}👩‍💻x",
        1,
        .{ .size = 15 },
        .{ .next_fn = nextGrapheme, .width_fn = graphemeWidth },
    );
    defer snapshot.deinit();

    try std.testing.expectEqual(@as(usize, 3), snapshot.graphemes.len);
    try std.testing.expectEqual(
        fiew.document.ByteRange{ .start = 0, .end = 3 },
        snapshot.graphemes[0].source,
    );
    try std.testing.expectEqual(
        fiew.document.ByteRange{ .start = 3, .end = 14 },
        snapshot.graphemes[1].source,
    );
    try std.testing.expectEqual(@as(u16, 2), snapshot.graphemes[1].width);
}
