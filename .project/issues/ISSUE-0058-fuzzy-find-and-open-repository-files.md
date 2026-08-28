---
id: ISSUE-0058
title: "Fuzzy-find and open repository files"
kind: "implementation"
status: resolved
created: 2026-08-28
assignee: "agent"
parent: "ISSUE-0057-implement-fiew-v0-2.md"
blocked_by:
labels: []
---
# Fuzzy-find and open repository files

## Parent

[fiew v0.2](<docs/specs/fiew-v0-2.md>)

## What to build

Deliver a transient repository-path finder from typed query through preview to a pinned immutable document.

## Acceptance criteria

- [ ] Subsequence ranking favors path-component boundaries and contiguous runs with deterministic ties.
- [ ] Results and matching work remain bounded and responsive at the 10,000-file target.
- [ ] Moving through results previews without changing location history.
- [ ] `Enter` pins one result and adds one origin; `Esc` restores the prior pinned view, selection, and history.
- [ ] Matcher, reducer, and fixed-dimension render tests pass offline without source or Git mutation.

## Blocked by

Managed by native issue relationships.

## Out of scope

Project-wide content search, regular expressions, multi-select, replace, and source mutation.

## Comments
## Resolution

Implemented the transient repository file finder through the command registry (`Space f` and `file-find`). It provides bounded subsequence ranking, typed query and explicit empty/truncation states, selection preview, pin-on-Enter, and cancellation that restores the pinned view without changing history.

Added offline matcher coverage at 10,000 files, reducer coverage for preview/cancel/pin/history transitions, and a fixed-dimension finder RenderPlan snapshot. Updated generated command/help surfaces and README navigation.

Verification:
- `zig build test`
- `zig build`
- `zig build test -Dperformance=true` (10,000-file repository scan completed in approximately 429 ms)
- `zig fmt --check src build.zig`
- `git diff --check`
