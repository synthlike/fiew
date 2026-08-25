<!-- agent-workflows-record
{"archived":false,"created":"2026-08-25T20:38:47Z","id":"tree-sitter-integration-constraints-for-fiew-v0-1","modified":"2026-08-25T20:38:47Z","record_type":"research","title":"Tree-sitter integration constraints for fiew v0.1"}
-->
# Tree-sitter integration constraints for fiew v0.1

## Question

Which Tree-sitter integration boundary can provide responsive Zig and Markdown highlighting, folding, and structural navigation in a Zig 0.16.0 terminal application?

This research informs the parsing architecture decision in ISSUE-0008.

## Verified findings

- Tree-sitter v0.26.13 resolves to commit `d97971e24500218865c05ed1febdee2acf41bae1`. Its C API supports grammar ABI versions 13 through 15.
- Zig grammar revision `6479aa13f32f701c383083d8b28360ebd682fb7d` generates an ABI 15 parser and provides `highlights.scm`, `folds.scm`, `indents.scm`, `injections.scm`, and `locals.scm` queries.
- Markdown grammar revision `a0a00f817d02412bd92c54d316f164d827b57b5c` generates ABI 15 block and inline parsers. It provides highlighting and injection queries but no folding query.
- The Markdown grammar requires a block parse followed by an inline parse over ranges identified by `inline` nodes. Its documentation directs clients to use `ts_parser_set_included_ranges` for the second parse.
- The Markdown project describes the grammar as intended for editor syntax information and warns against correctness-critical use because Markdown cannot be represented fully accurately under Tree-sitter's parsing constraints.
- Tree-sitter's C API accepts callback-based UTF-8 input through `TSInput`.
- `ts_parser_parse_with_options` accepts a progress callback that can cancel parsing.
- Tree-sitter supports incremental reparsing by editing an old tree, passing it to the next parse, and obtaining changed ranges. This capability is available even though fiew v0.1 does not edit source.
- Query cursors can constrain execution by byte or point range, allowing highlighting work to be bounded around a viewport.
- Tree-sitter core and both selected grammar repositories use the MIT license.

## Interpretation

- Zig can statically compile the Tree-sitter C core and generated grammar C sources, so a third-party Zig wrapper is not required.
- A thin adapter can contain C ownership and translate syntax output into immutable fiew-owned parse snapshots, highlight spans, and fold ranges.
- Parsing outside the render loop and range-limited highlighting queries can keep terminal rendering independent of parser latency.
- Markdown needs project-owned fold queries. Its parse tree must be treated as presentation assistance, not semantic truth.
- Immutable dependency revisions and ABI checks are necessary because grammar compatibility depends on the Tree-sitter ABI.

## Remaining uncertainty

- The accepted 2 MiB file threshold, 100 ms pending indicator, and one-second cancellation limit are conservative project policies. Their responsiveness has not been verified on the supported Apple Silicon and Ghostty baseline.
- Memory use and query latency remain unmeasured because no fiew source or benchmark harness exists.
- Exact Zig 0.16 build declarations for the C core and grammar scanners remain implementation work.

## Sources

- [Tree-sitter v0.26.13 C API](https://github.com/tree-sitter/tree-sitter/blob/v0.26.13/lib/include/tree_sitter/api.h)
- [Tree-sitter basic parsing documentation](https://tree-sitter.github.io/tree-sitter/using-parsers/2-basic-parsing.html)
- [Tree-sitter advanced parsing documentation](https://tree-sitter.github.io/tree-sitter/using-parsers/3-advanced-parsing.html)
- [Tree-sitter syntax highlighting documentation](https://tree-sitter.github.io/tree-sitter/3-syntax-highlighting.html)
- [Selected Zig grammar revision](https://github.com/tree-sitter-grammars/tree-sitter-zig/tree/6479aa13f32f701c383083d8b28360ebd682fb7d)
- [Selected Markdown grammar revision](https://github.com/tree-sitter-grammars/tree-sitter-markdown/tree/a0a00f817d02412bd92c54d316f164d827b57b5c)
