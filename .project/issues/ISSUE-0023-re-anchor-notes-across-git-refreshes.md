---
id: ISSUE-0023
title: "Re-anchor notes across Git refreshes"
kind: "implementation"
status: open
created: 2026-08-25
assignee: 
parent: "ISSUE-0013-implement-fiew-v0-1.md"
blocked_by:
  - "ISSUE-0021-keep-git-views-current-and-consistent.md"
  - "ISSUE-0022-create-and-manage-local-review-notes.md"
labels: []
---
# Re-anchor notes across Git refreshes

## Parent

[Implement fiew v0.1](<.project/issues/ISSUE-0013-implement-fiew-v0-1.md>)

## Source specification

[fiew v0.1](<docs/specs/fiew-v0-1.md>)

## What to build

Relocate notes only through exact unique matches across changed lines and Git groups, expose Outdated and detached states, and support explicit repository reassociation.

## Acceptance criteria

- [ ] Unique matches preserve note identity and current lifecycle state.
- [ ] Missing or ambiguous matches become Outdated.
- [ ] Notes follow unchanged changes among Untracked, Unstaged, and Staged.
- [ ] Repository movement never causes guessed reassociation.
- [ ] Anchor-transition fixtures cover refresh and path changes.

## Blocked by

Managed by native issue relationships.

## Out of scope

Heuristic or remote note synchronization.

## Comments

## Resolution
