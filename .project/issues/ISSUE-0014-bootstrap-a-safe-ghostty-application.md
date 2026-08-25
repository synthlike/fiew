---
id: ISSUE-0014
title: "Bootstrap a safe Ghostty application"
kind: "implementation"
status: resolved
created: 2026-08-25
assignee: "agent"
parent: "ISSUE-0013-implement-fiew-v0-1.md"
blocked_by:
labels: []
---
# Bootstrap a safe Ghostty application

## Parent

[Implement fiew v0.1](<.project/issues/ISSUE-0013-implement-fiew-v0-1.md>)

## Source specification

[fiew v0.1](<docs/specs/fiew-v0-1.md>)

## What to build

Create a Zig 0.16 executable using pinned low-level libvaxis that enters the terminal UI, renders a welcome view, handles resize, and restores the terminal on every exit path.

## Acceptance criteria

- [ ] `zig build`, `zig build test`, and formatting checks pass.
- [ ] Ghostty displays the welcome view and processes resize events.
- [ ] Normal exit, error exit, and interruption restore terminal state.
- [ ] Tests require neither network access nor optional executables.

## Blocked by

Managed by native issue relationships.

## Out of scope

Repository browsing and feature integrations.

## Comments
## Resolution

**Outcome: Achieved.**

Delivered a Zig 0.16.0 executable using low-level libvaxis pinned to `c060d314930c5552b99a89278a6a695baf0352da`. The application enters the alternate screen, renders a centered welcome view, redraws after resize events, accepts `q` and `Ctrl-C`, and restores terminal state through ordered cleanup on normal and error returns.

Verification passed:

- `zig build`
- `zig build test --system zig-pkg`
- `zig fmt --check src build.zig`
- ReleaseSafe and explicit `aarch64-macos` builds
- Manual Ghostty checks for welcome rendering, resize behavior, `q`, `Ctrl-C`, and terminal restoration

Tests use no optional executables. The network-disabled system package build passed after dependencies were fetched. Repository browsing remains out of scope for this issue.
