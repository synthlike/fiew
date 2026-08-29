---
id: ISSUE-0073
title: "Record and revisit review-local Trails"
kind: "implementation"
status: resolved
created: 2026-08-29
assignee: "agent"
parent: "ISSUE-0057-implement-fiew-v0-2.md"
blocked_by:
labels: []
---
# Record and revisit review-local Trails

## Parent

[fiew v0.2](<docs/specs/fiew-v0-2.md>)

## What to build

Provide the complete manual Trail workflow for an active review: record ordered repository locations, compose metadata, persist safely, revisit points, navigate without preview-history noise, delete with confirmation, and conservatively re-anchor changed locations.

Persist Trails according to [Store Trails as review-keyed private companion records](<docs/decisions/ARP-0011.md>).

## Acceptance criteria

- [ ] `Space t`, `Space t r`, and `Space t a` implement the agreed list, toggle, and manual-point behavior with active-review, repository-location, External, and minimum-point guards.
- [ ] Stop opens title/note composition; cancel resumes recording; save creates a review-keyed `fiew.trail/v1` companion without changing review/bookmark schemas or agent projections.
- [ ] Saved Trails list by active review, expose ordered `file:line:content` points, preview with `j`/`k`, pin with `Enter`, and delete only after confirmation.
- [ ] Points uniquely re-anchor through exact context or become **Outdated** while retaining captured content.
- [ ] Malformed or future storage, persistence failure, deleted files, invalid points, and unfinished quit state remain explicit and non-destructive.
- [ ] Offline model, store, reducer, command, render, re-anchoring, recovery, and projection-isolation tests pass.

## Blocked by

None.

## Out of scope

Automatic capture, External points, one-point Trails, metadata editing, point reordering or deletion, comment printing, and global Trails.

## Comments
## Resolution

Delivered the complete review-local manual Trail workflow.

Added the private `fiew.trail/v1` model and review-keyed `.reviews/<review>.trails` companion store with validation, atomic replacement, validated backup recovery, future-schema refusal, and isolation from canonical review and bookmark data. Active-review startup reports malformed, future, and unrecoverable state without impairing source viewing.

`Space t` now opens saved Trails, `Space t r` starts or stops recording, and `Space t a` appends a manual point. Recording rejects absent reviews, External and non-source views, binary or invalid text, and stops with fewer than two points. The bounded title/note composer resumes recording on cancel and leaves failed persistence dirty in memory.

Saved Trails expose ordered `file:line:content` points. `j`/`k` previews without history changes, `Enter` pins one point, and deletion requires confirmation. Exact contextual anchors retain or uniquely relocate points; missing, changed, ambiguous, and deleted locations become **Outdated** while captured path, line, and content remain available.

Added offline model, storage, recovery, projection-isolation, reducer, command, re-anchoring, quit-warning, and fixed-dimension render-plan coverage.

Verification:
- `zig build test`
- `zig build`
- `zig fmt` on changed Zig files
- `git diff --check`
