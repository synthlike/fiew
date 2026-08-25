---
id: ISSUE-0018
title: "Add Zig syntax, folding, and structural navigation"
kind: "implementation"
status: open
created: 2026-08-25
assignee: 
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

- [ ] Accepted dependency revisions and grammar ABI checks are pinned.
- [ ] Parsing and queries never execute during cell rendering.
- [ ] The 2 MiB, 100 ms, and one-second boundaries produce safe fallback.
- [ ] Specified fold and structural commands work on representative Zig files.
- [ ] Ownership, cancellation, and stale-result tests pass.

## Blocked by

Managed by native issue relationships.

## Out of scope

Markdown parsing and semantic ZLS navigation.

## Comments

## Resolution
