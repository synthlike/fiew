---
id: ISSUE-0066
title: "Show Zig hover information through trusted ZLS"
kind: "implementation"
status: open
created: 2026-08-28
assignee:
parent: "ISSUE-0057-implement-fiew-v0-2.md"
blocked_by:
  - "ISSUE-0063-establish-trusted-zls-lifecycle-and-read-only-enforcement.md"
labels: []
---
# Show Zig hover information through trusted ZLS

## Parent

[fiew v0.2](<docs/specs/fiew-v0-2.md>)

## What to build

Deliver `K` from the active Zig selection to bounded, sanitized, scrollable hover documentation and type information.

## Acceptance criteria

- [ ] Hover opens without changing selection or location history and preserves unsupported markup as readable text.
- [ ] Long content scrolls; `Esc`, `q`, navigation, or snapshot replacement dismisses it.
- [ ] A new hover supersedes an older request and stale output never replaces current information.
- [ ] Cancellation, two-second timeout, malformed output, and no-result states are explicit and non-destructive.
- [ ] Transcript, reducer, sanitization, and render tests pass offline.

## Blocked by

Managed by native issue relationships.

## Out of scope

Completion, diagnostics, symbols, rich web rendering, and persistent hover panels.

## Comments

## Resolution
