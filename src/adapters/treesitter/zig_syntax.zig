//! Direct Tree-sitter adapter for Zig. Owns every C lifetime (parser, tree,
//! queries, cursors) and returns only Skaut-owned syntax values. Parsing is
//! cancellable and never runs during cell rendering; callers invoke it from
//! parse jobs and read the resulting immutable snapshot while drawing.

const std = @import("std");
const ts = @import("c.zig");
const c = ts.c;
const document = @import("../../model/document.zig");
const syntax = @import("../../model/syntax.zig");

/// Grammar ABI range this build accepts, taken from the vendored core headers.
pub const min_abi: u32 = c.TREE_SITTER_MIN_COMPATIBLE_LANGUAGE_VERSION;
pub const max_abi: u32 = c.TREE_SITTER_LANGUAGE_VERSION;

/// Files at or above this size stay plain text and are never parsed.
pub const max_parse_bytes: usize = 2 << 20;

pub const Error = error{
    UnsupportedAbi,
    QueryCompilationFailed,
    OutOfMemory,
};

/// Cooperative cancellation for a parse job. The C progress callback polls
/// `flag`; a parse job flips it from a deadline timer or on supersession.
pub const CancelContext = struct {
    flag: ?*std.atomic.Value(bool) = null,

    fn cancelled(self: *const CancelContext) bool {
        if (self.flag) |flag| return flag.load(.acquire);
        return false;
    }
};

/// Skaut-owned highlight query. Predicate-free by design: the C query API does
/// not evaluate the grammar's `#lua-match?` predicates, so naming-convention
/// captures are omitted in favor of node-type and token captures that are
/// correct by construction. Every token below is drawn from the grammar's own
/// highlights query, so the query compiles against this ABI.
const highlight_query_source =
    \\(comment) @comment
    \\(string) @string
    \\(multiline_string) @string
    \\(character) @string
    \\(escape_sequence) @string
    \\(integer) @number
    \\(float) @number
    \\(boolean) @constant
    \\(builtin_type) @type
    \\(builtin_identifier) @function
    \\(function_declaration name: (identifier) @function)
    \\(call_expression function: (identifier) @function)
    \\(block_label (identifier) @label)
    \\["null" "unreachable" "undefined"] @constant
    \\[
    \\  "asm" "defer" "errdefer" "test" "error" "const" "var"
    \\  "struct" "union" "enum" "opaque"
    \\  "async" "await" "suspend" "nosuspend" "resume"
    \\  "fn" "and" "or" "orelse" "return"
    \\  "if" "else" "switch" "for" "while" "break" "continue"
    \\  "usingnamespace" "export" "try" "catch"
    \\  "volatile" "allowzero" "noalias" "addrspace" "align" "callconv"
    \\  "linksection" "pub" "inline" "noinline" "extern" "comptime"
    \\  "packed" "threadlocal"
    \\] @keyword
    \\[
    \\  "[" "]" "(" ")" "{" "}"
    \\] @punctuation
    \\[
    \\  ";" "." "," ":" "=>" "->"
    \\] @punctuation
;

/// The grammar's own fold query (a plain node list, no predicates), registered
/// as a named import in build.zig because it lives outside src/.
const fold_query_source = @embedFile("zig_fold_query");

pub fn abiSupported() bool {
    const version = c.ts_language_abi_version(ts.tree_sitter_zig());
    return version >= min_abi and version <= max_abi;
}

/// Reusable per-thread syntax engine. One engine owns one parser and the
/// compiled queries; a parse job holds an engine for the life of the job.
pub const Engine = struct {
    allocator: std.mem.Allocator,
    parser: *c.TSParser,
    highlight_query: *c.TSQuery,
    fold_query: *c.TSQuery,
    highlight_kinds: []const ?syntax.HighlightKind,

    pub fn init(allocator: std.mem.Allocator) Error!Engine {
        const language = ts.tree_sitter_zig();
        const version = c.ts_language_abi_version(language);
        if (version < min_abi or version > max_abi) return error.UnsupportedAbi;

        const parser = c.ts_parser_new() orelse return error.OutOfMemory;
        errdefer c.ts_parser_delete(parser);
        if (!c.ts_parser_set_language(parser, language)) return error.UnsupportedAbi;

        const highlight_query = try compileQuery(language, highlight_query_source);
        errdefer c.ts_query_delete(highlight_query);
        const fold_query = try compileQuery(language, fold_query_source);
        errdefer c.ts_query_delete(fold_query);

        const capture_count = c.ts_query_capture_count(highlight_query);
        const kinds = try allocator.alloc(?syntax.HighlightKind, capture_count);
        errdefer allocator.free(kinds);
        var index: u32 = 0;
        while (index < capture_count) : (index += 1) {
            var length: u32 = 0;
            const name = c.ts_query_capture_name_for_id(highlight_query, index, &length);
            kinds[index] = syntax.HighlightKind.fromCapture(name[0..length]);
        }

        return .{
            .allocator = allocator,
            .parser = parser,
            .highlight_query = highlight_query,
            .fold_query = fold_query,
            .highlight_kinds = kinds,
        };
    }

    pub fn deinit(self: *Engine) void {
        self.allocator.free(self.highlight_kinds);
        c.ts_query_delete(self.fold_query);
        c.ts_query_delete(self.highlight_query);
        c.ts_parser_delete(self.parser);
        self.* = undefined;
    }

    /// Parse `source`, returning an owned tree or null when cancelled. `source`
    /// must outlive the returned tree. Returns null immediately for oversized
    /// input so the caller keeps the plain-text fallback.
    pub fn parse(self: *Engine, source: []const u8, cancel: ?*CancelContext) ?Tree {
        if (source.len > max_parse_bytes) return null;

        var reader: SliceReader = .{ .source = source };
        const input: c.TSInput = .{
            .payload = &reader,
            .read = SliceReader.read,
            .encoding = c.TSInputEncodingUTF8,
            .decode = null,
        };
        const options: c.TSParseOptions = .{
            .payload = if (cancel) |ctx| ctx else null,
            .progress_callback = if (cancel != null) progressCallback else null,
        };
        const tree = c.ts_parser_parse_with_options(self.parser, null, input, options);
        if (tree == null) {
            c.ts_parser_reset(self.parser);
            return null;
        }
        return .{ .tree = tree.?, .source = source };
    }

    /// Highlight spans intersecting `range` (a viewport plus overscan window),
    /// ordered so more specific spans paint last.
    pub fn highlights(
        self: *Engine,
        allocator: std.mem.Allocator,
        tree: *const Tree,
        range: document.ByteRange,
    ) ![]syntax.HighlightSpan {
        const cursor = c.ts_query_cursor_new() orelse return error.OutOfMemory;
        defer c.ts_query_cursor_delete(cursor);
        _ = c.ts_query_cursor_set_byte_range(cursor, @intCast(range.start), @intCast(range.end));
        c.ts_query_cursor_exec(cursor, self.highlight_query, c.ts_tree_root_node(tree.tree));

        var spans: std.ArrayList(syntax.HighlightSpan) = .empty;
        defer spans.deinit(allocator);
        var match: c.TSQueryMatch = undefined;
        while (c.ts_query_cursor_next_match(cursor, &match)) {
            for (match.captures[0..match.capture_count]) |capture| {
                const kind = self.highlight_kinds[capture.index] orelse continue;
                try spans.append(allocator, .{
                    .source = .{
                        .start = c.ts_node_start_byte(capture.node),
                        .end = c.ts_node_end_byte(capture.node),
                    },
                    .kind = kind,
                });
            }
        }
        std.mem.sort(syntax.HighlightSpan, spans.items, {}, syntax.lessSpecificFirst);
        return spans.toOwnedSlice(allocator);
    }

    /// All foldable regions in the tree, in document order.
    pub fn folds(
        self: *Engine,
        allocator: std.mem.Allocator,
        tree: *const Tree,
    ) ![]syntax.FoldRange {
        const cursor = c.ts_query_cursor_new() orelse return error.OutOfMemory;
        defer c.ts_query_cursor_delete(cursor);
        c.ts_query_cursor_exec(cursor, self.fold_query, c.ts_tree_root_node(tree.tree));

        var ranges: std.ArrayList(syntax.FoldRange) = .empty;
        defer ranges.deinit(allocator);
        var match: c.TSQueryMatch = undefined;
        while (c.ts_query_cursor_next_match(cursor, &match)) {
            for (match.captures[0..match.capture_count]) |capture| {
                const start = c.ts_node_start_point(capture.node).row;
                const end = c.ts_node_end_point(capture.node).row;
                const fold: syntax.FoldRange = .{ .start_line = start, .end_line = end };
                if (fold.isFoldable()) try ranges.append(allocator, fold);
            }
        }
        std.mem.sort(syntax.FoldRange, ranges.items, {}, foldBeforeFold);
        return ranges.toOwnedSlice(allocator);
    }

    /// Produce the complete Skaut-owned analysis of a parsed document: highlight
    /// spans over the whole document, fold ranges, and the structural outline.
    /// Highlighting the full (<= 2 MiB) document trivially covers any viewport.
    pub fn analyze(
        self: *Engine,
        allocator: std.mem.Allocator,
        tree: *const Tree,
    ) !syntax.ParseData {
        const spans = try self.highlights(allocator, tree, .{ .start = 0, .end = tree.source.len });
        errdefer allocator.free(spans);
        const fold_ranges = try self.folds(allocator, tree);
        errdefer allocator.free(fold_ranges);
        const outline = try buildOutline(allocator, tree);
        return .{
            .allocator = allocator,
            .highlights = spans,
            .folds = fold_ranges,
            .outline = outline,
        };
    }

    /// Walk the named nodes into a pre-order outline with parent indices.
    fn buildOutline(allocator: std.mem.Allocator, tree: *const Tree) !syntax.Outline {
        const Frame = struct { node: c.TSNode, parent: ?usize };
        var nodes: std.ArrayList(syntax.OutlineNode) = .empty;
        errdefer nodes.deinit(allocator);
        var stack: std.ArrayList(Frame) = .empty;
        defer stack.deinit(allocator);

        try stack.append(allocator, .{ .node = c.ts_tree_root_node(tree.tree), .parent = null });
        while (stack.pop()) |frame| {
            const index = nodes.items.len;
            try nodes.append(allocator, .{
                .source = .{
                    .start = c.ts_node_start_byte(frame.node),
                    .end = c.ts_node_end_byte(frame.node),
                },
                .start_line = c.ts_node_start_point(frame.node).row,
                .end_line = c.ts_node_end_point(frame.node).row,
                .parent = frame.parent,
            });
            // Push children in reverse so they emit in source order (pre-order).
            var child_index = c.ts_node_named_child_count(frame.node);
            while (child_index > 0) {
                child_index -= 1;
                try stack.append(allocator, .{
                    .node = c.ts_node_named_child(frame.node, child_index),
                    .parent = index,
                });
            }
        }
        return .{ .allocator = allocator, .nodes = try nodes.toOwnedSlice(allocator) };
    }

    fn compileQuery(language: *const c.TSLanguage, source: []const u8) Error!*c.TSQuery {
        var error_offset: u32 = 0;
        var error_type: c.TSQueryError = c.TSQueryErrorNone;
        const query = c.ts_query_new(
            language,
            source.ptr,
            @intCast(source.len),
            &error_offset,
            &error_type,
        );
        return query orelse error.QueryCompilationFailed;
    }
};

fn foldBeforeFold(_: void, a: syntax.FoldRange, b: syntax.FoldRange) bool {
    if (a.start_line != b.start_line) return a.start_line < b.start_line;
    return a.end_line < b.end_line;
}

/// An owned parse tree over borrowed source bytes.
pub const Tree = struct {
    tree: *c.TSTree,
    source: []const u8,

    pub fn deinit(self: *Tree) void {
        c.ts_tree_delete(self.tree);
        self.* = undefined;
    }

    pub fn rootKind(self: *const Tree) []const u8 {
        return std.mem.span(c.ts_node_type(c.ts_tree_root_node(self.tree)));
    }

    pub fn hasError(self: *const Tree) bool {
        return c.ts_node_has_error(c.ts_tree_root_node(self.tree));
    }
};

const SliceReader = struct {
    source: []const u8,

    fn read(
        payload: ?*anyopaque,
        byte_index: u32,
        _: c.TSPoint,
        bytes_read: [*c]u32,
    ) callconv(.c) [*c]const u8 {
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
    const ctx: *CancelContext = @ptrCast(@alignCast(state.*.payload));
    return ctx.cancelled();
}

// --- Tests ---------------------------------------------------------------

const testing = std.testing;

const sample_source =
    \\const std = @import("std");
    \\// a greeting program
    \\pub fn main() void {
    \\    const message = "hello";
    \\    const count = 42;
    \\    _ = message;
    \\    _ = count;
    \\}
    \\
;

fn hasKind(spans: []const syntax.HighlightSpan, kind: syntax.HighlightKind) bool {
    for (spans) |span| if (span.kind == kind) return true;
    return false;
}

test "adapter reports a supported grammar ABI" {
    try testing.expect(abiSupported());
    try testing.expect(min_abi <= max_abi);
}

test "valid Zig parses without error and yields a root node" {
    var engine = try Engine.init(testing.allocator);
    defer engine.deinit();
    var tree = engine.parse(sample_source, null) orelse return error.ParseFailed;
    defer tree.deinit();
    try testing.expect(tree.rootKind().len != 0);
    try testing.expect(!tree.hasError());
}

test "highlights cover keywords, strings, numbers, and comments" {
    var engine = try Engine.init(testing.allocator);
    defer engine.deinit();
    var tree = engine.parse(sample_source, null) orelse return error.ParseFailed;
    defer tree.deinit();

    const spans = try engine.highlights(testing.allocator, &tree, .{ .start = 0, .end = sample_source.len });
    defer testing.allocator.free(spans);

    try testing.expect(hasKind(spans, .keyword));
    try testing.expect(hasKind(spans, .string));
    try testing.expect(hasKind(spans, .number));
    try testing.expect(hasKind(spans, .comment));
    try testing.expect(hasKind(spans, .function));

    // Spans are ordered so more specific spans paint last (non-decreasing start).
    var previous_start: usize = 0;
    for (spans) |span| {
        try testing.expect(span.source.start >= previous_start);
        previous_start = span.source.start;
    }
}

test "highlight range restricts spans to the requested window" {
    var engine = try Engine.init(testing.allocator);
    defer engine.deinit();
    var tree = engine.parse(sample_source, null) orelse return error.ParseFailed;
    defer tree.deinit();

    // Only the first line: `const std = @import("std");`
    const first_line_end = std.mem.indexOfScalar(u8, sample_source, '\n').?;
    const spans = try engine.highlights(testing.allocator, &tree, .{ .start = 0, .end = first_line_end });
    defer testing.allocator.free(spans);
    // The comment lives on line 2, outside the queried first-line window.
    try testing.expect(hasKind(spans, .keyword));
    try testing.expect(!hasKind(spans, .comment));
}

test "folds cover the function body block" {
    var engine = try Engine.init(testing.allocator);
    defer engine.deinit();
    var tree = engine.parse(sample_source, null) orelse return error.ParseFailed;
    defer tree.deinit();

    const ranges = try engine.folds(testing.allocator, &tree);
    defer testing.allocator.free(ranges);
    try testing.expect(ranges.len >= 1);
    // The `pub fn main() void {` block starts on line 2 (zero-based).
    var found_body = false;
    for (ranges) |fold| {
        try testing.expect(fold.isFoldable());
        if (fold.start_line == 2 and fold.end_line >= 7) found_body = true;
    }
    try testing.expect(found_body);
}

test "analyze builds highlights, folds, and a navigable outline" {
    var engine = try Engine.init(testing.allocator);
    defer engine.deinit();
    var tree = engine.parse(sample_source, null) orelse return error.ParseFailed;
    defer tree.deinit();

    var data = try engine.analyze(testing.allocator, &tree);
    defer data.deinit();

    try testing.expect(hasKind(data.highlights, .keyword));
    try testing.expect(data.folds.len >= 1);
    try testing.expect(data.outline.nodes.len >= 3);

    // Byte offset inside `message` on line 3.
    const inside = std.mem.indexOf(u8, sample_source, "message").?;
    const here = data.outline.enclosing(.{ .start = inside, .end = inside + 1 }) orelse
        return error.NoEnclosingNode;
    const node = data.outline.nodes[here];
    try testing.expect(node.source.start <= inside and node.source.end > inside);

    // Ascending reaches a strictly larger enclosing node.
    const parent_index = data.outline.parent(here) orelse return error.NoParent;
    const parent = data.outline.nodes[parent_index];
    try testing.expect(parent.source.start <= node.source.start and parent.source.end >= node.source.end);

    // The outline supports descending and sibling movement somewhere in the tree.
    try testing.expect(data.outline.firstChild(0) != null);
}

test "preset cancellation returns no tree for large input" {
    var engine = try Engine.init(testing.allocator);
    defer engine.deinit();

    const line = "const value: u32 = 12345;\n";
    const repeats = 60_000; // ~1.5 MiB, under the 2 MiB fallback ceiling
    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit(testing.allocator);
    try buffer.ensureTotalCapacity(testing.allocator, line.len * repeats);
    var index: usize = 0;
    while (index < repeats) : (index += 1) buffer.appendSliceAssumeCapacity(line);
    try testing.expect(buffer.items.len < max_parse_bytes);

    var flag: std.atomic.Value(bool) = .init(true);
    var cancel: CancelContext = .{ .flag = &flag };
    try testing.expect(engine.parse(buffer.items, &cancel) == null);

    // The parser recovers for the next request.
    var tree = engine.parse(sample_source, null) orelse return error.ParseFailed;
    defer tree.deinit();
    try testing.expect(!tree.hasError());
}

test "oversized input falls back to plain text" {
    var engine = try Engine.init(testing.allocator);
    defer engine.deinit();
    const big = try testing.allocator.alloc(u8, max_parse_bytes + 1);
    defer testing.allocator.free(big);
    @memset(big, ' ');
    try testing.expect(engine.parse(big, null) == null);
}
