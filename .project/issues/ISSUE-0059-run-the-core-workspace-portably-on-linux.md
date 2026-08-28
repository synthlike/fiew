---
id: ISSUE-0059
title: "Run the core workspace portably on Linux"
kind: "implementation"
status: open
created: 2026-08-28
assignee:
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
