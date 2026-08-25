---
id: ISSUE-0021
title: "Keep Git views current and consistent"
kind: "implementation"
status: open
created: 2026-08-25
assignee: 
parent: "ISSUE-0013-implement-fiew-v0-1.md"
blocked_by:
  - "ISSUE-0018-add-zig-syntax-folding-and-structural-navigation.md"
  - "ISSUE-0019-add-markdown-syntax-and-fenced-code-structure.md"
  - "ISSUE-0020-review-current-git-changes.md"
labels: []
---
# Keep Git views current and consistent

## Parent

[Implement fiew v0.1](<.project/issues/ISSUE-0013-implement-fiew-v0-1.md>)

## Source specification

[fiew v0.1](<docs/specs/fiew-v0-1.md>)

## What to build

Add debounced filesystem refresh, immutable Git snapshots, consistency retry, stale-state handling, selection preservation, cancellation, and syntax-layered Zig/Markdown diffs.

## Acceptance criteria

- [ ] Partial or changing Git snapshots are never published.
- [ ] Repository fingerprint changes cause at most one retry.
- [ ] Failed refresh retains and marks the previous snapshot stale.
- [ ] Obsolete refresh and parse work is cancelled.
- [ ] Diff viewing never waits for syntax parsing.

## Blocked by

Managed by native issue relationships.

## Out of scope

Review-note creation and anchoring.

## Comments

## Resolution
