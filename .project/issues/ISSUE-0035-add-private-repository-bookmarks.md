---
id: ISSUE-0035
title: "Add private repository bookmarks"
kind: "implementation"
status: resolved
created: 2026-08-27
assignee: "agent"
parent: "ISSUE-0013-implement-fiew-v0-1.md"
blocked_by:
labels: []
---
# Add private repository bookmarks

## Parent

[Implement fiew v0.1](<.project/issues/ISSUE-0013-implement-fiew-v0-1.md>)

## What to build

Let a reviewer save repository-local source locations for later inspection without exposing them through agent-facing review commands or modifying source and Git state. Bookmarks may originate in source or a diff and may carry a short optional label. Persist them as private canonical JSON in `.bookmarks/bookmarks.json` according to ARP-0008 and the v0.1 specification.

## Acceptance criteria

- [ ] `Space b Enter` opens the Bookmarks sidebar; `Space b n` creates a bookmark with an optional short label; `Space b d` deletes with confirmation; `[ b` and `] b` navigate.
- [ ] Bookmarks use the `{ "schema": "fiew.bookmark/v1", "data": ... }` envelope in repository-local `.bookmarks/bookmarks.json`; fiew neither checks nor modifies Git ignore configuration.
- [ ] A source bookmark records the selected source location; a diff bookmark maps to its source location and reopens source rather than a historical diff.
- [ ] Empty labels are accepted, labels remain short, and the sidebar distinguishes labelled, unlabelled, and Outdated entries.
- [ ] Bookmarks are absent from public JSON and Markdown review projections and all other agent-facing review output.
- [ ] Same-directory atomic persistence, validated `.bookmarks/bookmarks.bak` recovery, future-schema refusal, repository-local isolation, and source/Git non-mutation are verified.
- [ ] Unreleased global bookmark data is not migrated or interpreted as current bookmark state.

## Blocked by

Managed by native issue relationships.

## Out of scope

Shared bookmarks, agent-visible bookmarks, tags, folders, synchronization, ignore-rule management, migration of global bookmark data, and semantic language-server reanchoring.

## Comments
## Resolution

Delivered repository-local private bookmarks using the accepted `fiew.bookmark/v1` schema-plus-data envelope at `.bookmarks/bookmarks.json`. Added source and diff-to-current-source capture, optional short labels, independent Bookmarks sidebar keyboard/mouse interaction, preview and activation, previous/next navigation, confirmed deletion, Outdated status, persistence-aware quit behavior, atomic writes, validated backup recovery, future-schema refusal, and repository isolation. Bookmark data remains absent from public review JSON and Markdown projections. fiew neither checks nor modifies ignore configuration and performs no global bookmark migration. Verification passes with 126/126 tests, ReleaseSafe, and Apple Silicon macOS builds; the reviewer approved the result.
