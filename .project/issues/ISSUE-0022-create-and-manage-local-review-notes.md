---
id: ISSUE-0022
title: "Create and manage local review notes"
kind: "implementation"
status: open
created: 2026-08-25
assignee: 
parent: "ISSUE-0013-implement-fiew-v0-1.md"
blocked_by:
  - "ISSUE-0017-establish-recoverable-fiew-owned-state.md"
  - "ISSUE-0020-review-current-git-changes.md"
labels: []
---
# Create and manage local review notes

## Parent

[Implement fiew v0.1](<.project/issues/ISSUE-0013-implement-fiew-v0-1.md>)

## Source specification

[fiew v0.1](<docs/specs/fiew-v0-1.md>)

## What to build

Deliver the Note Composer, persisted diff anchors, Review sidebar, Open/Resolved lifecycle, edit/delete behavior, gutter markers, and note navigation.

## Acceptance criteria

- [ ] Notes attach only to textual old/new diff selections.
- [ ] `Ctrl-Enter` saves and `Esc` protects modified note text.
- [ ] Notes survive application restart outside the repository and `.git`.
- [ ] Resolve, reopen, edit, delete, preview, and navigation commands work.
- [ ] Repository and Git files remain unchanged.

## Blocked by

Managed by native issue relationships.

## Out of scope

Cross-refresh anchor relocation and remote/shared review behavior.

## Comments

## Resolution
