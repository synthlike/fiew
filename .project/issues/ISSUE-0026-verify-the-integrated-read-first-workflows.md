---
id: ISSUE-0026
title: "Verify the integrated v0.1 review workflows"
kind: "implementation"
status: resolved
created: 2026-08-25
assignee: "agent"
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

Completed integrated v0.1 verification on the supported Apple Silicon macOS and Ghostty baseline.

- Added opt-in `-Dperformance` coverage for a 10,000-file filesystem scan and a clean Git snapshot over 10,000 tracked files.
- Measured 437 ms for the filesystem scan and 189 ms for the clean Git snapshot on this machine; the full profiled suite passed 144/144 tests.
- The normal deterministic suite passed 136/144 with 8 expected opt-in skips using clean local/global caches, system-pinned dependencies, and Git absent from `PATH`.
- Git integration passed 142/144 with only the 2 performance tests skipped.
- A `ReleaseSafe` Mach-O ARM64 build completed successfully.
- An end-to-end non-interactive CLI fixture verified nested-root discovery, public current-review output, ordered agent replies, exit `1` for unapproved but successful show/reply, exit `0` for an approved historical review, exit `2` for command failures, unchanged current selection during historical access, malformed and dangling pointer refusal, and unchanged source, index, HEAD, and Git status.
- Existing deterministic coverage passed for canonical review/bookmark envelopes, public projections, backup recovery, future-schema refusal, persistence failures, role authority, stale completion rejection, re-anchoring, queue/cancellation behavior, and bookmark isolation.
- Corrected the engineering baseline to reflect canonical repository-local JSON reviews and bookmarks and recorded current verification evidence.
- Updated the Ghostty checklist to current Review Diff and Review Threads bindings and wrapped-comment behavior.
- The reviewer confirmed every manual Ghostty checklist step passed on 2026-08-28 using Ghostty 1.3.1 on Apple Silicon macOS 26.5.2, including startup/restoration, keyboard and mouse interaction, resize, all four contexts, review conversations, bookmarks, shutdown, and source/Git mutation checks.

Final verification passed with `zig fmt --check src build.zig`, `zig build test --summary all`, and `git diff --check`.
