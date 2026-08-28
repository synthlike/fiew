---
id: ISSUE-0060
title: "Normalize terminal and subprocess behavior"
kind: "implementation"
status: resolved
created: 2026-08-28
assignee: "agent"
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

Implemented portable terminal and subprocess normalization.

Added signal-safe `SIGINT` and `SIGTERM` delivery through a pipe-backed watcher so the terminal loop exits through its normal cleanup path. Normal and handled-signal exits restore Vaxis and TTY state and return conventional signal exit codes. Active Git work is cancelled on shutdown; the bounded direct process runner terminates and reaps its child. Removed implicit Git polling so refresh remains explicit.

Normalized Kitty and conventional VT shortcut translation, including Kitty control-byte text for `Ctrl-C`. Existing libvaxis capability behavior retains keyboard-complete operation without mouse, synchronized updates, or color, and no clipboard, watcher, graphics, multiplexer, shell, or terminal-name path was added.

Added deterministic signal, keyboard, and fallback coverage plus `docs/engineering/v0.2-terminal-smoke-test.md`. The decision owner reported successful Kitty and WezTerm testing; existing Ghostty behavior remains covered by the established smoke baseline.

Verification:
- `zig build test -Dgit-integration=true`
- `zig build`
- `zig build -Dtarget=x86_64-linux-musl -Dcpu=baseline`
- `zig build -Dtarget=aarch64-linux-musl -Dcpu=baseline`
- Pseudo-terminal `SIGINT` shutdown: exit 130 with terminal cleanup completed
- Pseudo-terminal `SIGTERM` shutdown: exit 143 with terminal cleanup completed
- `zig fmt --check src build.zig`
- `git diff --check`

Implementation review verdict: Conforms. The verdict is bounded to ISSUE-0060 and the evidence above; full release-matrix evidence remains part of integrated v0.2 verification.
