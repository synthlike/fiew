---
id: ISSUE-0018
title: "Add Zig syntax, folding, and structural navigation"
kind: "implementation"
status: resolved
created: 2026-08-25
assignee: "agent"
parent: "ISSUE-0013-implement-fiew-v0-1.md"
blocked_by:
  - "ISSUE-0016-complete-the-modal-command-and-workspace-language.md"
labels: []
---
# Add Zig syntax, folding, and structural navigation

## Parent

[Implement fiew v0.1](<.project/issues/ISSUE-0013-implement-fiew-v0-1.md>)

## Source specification

[fiew v0.1](<docs/specs/fiew-v0-1.md>)

## What to build

Integrate pinned Tree-sitter core and Zig grammar through the direct C adapter, with asynchronous parse snapshots, viewport highlighting, folding, structural navigation, cancellation, and plain-text fallback.

## Acceptance criteria

- [x] Accepted dependency revisions and grammar ABI checks are pinned.
- [x] Parsing and queries never execute during cell rendering.
- [x] The 2 MiB, 100 ms, and one-second boundaries produce safe fallback.
- [x] Specified fold and structural commands work on representative Zig files.
- [x] Ownership, cancellation, and stale-result tests pass.

## Blocked by

Managed by native issue relationships.

## Out of scope

Markdown parsing and semantic ZLS navigation.

## Comments

## Resolution

**Outcome: Achieved.**

Integrated Tree-sitter for Zig behind a direct C adapter with asynchronous parse snapshots, syntax highlighting, folding, structural navigation, cancellation, and plain-text fallback. Markdown parsing and semantic ZLS navigation remain out of scope.

Delivered:

- **Vendored, pinned toolchain.** Tree-sitter core v0.26.13 (`d97971e`) and the tree-sitter-zig grammar (`6479aa1`, ABI 15) are committed under `vendor/` (with `REVISION`/`LICENSE`) and statically compiled by `build.zig` (WASM feature off). The adapter asserts the grammar's ABI is within the core's supported 13–15 range at engine init.
- **`src/adapters/treesitter/zig_syntax.zig`** — the one C boundary. An `Engine` owns the `TSParser`, compiled queries, and cursors; parsing streams source through a `TSInput` and cancels via the `ts_parser_parse_with_options` progress callback. `analyze()` returns a fully fiew-owned `ParseData` (highlight spans, fold ranges, pre-order outline); no Tree-sitter type escapes.
- **`src/model/syntax.zig`** — fiew-owned `HighlightSpan`/`FoldRange`/`Outline`/`ParseData` with pure structural navigation (enclosing/parent/child/siblings) and innermost-fold lookup.
- **Reducer integration** — `View` carries parse data and collapsed-fold state; `App` implements `z c/z o/z a/z M/z R` and `Alt-o/Alt-i/Alt-n/Alt-p`; vertical movement and rendering skip folded lines. Commands are gated by dynamic availability and dispatched through the one command registry.
- **`src/adapters/treesitter/parse_job.zig`** — the off-render analysis step plus a `Coordinator` that rejects results whose generation was superseded; timing policy for the 100 ms pending and one-second deadline boundaries.
- **`main.zig` `ParseState`** — runs one parse job at a time on an `io.concurrent` worker, routes completions to the matching view by generation, and cancels past the deadline. The render path only reads precomputed spans/folds.

Notable decisions:

- **Pinning by vendored source, not package hash.** The core's upstream `build.zig` is pre-0.16 (breaks `b.dependency`) and the grammar's `build.zig.zon` lacks a `fingerprint` (breaks `zig fetch --save`), so exact revisions are committed and documented instead — stronger for offline/deterministic builds.
- **fiew-owned, predicate-free highlight query.** The C query API does not evaluate the grammar's `#lua-match?` predicates, so a node-type/token query (drawn from the grammar's own captures) is used to avoid over-matching. Folding uses the grammar's own `folds.scm`.
- Highlighting analyzes the whole (≤ 2 MiB) document, which covers any viewport; the tick timer gives ~250 ms deadline granularity; `Alt-i` descends to the first named child.

Verification passed:

- `zig build`
- `zig build test --system zig-pkg` — 64/64 tests (adapter ABI/parse/highlight/fold/outline, cancellation, oversize fallback, stale-result rejection, reducer fold/structural, real-parse end-to-end)
- `zig fmt --check src build.zig`
- `zig build -Doptimize=ReleaseSafe --system zig-pkg`
- `zig build -Dtarget=aarch64-macos --system zig-pkg`
- Manual run: launched fiew against `src/model`, confirmed live syntax colors, `z c`/`z R` folding with a `⋯` marker and hidden lines, structural `Alt-o`, and a clean quit — no crashes.

`zig build test` needs no network or optional executables (dependencies are vendored). Markdown, Mermaid, Git, review notes, and ZLS remain outside this issue.
