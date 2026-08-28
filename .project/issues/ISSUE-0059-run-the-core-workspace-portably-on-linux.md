---
id: ISSUE-0059
title: "Run the core workspace portably on Linux"
kind: "implementation"
status: resolved
created: 2026-08-28
assignee: "agent"
parent: "ISSUE-0057-implement-fiew-v0-2.md"
blocked_by:
labels: []
---
# Run the core workspace portably on Linux

## Parent

[fiew v0.2](<docs/specs/fiew-v0-2.md>)

## What to build

Deliver startup, repository browsing, explicit document reload, and global state behavior on macOS and Linux.

## Acceptance criteria

- [ ] Baseline x86_64-linux-musl and aarch64-linux-musl builds compile with the locked Zig dependencies.
- [ ] Vendored Tree-sitter compiles correctly for Linux without weakening macOS behavior.
- [ ] Linux uses `XDG_STATE_HOME/fiew` with the specified `$HOME/.local/state/fiew` fallback.
- [ ] Unavailable global persistence leaves repository browsing and review usable with an explicit diagnostic.
- [ ] Explicit reload safely handles changed, deleted, replaced, and unreadable files while retaining the last valid snapshot until replacement succeeds.
- [ ] Native Linux deterministic tests pass.

## Blocked by

Managed by native issue relationships.

## Out of scope

Release packaging, terminal-matrix certification, filesystem watchers, and optional ZLS or Mermaid behavior.

## Comments
## Resolution

Delivered the portable core workspace boundary for macOS and Linux.

Added the POSIX/default feature macros required to compile vendored Tree-sitter for baseline x86_64-linux-musl and aarch64-linux-musl. Added a `test-binaries` build step so cross-built deterministic test executables can run in a native target environment. Both Linux executables are static ELF binaries; the ARM64 Linux core and executable test suites passed in an Alpine Linux container (140 passed with 9 opt-in skips, plus 8 executable tests).

Global state now resolves to `$HOME/Library/Application Support/fiew` on macOS and `$XDG_STATE_HOME/fiew` on Linux, with `$HOME/.local/state/fiew` fallback. Missing or invalid absolute environment paths and directory-open failures continue with an explicit persistence-disabled diagnostic.

Added `Space f r` / `file-reload` under the Files command namespace. Reload fully reads and validates a replacement snapshot before atomically publishing it while preserving source position and scroll. Load failures report the exact error and retain the previous immutable view and history.

Verification:
- `zig build`
- `zig build test`
- `zig build -Dtarget=x86_64-linux-musl -Dcpu=baseline` (static x86-64 ELF)
- `zig build -Dtarget=aarch64-linux-musl -Dcpu=baseline` (static ARM aarch64 ELF)
- ARM64 Linux `fiew-core-tests`: 140 passed, 9 opt-in skipped
- ARM64 Linux `fiew-executable-tests`: 8 passed
- ARM64 Linux `fiew --version` runtime smoke passed
- `zig fmt --check src build.zig`
- `git diff --check`
