---
id: ISSUE-0026
title: "Verify the integrated read-first workflows"
kind: "implementation"
status: open
created: 2026-08-25
assignee: 
parent: "ISSUE-0013-implement-fiew-v0-1.md"
blocked_by:
  - "ISSUE-0023-re-anchor-notes-across-git-refreshes.md"
  - "ISSUE-0024-navigate-zig-definitions-through-trusted-zls.md"
  - "ISSUE-0025-preview-mermaid-fences-as-terminal-text.md"
labels: []
---
# Verify the integrated read-first workflows

## Parent

[Implement fiew v0.1](<.project/issues/ISSUE-0013-implement-fiew-v0-1.md>)

## Source specification

[fiew v0.1](<docs/specs/fiew-v0-1.md>)

## What to build

Exercise browsing, Git review with notes, and Zig definition navigation end to end; harden queues and cancellation; profile the 10,000-file target; and complete the Ghostty smoke checklist.

## Acceptance criteria

- [ ] All three required workflows pass from a clean user-data directory.
- [ ] Optional-tool failures preserve documented fallback behavior.
- [ ] Mutation audits confirm source and Git state remain unchanged.
- [ ] Shutdown cleans workers and subprocesses and restores Ghostty.
- [ ] Accepted performance limits are measured and documented honestly.
- [ ] `zig build test` remains offline and deterministic.

## Blocked by

Managed by native issue relationships.

## Out of scope

Release packaging and behavior outside the v0.1 compatibility boundary.

## Comments

## Resolution
