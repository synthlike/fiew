---
id: ISSUE-0022
title: "Create and manage local review notes"
kind: "implementation"
status: claimed
created: 2026-08-25
assignee: "agent"
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

Deliver the Note Composer, persisted diff anchors, Review sidebar, Open/Resolved lifecycle, edit/delete behavior, gutter markers, and note navigation. Notes are stored as agent-retrievable Markdown (`fiew.review/v1`) in a gitignored `.reviews/` directory, per [ARP-0006](<docs/decisions/ARP-0006.md>): one file per review with frontmatter (`schema`, `created`, `base` ref+SHA) and note sections carrying authoritative bullets (`id`, `status`, `blob` when present), a required anchored diff excerpt for line notes, and a Markdown body.

## Acceptance criteria

- [ ] Notes attach to a contiguous old/new diff selection (line notes) or a whole file (file notes).
- [ ] `Ctrl-Enter` saves and `Esc` protects modified note text.
- [ ] Notes persist as versioned Markdown in the gitignored `.reviews/` directory and are re-read on open; a coding agent can retrieve and parse them.
- [ ] Line notes embed an anchored diff excerpt and, when a side blob exists, its blob ID, so a note reconciles to the reviewed content.
- [ ] Resolve, reopen, edit, delete, preview, and navigation commands work.
- [ ] Source, tracked files, `.gitignore`, and Git metadata remain unchanged; fiew writes only within `.reviews/`.

## Blocked by

Managed by native issue relationships.

## Out of scope

Cross-refresh anchor relocation, remote/shared review behavior, and reviewing arbitrary commits. fiew does not add the `.reviews/` entry to `.gitignore` itself.

## Comments

### 2026-08-27

Storage and format changed per [ARP-0006](<docs/decisions/ARP-0006.md>): review notes are now agent-retrievable Markdown in a gitignored `.reviews/` directory rather than JSON under the macOS user-data directory. The read-only boundary is amended to permit writes within `.reviews/` only. The `fiew.review/v1` format, the file-note vs line-note distinction, and the diff-excerpt/blob anchoring for agent reconciliation are captured in the ARP and reflected in the updated scope and acceptance criteria above.

## Resolution
