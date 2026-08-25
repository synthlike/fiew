---
id: ISSUE-0024
title: "Navigate Zig definitions through trusted ZLS"
kind: "implementation"
status: open
created: 2026-08-25
assignee: 
parent: "ISSUE-0013-implement-fiew-v0-1.md"
blocked_by:
  - "ISSUE-0016-complete-the-modal-command-and-workspace-language.md"
  - "ISSUE-0017-establish-recoverable-fiew-owned-state.md"
labels: []
---
# Navigate Zig definitions through trusted ZLS

## Parent

[Implement fiew v0.1](<.project/issues/ISSUE-0013-implement-fiew-v0-1.md>)

## Source specification

[fiew v0.1](<docs/specs/fiew-v0-1.md>)

## What to build

Deliver repository trust, ZLS version validation and process lifecycle, definition requests, UTF-8/UTF-16 mapping, multiple-result previews, External views, cancellation, timeout, and read-only protocol enforcement.

## Acceptance criteria

- [ ] ZLS never launches before explicit repository trust.
- [ ] Definition navigation and history return work with transcript and opt-in integration tests.
- [ ] Stale, late, malformed, cancelled, and timed-out responses never navigate.
- [ ] Workspace edits and server commands are refused.
- [ ] Missing, incompatible, or crashed ZLS preserves non-LSP behavior.
- [ ] Shutdown, restart, and trust revocation cleanly stop the process.

## Blocked by

Managed by native issue relationships.

## Out of scope

Other LSP methods, generic servers, and Markdown LSP.

## Comments

## Resolution
