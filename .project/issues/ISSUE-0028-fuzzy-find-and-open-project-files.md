---
id: ISSUE-0028
title: "Fuzzy-find and open project files"
kind: "implementation"
status: open
created: 2026-08-27
assignee: 
parent: "ISSUE-0013-implement-fiew-v0-1.md"
blocked_by:
labels: []
---
# Fuzzy-find and open project files

## Parent

[Implement fiew v0.1](<.project/issues/ISSUE-0013-implement-fiew-v0-1.md>)

## Source specification

[fiew v0.1](<docs/specs/fiew-v0-1.md>)

## What to build

Replace the placeholder `Space f` file-commands submenu with a transient fuzzy file finder: an overlay that filters the repository's tracked files by a typed query, ranks the matches, and opens (pins) the selected file. It reuses the named-command prompt interaction — a query input, `Up`/`Down` selection, and `Enter` to act — applied to file paths.

This is a file-name navigation utility (an accepted extension of file browsing), distinct from the excluded project-wide content search.

## Acceptance criteria

- [ ] `Space f` opens a fuzzy file overlay listing repository files; `Esc` cancels and restores the prior view.
- [ ] Typing filters and ranks by subsequence match that favors boundary starts and contiguous runs; `Up`/`Down` move the selection and results stay bounded.
- [ ] `Enter` opens and pins the selected file, focuses the main view, and adds a history location.
- [ ] The matcher is pure and unit-tested, and remains responsive at the 10,000-file target.
- [ ] No source file or Git state is modified.

## Blocked by

Managed by native issue relationships. Sequenced after [Create and manage local review notes](<.project/issues/ISSUE-0022-create-and-manage-local-review-notes.md>) by preference, not technical dependency.

## Out of scope

Project-wide content search, regular expressions, and multi-select. This finds files by path only.

## Comments

## Resolution
