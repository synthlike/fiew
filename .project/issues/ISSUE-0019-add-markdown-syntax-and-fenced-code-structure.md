---
id: ISSUE-0019
title: "Add Markdown syntax and fenced-code structure"
kind: "implementation"
status: open
created: 2026-08-25
assignee: 
parent: "ISSUE-0052-hold-deferred-fiew-v0-2-implementation-candidates.md"
blocked_by:
  - "ISSUE-0018-add-zig-syntax-folding-and-structural-navigation.md"
labels: []
---
# Add Markdown syntax and fenced-code structure

## Parent

[Hold deferred fiew v0.2 implementation candidates](<.project/issues/ISSUE-0052-hold-deferred-fiew-v0-2-implementation-candidates.md>)

## Planning status

Deferred from v0.1. This is a candidate v0.2 implementation slice and must be reconciled with the eventual v0.2 specification before implementation.

## What to build

Integrate Markdown block and inline parsing, viewport highlighting, section and fenced-block folding, and one-level Zig fence injection.

## Acceptance criteria

- [ ] Block and inline included ranges are correct for representative Markdown.
- [ ] Fiew-owned Markdown fold queries produce section and fence ranges.
- [ ] Explicit `zig` fences receive Zig highlighting to one level.
- [ ] Malformed or unsupported Markdown remains fully navigable.
- [ ] Snapshot and query fixtures pass without optional executables.

## Blocked by

Managed by native issue relationships.

## Out of scope

Mermaid rendering and additional grammar injections.

## Comments

## Resolution
