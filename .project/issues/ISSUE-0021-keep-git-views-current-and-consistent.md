---
id: ISSUE-0021
title: "Harden and refresh current Git review snapshots"
kind: "implementation"
status: resolved
created: 2026-08-25
assignee: "agent"
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

### 2026-08-27T21:34:02Z — agent

## Post-resolution regression: VCS selection reset after review save

A reviewer reported that saving a review comment returned the VCS view to the first Unstaged file after about one second.

Root cause:

- `.reviews/` is untracked in the current workspace, so saving a comment changes the Git fingerprint.
- The one-second poll correctly requests a replacement snapshot.
- `App.openReview` replaced the prior `git_review.Review` with a newly initialized value, which selected the first changed row and discarded the prior VCS selection and scroll.

This conflicts with the specification requirement that each sidebar context preserve its selection and scroll position.

A regression check in `src/app/state.zig` reproduced the defect before repair:

```text
expected: b.zig
found:    a.zig
```

The repair carries VCS position into a replacement snapshot by matching the prior Git group and repository-relative path, preserving sidebar scroll and bounded diff cursor position when that change remains. If it no longer exists, normal first-change fallback remains.

Verification after repair:

- `zig build test --system zig-pkg -Dgit-integration --summary all` — 101/101 tests passed
- build, formatting, ReleaseSafe, Apple Silicon macOS target, and `git diff --check` passed

The adapter does not support reopening a resolved issue, so this comment records the corrected implementation and evidence without directly editing issue status.

### 2026-08-27T21:37:06Z — agent

## Post-resolution regression: refresh moved focus from diff to VCS sidebar

The selection-preservation repair exposed a second refresh-state loss: publishing a replacement snapshot unconditionally set `App.focus` to `sidebar`, moving focus away from the active diff.

The existing refresh regression check was extended to place focus on the main diff before replacement. Before repair it failed with:

```text
expected .main, found .sidebar
```

`App.openReview` now distinguishes initial installation from snapshot replacement. Initial VCS opening still selects the Git sidebar. Replacement preserves the active sidebar context and focus while updating snapshot status and navigation state.

Verification passed, including `zig build test --system zig-pkg -Dgit-integration --summary all` with 101/101 tests.

### 2026-08-27T21:48:04Z — agent

## Focus regression correction: automatic refresh start changed focus

The prior focus repair covered snapshot publication but did not cover the full production sequence. The reported keys established that focus moved before publication, when the one-second fingerprint poll called `App.beginGitRefresh`.

`beginGitRefresh` unconditionally called `showGitSidebar`, which changed focus from the diff to the sidebar as soon as an automatic refresh became pending. The regression check now executes the refresh-begin transition before replacement and reproduced the production failure (`expected .main, found .sidebar`).

The repair separates requesting a refresh from opening the VCS context:

- `beginGitRefresh` changes only generation, pending status, and feedback;
- the explicit `Space v` command remains responsible for opening and focusing the Git sidebar;
- automatic and named refreshes preserve the current context and focus throughout request and publication.

Verification passed, including 101/101 integration-enabled tests and all build, format, ReleaseSafe, and Apple Silicon macOS checks.

## Resolution

**Outcome: Achieved.**

Delivered repository-rooted, asynchronous Git snapshot loading and refresh:

- Git work now runs in one bounded background slot and returns generation-tagged completions. Obsolete completions cannot publish.
- Discovery promotes a nested starting directory to the canonical worktree top level used by Project, Git, source loading, and review storage.
- Checked Git invocations map nonzero exits, signals, timeouts, and output-limit failures to typed failures.
- Complete snapshots are bracketed by content-sensitive fingerprints. A changed fingerprint discards the candidate and retries once.
- One-second fingerprint polling debounces external changes into refreshes. Manual `Space v r` refresh and automatic refresh retain the previous snapshot until success; failures mark it stale.
- `Space v` opens the VCS context, identifies Git, and exposes visible loading, pending, stale, and refresh states. Project moved to the specified `Space p` namespace.

Verification passed:

- `zig build --system zig-pkg`
- `zig build test --system zig-pkg`
- `zig build test --system zig-pkg -Dgit-integration` — 100/100 tests
- `zig fmt --check src build.zig`
- `zig build -Doptimize=ReleaseSafe --system zig-pkg`
- `zig build -Dtarget=aarch64-macos --system zig-pkg`
- `git diff --check`

Integration coverage includes nested-root identity, nonzero command failure, tracked and untracked fingerprint changes, one bounded concurrent-change retry, and source/Git non-mutation. Generation rejection has deterministic unit coverage. No manual Ghostty session was performed.
