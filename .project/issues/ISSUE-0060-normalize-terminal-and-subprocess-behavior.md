---
id: ISSUE-0060
title: "Normalize terminal and subprocess behavior"
kind: "implementation"
status: open
created: 2026-08-28
assignee:
parent: "ISSUE-0057-implement-fiew-v0-2.md"
blocked_by:
  - "ISSUE-0059-run-the-core-workspace-portably-on-linux.md"
labels: []
---
# Normalize terminal and subprocess behavior

## Parent

[fiew v0.2](<docs/specs/fiew-v0-2.md>)

## What to build

Deliver equivalent core interaction, capability fallback, terminal restoration, and child-process cleanup across supported operating systems.

## Acceptance criteria

- [ ] Normal exit and handled `SIGINT` and `SIGTERM` restore terminal state.
- [ ] Child tools launch without a shell and are bounded, cancellable, terminated, and reaped.
- [ ] Core keyboard workflows operate with Kitty keyboard input and conventional VT fallback.
- [ ] Missing mouse, synchronized output, or true color degrades without disabling keyboard-complete workflows.
- [ ] No application clipboard, watcher, graphics, multiplexer, or terminal-name branch is introduced.
- [ ] Deterministic fallback tests and the portable smoke procedure pass.

## Blocked by

Managed by native issue relationships.

## Out of scope

Guaranteed `SIGKILL` recovery, shell job control, background operation, and `Ctrl-Z` suspend/resume.

## Comments

## Resolution
