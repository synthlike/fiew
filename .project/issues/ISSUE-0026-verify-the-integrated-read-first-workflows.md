---
id: ISSUE-0026
title: "Verify the integrated v0.1 review workflows"
kind: "implementation"
status: open
created: 2026-08-25
assignee: 
parent: "ISSUE-0013-implement-fiew-v0-1.md"
blocked_by:
  - "ISSUE-0023-re-anchor-notes-across-git-refreshes.md"
  - "ISSUE-0034-replace-the-legacy-review-flag-with-the-agent-review-interface.md"
labels: []
---
# Verify the integrated v0.1 review workflows

## Parent

[Implement fiew v0.1](<.project/issues/ISSUE-0013-implement-fiew-v0-1.md>)

## Source specification

[fiew v0.1](<docs/specs/fiew-v0-1.md>)

## What to build

Exercise immutable browsing, Git-backed VCS review, reviewer-agent thread conversations, strict approval, private repository-local bookmarks, refresh, and recovery end to end. Harden queues and cancellation, profile the 10,000-file target, and complete the Ghostty smoke checklist.

## Acceptance criteria

- [ ] Project, VCS, Review, and Bookmarks workflows pass from clean `.reviews/` and `.bookmarks/` directories and a nested repository working directory.
- [ ] An agent can discover the current review without an exchanged ID, read all previous comments, and append a reply but cannot create, resolve, reopen, delete, or change the current review.
- [ ] Reviewer start/open operations update current atomically; approval preserves it, historical explicit-ID access does not change it, and missing, malformed, or dangling pointers fail without inference.
- [ ] Exit status reports approval only after every thread is durably reviewer-resolved.
- [ ] Malformed, legacy, future-schema, failed-write, and backup-recovery cases preserve durable state and the read-only boundary.
- [ ] Canonical review and bookmark JSON share the accepted schema envelope while public review JSON and Markdown projections retain complete public semantics and omit private bookmark data.
- [ ] Mutation audits confirm source and Git state remain unchanged.
- [ ] Shutdown cleans workers and subprocesses and restores Ghostty.
- [ ] Accepted performance limits are measured and documented honestly.
- [ ] `zig build test` remains offline and deterministic.

## Blocked by

Managed by native issue relationships.

## Out of scope

Release packaging and all v0.2 capabilities.

## Comments

## Resolution
