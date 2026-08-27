---
id: ISSUE-0021
title: "Harden and refresh current Git review snapshots"
kind: "implementation"
status: open
created: 2026-08-25
assignee: 
parent: "ISSUE-0013-implement-fiew-v0-1.md"
blocked_by:
  - "ISSUE-0018-add-zig-syntax-folding-and-structural-navigation.md"
  - "ISSUE-0020-review-current-git-changes.md"
labels: []
---
# Harden and refresh current Git review snapshots

## Parent

[Implement fiew v0.1](<.project/issues/ISSUE-0013-implement-fiew-v0-1.md>)

## Source specification

[fiew v0.1](<docs/specs/fiew-v0-1.md>)

## What to build

Make the Git-backed VCS view load and refresh complete repository-rooted snapshots without blocking terminal interaction or publishing partial, failed, or mutually inconsistent command results.

This slice incorporates the unresolved conformance findings recorded on [Review current Git changes](<.project/issues/ISSUE-0020-review-current-git-changes.md>): run Git work through the bounded asynchronous effect path, preserve the discovered repository top level, check every command result, and detect a repository change across the commands composing one snapshot.

## Acceptance criteria

- [ ] Git loading and refresh never block the terminal event loop.
- [ ] Starting in a nested directory retains one repository-root identity for Git paths, source opening, reviews, and bookmarks.
- [ ] Every Git command's nonzero exit, signal, timeout, and output-limit failure becomes an explicit typed failure rather than an empty change set.
- [ ] Raw metadata, numstat, patches, and untracked contents publish only when they describe one consistent repository state; one bounded retry handles a changing fingerprint.
- [ ] Debounced filesystem changes and the VCS refresh command retain the previous complete snapshot until replacement succeeds.
- [ ] Failed refresh marks the previous snapshot stale; obsolete work is cancelled or rejected by generation.
- [ ] `Space v` opens the VCS context, identifies Git as the active backend, and its refresh action has a visible disabled or pending state.
- [ ] Fixtures and opt-in Git integration tests cover nested roots, command failure, concurrent change, cancellation, and source/Git non-mutation.

## Blocked by

Managed by native issue relationships.

## Out of scope

Markdown syntax layering, non-Git VCS backends, review threads, and bookmarks.

## Comments

## Resolution
