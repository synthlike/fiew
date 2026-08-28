---
id: ISSUE-0071
title: "Show continuation hints for pending key sequences"
kind: "implementation"
status: resolved
created: 2026-08-28
assignee: "agent"
parent:
blocked_by:
labels: []
---
# Show continuation hints for pending key sequences

## Parent

The modal command behavior defined by the fiew v0.1 specification and retained by fiew v0.2.

## What to build

When a reviewer presses an actionable non-leader prefix, show a compact continuation surface listing the valid next keys and command names until the sequence completes or closes.

## Acceptance criteria

- [ ] `g` shows document start, document end, and definition continuations.
- [ ] `z` shows close, open, toggle, close-all, and open-all fold continuations with case-sensitive keys.
- [ ] `]` and `[` show file, hunk, changed-line, thread, and bookmark navigation continuations.
- [ ] Continuation hints derive from the command registry and keep unavailable commands visible with their disabled reason.
- [ ] Pending hints remain visible for approximately two seconds without input.
- [ ] Completion, `Esc`, invalid input, and timeout close the continuation surface without changing command dispatch behavior.
- [ ] Pure command and fixed render tests cover every pending prefix and unavailable-command presentation.

## Blocked by

None.

## Out of scope

Changing bindings, leader behavior, named-command search, or adding configurable keymaps.

## Comments
## Resolution

Implemented registry-backed continuation surfaces for every existing non-leader pending prefix. Pressing `g`, `z`, `]`, or `[` now opens a bottom hint panel whose keys come from registered bindings, whose concise labels live in the same command definitions, and whose unavailable commands remain visible with their exact disabled reason. Pending sequences remain visible for approximately two seconds and still close on completion, cancellation, invalid input, or timeout.

Verification passed:

- `zig build test`
- `zig build -Dtarget=x86_64-linux-musl`
- `zig build -Dtarget=aarch64-linux-musl`

Pure command tests cover registry-derived continuation discovery, the two-second timeout, and closure behavior. Fixed row snapshots cover all four prefixes, case-sensitive fold keys, and disabled-reason presentation.
