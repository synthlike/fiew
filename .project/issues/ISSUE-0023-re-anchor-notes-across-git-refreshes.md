---
id: ISSUE-0023
title: "Re-anchor review threads and bookmarks"
kind: "implementation"
status: open
created: 2026-08-25
assignee: 
parent: "ISSUE-0013-implement-fiew-v0-1.md"
blocked_by:
  - "ISSUE-0021-keep-git-views-current-and-consistent.md"
  - "ISSUE-0022-create-and-manage-local-review-notes.md"
  - "ISSUE-0033-evolve-local-review-notes-into-reviewer-owned-threads.md"
  - "ISSUE-0035-add-private-repository-bookmarks.md"
labels: []
---
# Re-anchor review threads and bookmarks

## Parent

[Implement fiew v0.1](<.project/issues/ISSUE-0013-implement-fiew-v0-1.md>)

## Source specification

[fiew v0.1](<docs/specs/fiew-v0-1.md>)

## What to build

Relocate review-thread and bookmark anchors across source and Git refreshes only when one exact match exists. Preserve identity and lifecycle state on success, expose Outdated when a location disappears or becomes ambiguous, and never guess.

## Acceptance criteria

- [ ] A unique exact match preserves thread or bookmark identity and current lifecycle state.
- [ ] Missing and ambiguous matches become Outdated without moving the anchor.
- [ ] Threads follow an unchanged change among Untracked, Unstaged, and Staged groups when exactly one anchor matches.
- [ ] Diff-created bookmarks reopen the mapped source location, never a historical diff presented as current.
- [ ] Repository movement never causes guessed reassociation.
- [ ] Shared anchor-transition fixtures cover refresh, group transitions, source changes, path changes, ambiguity, and missing content.

## Blocked by

Managed by native issue relationships.

## Out of scope

Heuristic relocation, semantic language-server anchors, and remote synchronization.

## Comments

## Resolution
