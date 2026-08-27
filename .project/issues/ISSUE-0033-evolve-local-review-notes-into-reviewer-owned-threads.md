---
id: ISSUE-0033
title: "Evolve local review notes into reviewer-owned threads"
kind: "implementation"
status: resolved
created: 2026-08-27
assignee: "agent"
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

**Outcome: Achieved.**

Replaced editable notes with reviewer-owned `fiew.review/v1` threads:

- Threads anchor to a changed file or a contiguous old/new diff selection. Production `v` + movement supports multiline selection; mixed-side ranges are refused.
- `Space r n` creates a diff thread, `Space r f` creates a file thread, and `Space r a` appends a reviewer comment.
- Comments retain ordered `reviewer` or `agent` roles and have no edit or individual-delete operation.
- Reviewer authority gates thread creation, resolve/reopen, and complete-thread deletion. `Space r d` requires explicit `y` confirmation.
- Open, Resolved, and Outdated states render distinctly. Open and Outdated block approval.
- Review sidebar state now owns keyboard/mouse selection, preview, scrolling, focus, and detail scrolling independently.
- The v1 thread Markdown format byte-counts comment bodies, so ordinary Markdown headings cannot become structural delimiters. Schema and anchor fields are validated; future schemas are refused without overwrite.
- The superseded local note layout is intentionally unsupported; this breaking change reserves v2 for a future deployed schema evolution.
- Storage validates serialized bytes, writes same-directory atomically, retains one validated backup, repairs a malformed primary from that backup, and refuses invalid/future primaries.
- Failed writes leave dirty or pending-deletion state intact. Approval requires zero blocking threads and no unsaved state.

Verification passed:

- `zig build --system zig-pkg`
- `zig build test --system zig-pkg`
- `zig build test --system zig-pkg -Dgit-integration --summary all` — 105/105 tests
- `zig fmt --check src build.zig`
- `zig build -Doptimize=ReleaseSafe --system zig-pkg`
- `zig build -Dtarget=aarch64-macos --system zig-pkg`
- `git diff --check`

Coverage includes production command paths for multiline and file anchors, mixed-side refusal, role authority, append order, deletion confirmation, sidebar selection/scroll, status and role rendering, arbitrary Markdown, schema refusal, rejection of the superseded note layout, validated backup recovery, and persistence-aware approval. No manual Ghostty session was performed.
