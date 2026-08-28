---
id: ISSUE-0069
title: "Distinguish all-file and Git-visible finders"
kind: "implementation"
status: resolved
created: 2026-08-28
assignee: "agent"
parent: "ISSUE-0057-implement-fiew-v0-2.md"
blocked_by:
labels: []
---
# Distinguish all-file and Git-visible finders

## Parent

[Implement fiew v0.2](<.project/issues/ISSUE-0057-implement-fiew-v0-2.md>)

## What to build

Split repository path finding into an all-files action and a Git-visible action so reviewers can deliberately include ignored files or restrict results to tracked and non-ignored untracked files.

## Acceptance criteria

- [ ] `Space f` opens a Files menu; `Space f a` opens all filesystem files except `.git`; `Space f g` opens Git-visible files.
- [ ] Git-visible candidates come from bounded, shell-free `git ls-files --cached --others --exclude-standard -z` output.
- [ ] The Git-visible action is disabled outside a usable Git repository and does not silently fall back.
- [ ] The Project tree remains unchanged, and both finder modes preserve preview, pin, cancellation, history, and read-only behavior.
- [ ] Named commands, generated help, parser/adapter tests, reducer tests, and offline deterministic tests cover both modes.

## Blocked by

None.

## Out of scope

Generic VCS support, external `fd` integration, content search, ignore configuration, and changes to the Project tree.

## Comments
## Resolution

Implemented a Files command namespace with `Space f a` for all repository filesystem files and `Space f g` for Git-visible files. The Git-visible action uses the existing bounded, shell-free Git command adapter to run `git ls-files --cached --others --exclude-standard -z`, rejects malformed or oversized path sets, and remains disabled outside usable Git repositories without fallback.

The finder now owns a transient candidate filter while the Project tree remains unchanged. Both scopes retain the existing preview, pin, cancellation, history, bounded ranking, and read-only behavior. Added offline parser and filtering tests, reducer coverage for both command paths, and an opt-in real-Git test covering tracked, eligible untracked, and ignored files. Updated generated command/help surfaces and README bindings.

Verification:
- `zig build`
- `zig build test`
- `zig build test -Dgit-integration=true`
- `zig build test -Dperformance=true` (10,000-file repository scan completed in approximately 427 ms)
- `zig fmt --check src build.zig`
- `git diff --check`
