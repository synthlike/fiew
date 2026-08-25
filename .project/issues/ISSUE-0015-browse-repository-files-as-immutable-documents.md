---
id: ISSUE-0015
title: "Browse repository files as immutable documents"
kind: "implementation"
status: open
created: 2026-08-25
assignee: 
parent: "ISSUE-0013-implement-fiew-v0-1.md"
blocked_by:
  - "ISSUE-0014-bootstrap-a-safe-ghostty-application.md"
labels: []
---
# Browse repository files as immutable documents

## Parent

[Implement fiew v0.1](<.project/issues/ISSUE-0013-implement-fiew-v0-1.md>)

## Source specification

[fiew v0.1](<docs/specs/fiew-v0-1.md>)

## What to build

Open a directory, display its Project tree, preview and pin files, navigate plain text, handle binary and invalid UTF-8 files, and apply the responsive sidebar layout.

## Acceptance criteria

- [ ] The Project tree remains usable at the 10,000-tracked-file target.
- [ ] Preview, pin, collapse, focus, and resize behavior matches the specification.
- [ ] Text navigation is grapheme-safe and preserves byte mappings.
- [ ] Binary and invalid UTF-8 behavior is verified.
- [ ] Source files remain byte-for-byte unchanged.

## Blocked by

Managed by native issue relationships.

## Out of scope

Complete modal command surfaces and external integrations.

## Comments

## Resolution
