---
id: ISSUE-0058
title: "Fuzzy-find and open repository files"
kind: "implementation"
status: open
created: 2026-08-28
assignee:
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
