---
id: ISSUE-0014
title: "Bootstrap a safe Ghostty application"
kind: "implementation"
status: open
created: 2026-08-25
assignee: 
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
