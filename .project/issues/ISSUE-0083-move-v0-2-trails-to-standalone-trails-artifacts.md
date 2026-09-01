---
id: ISSUE-0083
title: "Move v0.2 Trails to standalone .trails artifacts"
kind: "implementation"
status: open
created: 2026-09-01
assignee: 
parent: "ISSUE-0057-implement-fiew-v0-2.md"
blocked_by:
labels: []
---
# Move v0.2 Trails to standalone .trails artifacts

## Parent

[fiew v0.2](<docs/specs/fiew-v0-2.md>)

## What to build

Move the complete existing Review-local Trail workflow from review companion collections to independent private Trail artifacts under `.trails/` without changing recording, navigation, lifecycle, read-only behavior, or agent visibility.

## Acceptance criteria

- [ ] Every saved Trail uses one bounded `fiew.trail/v1` JSON artifact under `.trails/` with an opaque stable Trail identity and immutable active-Review ownership.
- [ ] Listing loads only Trails owned by the active Review and preserves existing title search, detail, preview, pin, history, recording, composition, re-anchoring, Outdated, unfinished-quit, and confirmed-deletion behavior.
- [ ] Create, metadata save, re-anchor persistence, and deletion affect only the selected Trail artifact and use atomic replacement with one validated previous backup where applicable.
- [ ] Missing, malformed, future-schema, or unrecoverable individual Trail artifacts remain explicit and do not disable unrelated valid Trails, source viewing, or Review state.
- [ ] `.reviews/*.trails` companions are neither read, migrated, diagnosed, nor written.
- [ ] Canonical `fiew.review/v1`, `fiew.bookmark/v1`, Review CLI JSON/Markdown projections, and agent authority remain byte-contract compatible.
- [ ] Offline model, adapter, reducer, recovery, isolation, projection, and fixed-render tests pass without source or Git mutation.

## Blocked by

None.

## Out of scope

Discovery, Spots, agent-proposed Trails, Trail attachments, `fiew.review/v2`, migration of development Trail companions, and changes to Trail interaction or command bindings.

## Comments


## Resolution
