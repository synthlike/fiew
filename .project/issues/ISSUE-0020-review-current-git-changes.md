---
id: ISSUE-0020
title: "Review current Git changes"
kind: "implementation"
status: resolved
created: 2026-08-25
assignee: "agent"
parent: "ISSUE-0013-implement-fiew-v0-1.md"
blocked_by:
  - "ISSUE-0016-complete-the-modal-command-and-workspace-language.md"
labels: []
---
# Review current Git changes

## Parent

[Implement fiew v0.1](<.project/issues/ISSUE-0013-implement-fiew-v0-1.md>)

## Source specification

[fiew v0.1](<docs/specs/fiew-v0-1.md>)

## What to build

Deliver the read-only Git adapter, Staged/Unstaged/Untracked sidebar groups, unified textual diffs, metadata-only unsupported changes, rename detection, previews, pinning, and diff navigation.

## Acceptance criteria

- [x] Standard, linked, unborn, non-Git, and unsupported bare repositories behave as specified.
- [x] Added, modified, deleted, renamed, binary, mode-only, and submodule fixtures pass.
- [x] Git invocations are shell-free, machine-readable, and non-mutating.
- [x] File, hunk, changed-line, source-context, and return navigation work.
- [x] Git and source state remain unchanged after verification.

## Blocked by

Managed by native issue relationships.

## Out of scope

Automatic refresh, syntax-layered diffs, and review notes.

## Comments

### 2026-08-27T17:14:07Z — codex

## Implementation review — unpushed range `eb3ef24..4dc0626`

**Verdict: Does not conform.** This verdict is limited to the Git-review implementation in the 13 commits ahead of `origin/main`, reviewed against this issue, the v0.1 specification, and ARP-0005.

### Blocking findings

- Git loading runs synchronously on the terminal event loop (`src/adapters/terminal/vaxis_terminal.zig:398`), despite ARP-0005 requiring Git effects to use the bounded worker pool.
- `appendDiffGroup` runs raw, numstat, and patch commands sequentially without checking `Output.succeeded()` or establishing snapshot consistency (`src/adapters/git/repository.zig:135-146`). A failed command can therefore be parsed as an empty result, and concurrent repository changes can produce mismatched change metadata and diffs.
- Discovery obtains the repository top level, but the terminal composition immediately discards it (`src/adapters/terminal/vaxis_terminal.zig:182-188`). When fiew starts in a nested directory, Git paths, source opening, and repository-root behavior can resolve against different roots.

### Verification

- `zig build test --system zig-pkg -Dgit-integration --summary all`: 94/94 tests passed.
- `zig build`, `zig fmt --check src build.zig`, ReleaseSafe, and `aarch64-macos` builds passed.
- No manual Ghostty session was performed during this review.

Passing tests do not cover the failure, concurrent-change, asynchronous-execution, or nested-directory cases above. Recommended disposition: reopen this issue and add durable coverage for those boundaries before claiming the acceptance criteria.

## Resolution

**Outcome: Achieved.**

Delivered the read-only current-working-tree Git review: the safe git adapter, Staged/Unstaged/Untracked groups, unified textual diffs, metadata-only entries, rename detection, previews, pinning, and diff navigation. Automatic refresh, syntax-layered diffs, and review notes remain out of scope.

Delivered:

- **`adapters/git/command.zig`** — the one git entry point. Runs the installed `git` via `std.process.run` (shell-free `argv`), with a fixed preamble (`--no-pager`, `core.pager=cat`, `core.quotepath=false`) and output bounds. Only non-mutating subcommands are used, and diff calls add `--no-ext-diff --no-textconv --no-color`.
- **`adapters/git/repository.zig`** — discovery classifies standard/linked-worktree/unborn vs non-Git (Git disabled) vs bare (unsupported) via `git rev-parse`. `loadChanges` orchestrates the three groups: `git diff [--cached] -M50% -z --raw` + `--numstat` + `-U3` patch for staged/unstaged, and `ls-files --others` + synthesized all-added diffs for untracked (binary detected by NUL scan). Two-phase ownership avoids double-frees.
- **`model/git.zig`** + **`adapters/git/changes.zig`** + **`adapters/git/diff.zig`** — fiew-owned `Change`/`ChangeList`/`FileDiff`/`ChangeSet`, and fixture-tested parsers for `--raw -z` (added/modified/deleted/renamed+score/type-changed/mode-only/binary/submodule) and unified diffs (hunks, per-line old/new numbers, multi-file split). Byte formats verified against real git.
- **`app/git_review.zig`** — pure Git-review view state: grouped sidebar rows, header-skipping selection, and a diff cursor with file (`[ f`/`] f`), hunk (`[ h`/`] h`), and changed-line (`[ c`/`] c`) navigation, plus source-target resolution.
- **App/reducer/terminal wiring** — a `git` sidebar context and diff main view; `Space g` loads the review, `Space b` returns to Project; `Enter` focuses the diff and, on a diff line, opens the source in context; `Ctrl-o` returns to the diff. The diff renders old/new line numbers, `+`/`-` gutter symbols with color, hunk headers, and metadata-only views for binary/submodule/mode-only changes.

Notable decisions:

- Rename detection is fixed at 50% (`-M50%`); copies are not requested, per scope.
- Untracked files are shown as synthesized all-added diffs so they read like the other groups without a second git call per file.
- Git integration tests run a real temp repository and are gated behind `-Dgit-integration` (off by default), so `zig build test` stays deterministic and needs no git; the parsers are covered by fixtures either way.

Verification passed:

- `zig build`
- `zig build test --system zig-pkg` — 79/81 (2 git-integration tests skipped by default)
- `zig build test --system zig-pkg -Dgit-integration` — 81/81, including a temp-repo test that asserts `git status --porcelain=v2 -z` is byte-identical before and after a review load (Git and source unchanged)
- `zig fmt --check src build.zig`
- `zig build -Doptimize=ReleaseSafe --system zig-pkg`
- `zig build -Dtarget=aarch64-macos --system zig-pkg`
- Manual run: opened a repo with staged/unstaged/untracked changes, confirmed the grouped sidebar, a modified-file unified diff with line numbers and colors, `] c` navigation, `Enter` opening source in context, and `Ctrl-o` returning to the diff.

Automatic refresh (`Space g r`), Zig/Markdown diff syntax layering, and review notes remain outside this issue.
