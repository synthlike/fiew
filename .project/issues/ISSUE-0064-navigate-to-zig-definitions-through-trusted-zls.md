---
id: ISSUE-0064
title: "Navigate to Zig definitions through trusted ZLS"
kind: "implementation"
status: open
created: 2026-08-28
assignee:
parent: "ISSUE-0057-implement-fiew-v0-2.md"
blocked_by:
  - "ISSUE-0063-establish-trusted-zls-lifecycle-and-read-only-enforcement.md"
labels: []
---
# Navigate to Zig definitions through trusted ZLS

## Parent

[fiew v0.2](<docs/specs/fiew-v0-2.md>)

## What to build

Deliver `g d` from the active Zig selection through validated ZLS results to immediate or selected read-only navigation.

## Acceptance criteria

- [ ] One valid result opens directly and multiple valid results use a transient path, line, and source-preview list.
- [ ] Validated outside-repository files open read-only with an **External** label.
- [ ] Preview movement does not affect history; pinning adds exactly one origin and `Ctrl-o`/`Ctrl-i` traverse it.
- [ ] Cancellation, two-second timeout, stale generations, malformed responses, and invalid locations preserve selection, view, and history.
- [ ] No-result and exact unavailable ZLS states are explicit, with no heuristic navigation fallback.
- [ ] Transcript, reducer, and render tests pass offline.

## Blocked by

Managed by native issue relationships.

## Out of scope

References, hover, diagnostics, symbols, and source-writing LSP capabilities.

## Comments

## Resolution
