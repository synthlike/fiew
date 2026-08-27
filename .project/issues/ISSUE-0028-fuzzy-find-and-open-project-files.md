---
id: ISSUE-0028
title: "Fuzzy-find and open project files"
kind: "implementation"
status: open
created: 2026-08-27
assignee: 
parent: "ISSUE-0052-hold-deferred-fiew-v0-2-implementation-candidates.md"
blocked_by:
labels: []
---
# Fuzzy-find and open project files

## Parent

[Hold deferred fiew v0.2 implementation candidates](<.project/issues/ISSUE-0052-hold-deferred-fiew-v0-2-implementation-candidates.md>)

## Planning status

Deferred from v0.1. This is a candidate v0.2 implementation slice and must be reconciled with the eventual v0.2 specification before implementation.

## What to build

Add a transient fuzzy file finder that filters repository files by typed path query, ranks matches, and opens the selected file without expanding into project-wide content search.

## Acceptance criteria

- [ ] The accepted command opens a fuzzy file overlay; `Esc` restores the prior view.
- [ ] Typing filters and ranks by subsequence match favoring boundary starts and contiguous runs.
- [ ] `Enter` opens and pins the selected file, focuses the main view, and adds a history location.
- [ ] Results stay bounded and the pure matcher remains responsive at the 10,000-file target.
- [ ] No source file or Git state is modified.

## Blocked by

Managed by native issue relationships.

## Out of scope

Project-wide content search, regular expressions, and multi-select.

## Comments

## Resolution
