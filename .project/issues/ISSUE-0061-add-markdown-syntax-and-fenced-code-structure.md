---
id: ISSUE-0061
title: "Add Markdown syntax and fenced-code structure"
kind: "implementation"
status: open
created: 2026-08-28
assignee:
parent: "ISSUE-0057-implement-fiew-v0-2.md"
blocked_by:
labels: []
---
# Add Markdown syntax and fenced-code structure

## Parent

[fiew v0.2](<docs/specs/fiew-v0-2.md>)

## What to build

Deliver Markdown block and inline parsing, viewport highlighting, structural navigation, section and fence folding, and one-level Zig fence injection.

## Acceptance criteria

- [ ] Representative Markdown produces correct block/inline ranges, highlights, section folds, and fence folds.
- [ ] Explicitly labeled Zig fences receive one level of Zig highlighting and structure.
- [ ] Malformed, oversized, invalid-UTF-8, failed, cancelled, and stale parsing retains complete plain-text navigation.
- [ ] Tree-sitter ABI, ownership, query, cancellation, and immutable snapshot boundaries remain enforced.
- [ ] Query, adapter, and render fixtures pass offline without optional executables.

## Blocked by

Managed by native issue relationships.

## Out of scope

Mermaid rendering, additional grammars, nested injections, and indentation folding.

## Comments

## Resolution
