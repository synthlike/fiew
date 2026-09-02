//! Direct Tree-sitter adapter for Markdown block and inline structure. The
//! adapter owns all C values and flattens both parse trees, plus one level of
//! explicitly labelled Zig fence injection, into Skaut-owned syntax data.

const std = @import("std");
const ts = @import("c.zig");
const c = ts.c;
const document = @import("../../model/document.zig");
const syntax = @import("../../model/syntax.zig");
const zig_syntax = @import("zig_syntax.zig");

pub const max_parse_bytes = zig_syntax.max_parse_bytes;
pub const CancelContext = zig_syntax.CancelContext;

pub const Error = error{ UnsupportedAbi, QueryCompilationFailed, OutOfMemory };

const block_highlights =
    \\(atx_heading) @label
    \\(setext_heading) @label
    \\[(atx_h1_marker) (atx_h2_marker) (atx_h3_marker) (atx_h4_marker) (atx_h5_marker) (atx_h6_marker)
    \\ (setext_h1_underline) (setext_h2_underline) (fenced_code_block_delimiter)
    \\ (list_marker_plus) (list_marker_minus) (list_marker_star) (list_marker_dot)
    \\ (list_marker_parenthesis) (block_quote_marker)] @punctuation
    \\[(link_title) (indented_code_block) (fenced_code_block)] @string
    \\(link_destination) @string
    \\(backslash_escape) @string
;

const inline_highlights =
    \\[(code_span) (link_title)] @string
    \\[(emphasis_delimiter) (code_span_delimiter)] @punctuation
    \\[(link_destination) (uri_autolink)] @string
    \\[(link_label) (link_text) (image_description)] @label
    \\[(backslash_escape) (hard_line_break)] @string
;

/// Project-owned folds: sections retain their heading line and fenced blocks
/// retain their opening delimiter line.
const fold_query_source =
    \\[(section) (fenced_code_block)] @fold
;

pub fn abiSupported() bool {
    return supported(ts.tree_sitter_markdown()) and supported(ts.tree_sitter_markdown_inline());
}

fn supported(language: *const c.TSLanguage) bool {
    const version = c.ts_language_abi_version(language);
    return version >= zig_syntax.min_abi and version <= zig_syntax.max_abi;
}

pub const Engine = struct {
    allocator: std.mem.Allocator,
    block_parser: *c.TSParser,
    inline_parser: *c.TSParser,
    block_query: *c.TSQuery,
    inline_query: *c.TSQuery,
    fold_query: *c.TSQuery,
    block_kinds: []const ?syntax.HighlightKind,
    inline_kinds: []const ?syntax.HighlightKind,
    zig_engine: zig_syntax.Engine,

    pub fn init(allocator: std.mem.Allocator) Error!Engine {
        const block_language = ts.tree_sitter_markdown();
        const inline_language = ts.tree_sitter_markdown_inline();
        if (!supported(block_language) or !supported(inline_language)) return error.UnsupportedAbi;

        const block_parser = try newParser(block_language);
        errdefer c.ts_parser_delete(block_parser);
        const inline_parser = try newParser(inline_language);
        errdefer c.ts_parser_delete(inline_parser);
        const block_query = try compileQuery(block_language, block_highlights);
        errdefer c.ts_query_delete(block_query);
        const inline_query = try compileQuery(inline_language, inline_highlights);
        errdefer c.ts_query_delete(inline_query);
        const fold_query = try compileQuery(block_language, fold_query_source);
        errdefer c.ts_query_delete(fold_query);
        const block_kinds = try captureKinds(allocator, block_query);
        errdefer allocator.free(block_kinds);
        const inline_kinds = try captureKinds(allocator, inline_query);
        errdefer allocator.free(inline_kinds);
        const zig_engine = zig_syntax.Engine.init(allocator) catch |err| return switch (err) {
            error.UnsupportedAbi => error.UnsupportedAbi,
            error.QueryCompilationFailed => error.QueryCompilationFailed,
            error.OutOfMemory => error.OutOfMemory,
        };

        return .{
            .allocator = allocator,
            .block_parser = block_parser,
            .inline_parser = inline_parser,
            .block_query = block_query,
            .inline_query = inline_query,
            .fold_query = fold_query,
            .block_kinds = block_kinds,
            .inline_kinds = inline_kinds,
            .zig_engine = zig_engine,
        };
    }

    pub fn deinit(self: *Engine) void {
        self.zig_engine.deinit();
        self.allocator.free(self.inline_kinds);
        self.allocator.free(self.block_kinds);
        c.ts_query_delete(self.fold_query);
        c.ts_query_delete(self.inline_query);
        c.ts_query_delete(self.block_query);
        c.ts_parser_delete(self.inline_parser);
        c.ts_parser_delete(self.block_parser);
        self.* = undefined;
    }

    /// Return null for every fallback case. Markdown with syntax errors remains
    /// available as complete plain text rather than exposing partial structure.
    pub fn analyze(self: *Engine, allocator: std.mem.Allocator, source: []const u8, cancel: ?*CancelContext) ?syntax.ParseData {
        if (source.len == 0 or source.len > max_parse_bytes or !std.unicode.utf8ValidateSlice(source)) return null;
        const block_tree = parse(self.block_parser, source, cancel) orelse return null;
        defer c.ts_tree_delete(block_tree);
        const block_root = c.ts_tree_root_node(block_tree);
        if (c.ts_node_has_error(block_root) or cancelled(cancel)) return null;

        var inline_ranges: std.ArrayList(c.TSRange) = .empty;
        defer inline_ranges.deinit(allocator);
        collectRanges(allocator, block_root, "inline", &inline_ranges) catch return null;

        var spans: std.ArrayList(syntax.HighlightSpan) = .empty;
        defer spans.deinit(allocator);
        appendHighlights(allocator, block_tree, self.block_query, self.block_kinds, &spans) catch return null;

        var inline_tree: ?*c.TSTree = null;
        defer if (inline_tree) |tree| c.ts_tree_delete(tree);
        if (inline_ranges.items.len != 0) {
            if (!c.ts_parser_set_included_ranges(self.inline_parser, inline_ranges.items.ptr, @intCast(inline_ranges.items.len))) return null;
            defer _ = c.ts_parser_set_included_ranges(self.inline_parser, null, 0);
            inline_tree = parse(self.inline_parser, source, cancel) orelse return null;
            if (c.ts_node_has_error(c.ts_tree_root_node(inline_tree.?)) or cancelled(cancel)) return null;
            appendHighlights(allocator, inline_tree.?, self.inline_query, self.inline_kinds, &spans) catch return null;
        }

        var folds: std.ArrayList(syntax.FoldRange) = .empty;
        defer folds.deinit(allocator);
        appendFolds(allocator, block_tree, self.fold_query, &folds) catch return null;

        var outline_nodes: std.ArrayList(syntax.OutlineNode) = .empty;
        defer outline_nodes.deinit(allocator);
        appendTree(allocator, block_root, null, &outline_nodes) catch return null;
        if (inline_tree) |tree| appendInlineStructure(allocator, c.ts_tree_root_node(tree), &outline_nodes) catch return null;

        // Injected Zig values are offset back into the immutable Markdown
        // snapshot and attached below the containing fence structure.
        appendZigFences(self, allocator, block_root, source, cancel, &spans, &folds, &outline_nodes) catch return null;
        if (cancelled(cancel)) return null;

        std.mem.sort(syntax.HighlightSpan, spans.items, {}, syntax.lessSpecificFirst);
        std.mem.sort(syntax.FoldRange, folds.items, {}, foldBeforeFold);
        var outline: syntax.Outline = .{
            .allocator = allocator,
            .nodes = outline_nodes.toOwnedSlice(allocator) catch return null,
        };
        errdefer outline.deinit();
        const owned_spans = spans.toOwnedSlice(allocator) catch return null;
        errdefer allocator.free(owned_spans);
        const owned_folds = folds.toOwnedSlice(allocator) catch return null;
        errdefer allocator.free(owned_folds);
        return .{
            .allocator = allocator,
            .highlights = owned_spans,
            .folds = owned_folds,
            .outline = outline,
        };
    }
};

fn newParser(language: *const c.TSLanguage) Error!*c.TSParser {
    const parser = c.ts_parser_new() orelse return error.OutOfMemory;
    errdefer c.ts_parser_delete(parser);
    if (!c.ts_parser_set_language(parser, language)) return error.UnsupportedAbi;
    return parser;
}

fn parse(parser: *c.TSParser, source: []const u8, cancel: ?*CancelContext) ?*c.TSTree {
    var reader: SliceReader = .{ .source = source };
    const input: c.TSInput = .{ .payload = &reader, .read = SliceReader.read, .encoding = c.TSInputEncodingUTF8, .decode = null };
    const options: c.TSParseOptions = .{
        .payload = if (cancel) |ctx| ctx else null,
        .progress_callback = if (cancel != null) progressCallback else null,
    };
    const tree = c.ts_parser_parse_with_options(parser, null, input, options);
    if (tree == null) c.ts_parser_reset(parser);
    return tree;
}

fn collectRanges(allocator: std.mem.Allocator, node: c.TSNode, kind: []const u8, ranges: *std.ArrayList(c.TSRange)) !void {
    if (std.mem.eql(u8, std.mem.span(c.ts_node_type(node)), kind)) {
        try ranges.append(allocator, .{
            .start_point = c.ts_node_start_point(node),
            .end_point = c.ts_node_end_point(node),
            .start_byte = c.ts_node_start_byte(node),
            .end_byte = c.ts_node_end_byte(node),
        });
        return;
    }
    var index: u32 = 0;
    while (index < c.ts_node_named_child_count(node)) : (index += 1)
        try collectRanges(allocator, c.ts_node_named_child(node, index), kind, ranges);
}

fn appendHighlights(allocator: std.mem.Allocator, tree: *c.TSTree, query: *c.TSQuery, kinds: []const ?syntax.HighlightKind, spans: *std.ArrayList(syntax.HighlightSpan)) !void {
    const cursor = c.ts_query_cursor_new() orelse return error.OutOfMemory;
    defer c.ts_query_cursor_delete(cursor);
    c.ts_query_cursor_exec(cursor, query, c.ts_tree_root_node(tree));
    var match: c.TSQueryMatch = undefined;
    while (c.ts_query_cursor_next_match(cursor, &match)) {
        for (match.captures[0..match.capture_count]) |capture| {
            const kind = kinds[capture.index] orelse continue;
            try spans.append(allocator, .{ .source = .{
                .start = c.ts_node_start_byte(capture.node),
                .end = c.ts_node_end_byte(capture.node),
            }, .kind = kind });
        }
    }
}

fn appendFolds(allocator: std.mem.Allocator, tree: *c.TSTree, query: *c.TSQuery, folds: *std.ArrayList(syntax.FoldRange)) !void {
    const cursor = c.ts_query_cursor_new() orelse return error.OutOfMemory;
    defer c.ts_query_cursor_delete(cursor);
    c.ts_query_cursor_exec(cursor, query, c.ts_tree_root_node(tree));
    var match: c.TSQueryMatch = undefined;
    while (c.ts_query_cursor_next_match(cursor, &match)) {
        for (match.captures[0..match.capture_count]) |capture| {
            const fold: syntax.FoldRange = .{
                .start_line = c.ts_node_start_point(capture.node).row,
                .end_line = c.ts_node_end_point(capture.node).row,
            };
            if (fold.isFoldable()) try folds.append(allocator, fold);
        }
    }
}

fn appendZigFences(self: *Engine, allocator: std.mem.Allocator, node: c.TSNode, source: []const u8, cancel: ?*CancelContext, spans: *std.ArrayList(syntax.HighlightSpan), folds: *std.ArrayList(syntax.FoldRange), outline_nodes: *std.ArrayList(syntax.OutlineNode)) !void {
    if (std.mem.eql(u8, std.mem.span(c.ts_node_type(node)), "fenced_code_block")) {
        const language = findDescendant(node, "language");
        const content = findDescendant(node, "code_fence_content");
        if (language != null and content != null) {
            const language_bytes = source[c.ts_node_start_byte(language.?)..c.ts_node_end_byte(language.?)];
            if (std.mem.eql(u8, std.mem.trim(u8, language_bytes, " \t\r\n"), "zig")) {
                const content_node = content.?;
                const start_byte: usize = c.ts_node_start_byte(content_node);
                const end_byte: usize = c.ts_node_end_byte(content_node);
                var tree = self.zig_engine.parse(source[start_byte..end_byte], cancel) orelse return;
                defer tree.deinit();
                var data = try self.zig_engine.analyze(allocator, &tree);
                defer data.deinit();
                const start_line: usize = c.ts_node_start_point(content_node).row;
                for (data.highlights) |span| try spans.append(allocator, .{
                    .source = .{ .start = start_byte + span.source.start, .end = start_byte + span.source.end },
                    .kind = span.kind,
                });
                for (data.folds) |fold| try folds.append(allocator, .{
                    .start_line = start_line + fold.start_line,
                    .end_line = start_line + fold.end_line,
                });
                const base = outline_nodes.items.len;
                const container = deepestContainer(outline_nodes.items, .{ .start = start_byte, .end = end_byte });
                for (data.outline.nodes) |outline_node| try outline_nodes.append(allocator, .{
                    .source = .{
                        .start = start_byte + outline_node.source.start,
                        .end = start_byte + outline_node.source.end,
                    },
                    .start_line = start_line + outline_node.start_line,
                    .end_line = start_line + outline_node.end_line,
                    .parent = if (outline_node.parent) |parent| base + parent else container,
                });
            }
        }
        return; // Never recurse into a fence: injection depth is exactly one.
    }
    var index: u32 = 0;
    while (index < c.ts_node_named_child_count(node)) : (index += 1)
        try appendZigFences(self, allocator, c.ts_node_named_child(node, index), source, cancel, spans, folds, outline_nodes);
}

fn findDescendant(node: c.TSNode, kind: []const u8) ?c.TSNode {
    if (std.mem.eql(u8, std.mem.span(c.ts_node_type(node)), kind)) return node;
    var index: u32 = 0;
    while (index < c.ts_node_named_child_count(node)) : (index += 1)
        if (findDescendant(c.ts_node_named_child(node, index), kind)) |found| return found;
    return null;
}

fn appendTree(allocator: std.mem.Allocator, root: c.TSNode, parent: ?usize, nodes: *std.ArrayList(syntax.OutlineNode)) !void {
    const Frame = struct { node: c.TSNode, parent: ?usize };
    var stack: std.ArrayList(Frame) = .empty;
    defer stack.deinit(allocator);
    try stack.append(allocator, .{ .node = root, .parent = parent });
    while (stack.pop()) |frame| {
        const index = nodes.items.len;
        try nodes.append(allocator, .{
            .source = .{ .start = c.ts_node_start_byte(frame.node), .end = c.ts_node_end_byte(frame.node) },
            .start_line = c.ts_node_start_point(frame.node).row,
            .end_line = c.ts_node_end_point(frame.node).row,
            .parent = frame.parent,
        });
        var child_index = c.ts_node_named_child_count(frame.node);
        while (child_index > 0) {
            child_index -= 1;
            try stack.append(allocator, .{ .node = c.ts_node_named_child(frame.node, child_index), .parent = index });
        }
    }
}

fn appendInlineStructure(allocator: std.mem.Allocator, root: c.TSNode, nodes: *std.ArrayList(syntax.OutlineNode)) !void {
    var index: u32 = 0;
    while (index < c.ts_node_named_child_count(root)) : (index += 1) {
        const child = c.ts_node_named_child(root, index);
        const range: document.ByteRange = .{ .start = c.ts_node_start_byte(child), .end = c.ts_node_end_byte(child) };
        try appendTree(allocator, child, deepestContainer(nodes.items, range), nodes);
    }
}

fn deepestContainer(nodes: []const syntax.OutlineNode, range: document.ByteRange) ?usize {
    var best: ?usize = null;
    var best_span: usize = std.math.maxInt(usize);
    for (nodes, 0..) |node, index| {
        if (node.source.start <= range.start and node.source.end >= range.end) {
            const span = node.source.end - node.source.start;
            if (span < best_span) {
                best = index;
                best_span = span;
            }
        }
    }
    return best;
}

fn compileQuery(language: *const c.TSLanguage, source: []const u8) Error!*c.TSQuery {
    var offset: u32 = 0;
    var kind: c.TSQueryError = c.TSQueryErrorNone;
    return c.ts_query_new(language, source.ptr, @intCast(source.len), &offset, &kind) orelse error.QueryCompilationFailed;
}

fn captureKinds(allocator: std.mem.Allocator, query: *c.TSQuery) ![]const ?syntax.HighlightKind {
    const count = c.ts_query_capture_count(query);
    const kinds = try allocator.alloc(?syntax.HighlightKind, count);
    var index: u32 = 0;
    while (index < count) : (index += 1) {
        var length: u32 = 0;
        const name = c.ts_query_capture_name_for_id(query, index, &length);
        kinds[index] = syntax.HighlightKind.fromCapture(name[0..length]);
    }
    return kinds;
}

fn foldBeforeFold(_: void, a: syntax.FoldRange, b: syntax.FoldRange) bool {
    if (a.start_line != b.start_line) return a.start_line < b.start_line;
    return a.end_line < b.end_line;
}

fn cancelled(context: ?*CancelContext) bool {
    if (context) |value| if (value.flag) |flag| return flag.load(.acquire);
    return false;
}

const SliceReader = struct {
    source: []const u8,
    fn read(payload: ?*anyopaque, byte_index: u32, _: c.TSPoint, bytes_read: [*c]u32) callconv(.c) [*c]const u8 {
        const self: *SliceReader = @ptrCast(@alignCast(payload));
        if (byte_index >= self.source.len) {
            bytes_read.* = 0;
            return null;
        }
        bytes_read.* = @intCast(self.source.len - byte_index);
        return self.source.ptr + byte_index;
    }
};

fn progressCallback(state: [*c]c.TSParseState) callconv(.c) bool {
    const context: *CancelContext = @ptrCast(@alignCast(state.*.payload));
    return cancelled(context);
}

const testing = std.testing;
const sample =
    \\# Heading with *emphasis*
    \\
    \\Paragraph with [a link](https://example.com).
    \\
    \\## Child
    \\
    \\```zig
    \\const answer: u32 = 42;
    \\```
    \\
;

test "Markdown block and inline structure produces highlights and folds" {
    var engine = try Engine.init(testing.allocator);
    defer engine.deinit();
    var data = engine.analyze(testing.allocator, sample, null) orelse return error.ParseFailed;
    defer data.deinit();
    try testing.expect(data.highlights.len != 0);
    try testing.expect(data.folds.len >= 2);
    try testing.expect(data.outline.nodes.len > 4);
    const emphasis_offset = std.mem.indexOf(u8, sample, "emphasis").?;
    const inline_node = data.outline.enclosing(.{ .start = emphasis_offset, .end = emphasis_offset + 1 }) orelse return error.NoInlineStructure;
    try testing.expect(data.outline.nodes[inline_node].source.end - data.outline.nodes[inline_node].source.start < sample.len);
    const zig_offset = std.mem.indexOf(u8, sample, "answer").?;
    const zig_node = data.outline.enclosing(.{ .start = zig_offset, .end = zig_offset + 1 }) orelse return error.NoZigStructure;
    try testing.expect(data.outline.nodes[zig_node].source.end - data.outline.nodes[zig_node].source.start <= "answer".len);
    var has_number = false;
    for (data.highlights) |span| if (span.kind == .number) {
        has_number = true;
        break;
    };
    try testing.expect(has_number); // Zig fence injection.
}

test "block inline ranges preserve original byte and point mappings" {
    const source = "# Heading *one*\n\nParagraph [two](target).\n";
    var engine = try Engine.init(testing.allocator);
    defer engine.deinit();
    const tree = parse(engine.block_parser, source, null) orelse return error.ParseFailed;
    defer c.ts_tree_delete(tree);
    var ranges: std.ArrayList(c.TSRange) = .empty;
    defer ranges.deinit(testing.allocator);
    try collectRanges(testing.allocator, c.ts_tree_root_node(tree), "inline", &ranges);
    try testing.expectEqual(@as(usize, 2), ranges.items.len);
    try testing.expectEqualStrings("Heading *one*", source[ranges.items[0].start_byte..ranges.items[0].end_byte]);
    try testing.expectEqualStrings("Paragraph [two](target).", source[ranges.items[1].start_byte..ranges.items[1].end_byte]);
    try testing.expectEqual(@as(u32, 0), ranges.items[0].start_point.row);
    try testing.expectEqual(@as(u32, 2), ranges.items[1].start_point.row);
}

test "invalid project query is rejected without exposing a C value" {
    try testing.expectError(error.QueryCompilationFailed, compileQuery(ts.tree_sitter_markdown(), "(not_a_markdown_node) @label"));
}

test "only explicitly labelled Zig fences are injected" {
    const source = "```zig\nconst n = 1;\n```\n\n```rust\nconst n = 2;\n```\n";
    var engine = try Engine.init(testing.allocator);
    defer engine.deinit();
    var data = engine.analyze(testing.allocator, source, null) orelse return error.ParseFailed;
    defer data.deinit();
    var numbers: usize = 0;
    for (data.highlights) |span| {
        if (span.kind == .number) numbers += 1;
    }
    try testing.expectEqual(@as(usize, 1), numbers);
}

test "fallback rejects malformed, invalid UTF-8, oversized, and cancelled input" {
    var engine = try Engine.init(testing.allocator);
    defer engine.deinit();
    try testing.expect(engine.analyze(testing.allocator, "# malformed \x00 Markdown", null) == null);
    try testing.expect(engine.analyze(testing.allocator, "bad\xff", null) == null);
    const big = try testing.allocator.alloc(u8, max_parse_bytes + 1);
    defer testing.allocator.free(big);
    @memset(big, 'a');
    try testing.expect(engine.analyze(testing.allocator, big, null) == null);
    var flag: std.atomic.Value(bool) = .init(true);
    var context: CancelContext = .{ .flag = &flag };
    try testing.expect(engine.analyze(testing.allocator, sample, &context) == null);
}
