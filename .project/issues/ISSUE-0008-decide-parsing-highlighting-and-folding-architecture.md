---
id: ISSUE-0008
title: "Decide parsing, highlighting, and folding architecture"
kind: "research"
status: resolved
created: 2026-08-25
assignee: 
parent: "ISSUE-0001-plan-fiew-v0-1.md"
blocked_by:
  - "ISSUE-0003-define-the-v0-1-workflows-and-feature-boundary.md"
  - "ISSUE-0005-establish-the-zig-and-terminal-ui-technical-baseline.md"
labels: []
---
# Decide parsing, highlighting, and folding architecture

## Question

How should fiew integrate Tree-sitter or alternatives for syntax highlighting, structural navigation, and code folding while preserving responsive incremental rendering?

## Comments
## Resolution

Accepted based on [Tree-sitter integration constraints for fiew v0.1](<docs/research/tree-sitter-integration-constraints-for-fiew-v0-1.md>). The consequential integration boundary is recorded in [Integrate Tree-sitter behind a direct C adapter](<docs/decisions/ARP-0002.md>).

## Language and dependency scope

- Support Tree-sitter highlighting, folding, and structural navigation for Zig and Markdown only. Every other file remains fully navigable plain text.
- Statically compile Tree-sitter v0.26.13 at `d97971e24500218865c05ed1febdee2acf41bae1`, Zig grammar at `6479aa13f32f701c383083d8b28360ebd682fb7d`, and Markdown grammar at `a0a00f817d02412bd92c54d316f164d827b57b5c`.
- Call the C API through a thin Zig adapter that owns all C lifetimes and publishes fiew-owned immutable results.
- Markdown uses block and inline parsers. Only fenced blocks explicitly labeled `zig` receive nested Zig parsing; nested parsing stops after one level. Mermaid remains with ISSUE-0011.

## Responsiveness and fallback

- Parse outside the render loop in cancellable worker jobs. Render plain text immediately and atomically publish completed snapshots.
- Retain the previous valid snapshot during external reload, cancel obsolete work, and never let parse failure block text viewing or navigation.
- Compute highlighting for the visible viewport plus one viewport above and below. Cache normalized style spans by snapshot and row range; never execute queries during cell rendering.
- Parse supported files only up to 2 MiB. Show parsing status after 100 ms and cancel after one second, falling back to plain text. Profile these conservative policies on the supported hardware before treating them as performance guarantees.

## Folding

- Derive folds only from Tree-sitter queries: the pinned Zig `folds.scm` and fiew-owned Markdown section and fenced-block queries. Do not use indentation heuristics.
- Keep fold state outside syntax trees by document byte range and node kind. Restore only equivalent folds after reload; expand unmatched folds.
- `z c`, `z o`, and `z a` close, open, and toggle the fold at the selection. `z M` and `z R` close and open all folds.

## Structural navigation

- `Alt-o` expands to the smallest named parent node; `Alt-i` shrinks through prior expansions; `Alt-n` and `Alt-p` select next and previous named siblings.
- Structural-boundary failure leaves selection unchanged and reports why. Unsupported and fallback files expose these commands as disabled with a reason.
- Structural navigation is syntactic only. Semantic definition and reference behavior remains an LSP concern.
