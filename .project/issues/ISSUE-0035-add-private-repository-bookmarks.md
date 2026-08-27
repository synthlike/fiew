---
id: ISSUE-0035
title: "Add private repository bookmarks"
kind: "implementation"
status: open
created: 2026-08-27
assignee:
parent: "ISSUE-0013-implement-fiew-v0-1.md"
blocked_by:
labels: []
---
# Add private repository bookmarks

## Parent

[Implement fiew v0.1](<.project/issues/ISSUE-0013-implement-fiew-v0-1.md>)

## What to build

Let a reviewer save source locations for later inspection without exposing them to agents or writing them into the repository. Bookmarks may originate in source or a diff and may carry a short optional label.

## Acceptance criteria

- [ ] `Space b Enter` opens the Bookmarks sidebar; `Space b n` creates a bookmark with an optional short label; `Space b d` deletes with confirmation; `[ b` and `] b` navigate.
- [ ] Bookmarks live in schema-versioned global fiew-owned state outside repositories and are keyed by repository identity.
- [ ] A source bookmark records the selected source location; a diff bookmark maps to its source location and reopens source rather than a historical diff.
- [ ] Empty labels are accepted, labels remain short, and the sidebar distinguishes labelled, unlabelled, and Outdated entries.
- [ ] Bookmarks are absent from review Markdown and all agent-facing review output.
- [ ] Atomic persistence, backup recovery, future-schema refusal, repository-key isolation, and source/Git non-mutation are verified.

## Blocked by

Managed by native issue relationships.

## Out of scope

Shared bookmarks, agent-visible bookmarks, tags, folders, synchronization, and semantic language-server reanchoring.

## Comments


## Resolution
