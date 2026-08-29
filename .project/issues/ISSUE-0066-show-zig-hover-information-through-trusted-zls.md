---
id: ISSUE-0066
title: "Show Zig hover information through trusted ZLS"
kind: "implementation"
status: resolved
created: 2026-08-28
assignee: "agent"
parent: "ISSUE-0057-implement-fiew-v0-2.md"
blocked_by:
  - "ISSUE-0063-establish-trusted-zls-lifecycle-and-read-only-enforcement.md"
labels: []
---
# Show Zig hover information through trusted ZLS

## Parent

[fiew v0.2](<docs/specs/fiew-v0-2.md>)

## What to build

Deliver `K` from the active Zig selection to bounded, sanitized, scrollable hover documentation and type information.

## Acceptance criteria

- [ ] Hover opens without changing selection or location history and preserves unsupported markup as readable text.
- [ ] Long content scrolls; `Esc`, `q`, navigation, or snapshot replacement dismisses it.
- [ ] A new hover supersedes an older request and stale output never replaces current information.
- [ ] Cancellation, two-second timeout, malformed output, and no-result states are explicit and non-destructive.
- [ ] Transcript, reducer, sanitization, and render tests pass offline.

## Blocked by

Managed by native issue relationships.

## Out of scope

Completion, diagnostics, symbols, rich web rendering, and persistent hover panels.

## Comments
## Resolution

Delivered trusted ZLS hover information through `K`.

Hover requests now advertise Markdown/plaintext support, negotiate the existing UTF-8/UTF-16 position boundary, parse all LSP hover content variants, and bind output to the immutable document, selection, operation, and request generation. New requests cancel and supersede older work. Pending, cancellation, two-second timeout, malformed response, changed document/selection, and no-result states remain explicit and non-destructive.

Hover content is copied into a fiew-owned 64 KiB terminal-safe value. Control bytes are neutralized, CRLF and tabs are normalized, unsupported Markdown remains readable, and truncation is explicit. The bounded overlay scrolls with `j`/`k` or arrows and dismisses on `Esc`, `q`, other navigation, mouse navigation, snapshot replacement, or trust revocation without changing selection or location history.

Added offline protocol transcript, response variant, sanitization, bound, reducer, stale-generation, snapshot-dismissal, scrolling, and render-plan coverage. Updated user-facing ZLS instructions.

Verification:
- `zig build test`
- `zig fmt --check src build.zig`
- `git diff --check`
- `zig build -Dtarget=x86_64-linux-musl -Dcpu=baseline`
- `zig build -Dtarget=aarch64-linux-musl -Dcpu=baseline`
