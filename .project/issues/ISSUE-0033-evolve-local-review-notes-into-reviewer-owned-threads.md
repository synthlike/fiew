---
id: ISSUE-0033
title: "Evolve local review notes into reviewer-owned threads"
kind: "implementation"
status: open
created: 2026-08-27
assignee:
parent: "ISSUE-0013-implement-fiew-v0-1.md"
blocked_by:
labels: []
---
# Evolve local review notes into reviewer-owned threads

## Parent

[Implement fiew v0.1](<.project/issues/ISSUE-0013-implement-fiew-v0-1.md>)

## What to build

Replace editable independent notes with stable file- or diff-anchored threads containing ordered append-only reviewer and agent comments. Make reviewer authority, lifecycle, sidebar behavior, and persistence trustworthy end to end.

This follow-up owns the unresolved conformance findings recorded on [Create and manage local review notes](<.project/issues/ISSUE-0022-create-and-manage-local-review-notes.md>).

## Acceptance criteria

- [ ] A reviewer can create a file thread or a thread from a contiguous one-side multiline diff selection through production commands.
- [ ] Reviewer and agent comments remain ordered and append-only; persisted comments cannot be edited or individually deleted.
- [ ] Only the reviewer can create, resolve, reopen, or delete a complete thread, and deletion requires confirmation.
- [ ] Open, Resolved, and Outdated states are visible; Open and Outdated block approval.
- [ ] The Review sidebar has independent keyboard and mouse selection, preview, scrolling, and navigation.
- [ ] The versioned Markdown parser accepts ordinary Markdown headings in comment bodies, validates its schema, refuses future schemas, and recovers from one validated backup.
- [ ] Atomic persistence failure preserves dirty state and cannot be reported as successful approval.
- [ ] Command/reducer, format, storage, and render tests cover roles, multiline/file anchors, confirmation, arbitrary Markdown, schema refusal, and recovery.

## Blocked by

Managed by native issue relationships.

## Out of scope

Agent thread creation or lifecycle control, remote synchronization, reactions, attachments, and anchor relocation across refreshes.

## Comments


## Resolution
