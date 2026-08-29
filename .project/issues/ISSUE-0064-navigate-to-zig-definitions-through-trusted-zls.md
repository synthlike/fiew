---
id: ISSUE-0064
title: "Navigate to Zig definitions through trusted ZLS"
kind: "implementation"
status: resolved
created: 2026-08-28
assignee: "agent"
parent: "ISSUE-0057-implement-fiew-v0-2.md"
blocked_by:
  - "ISSUE-0063-establish-trusted-zls-lifecycle-and-read-only-enforcement.md"
labels: []
---
# Navigate to Zig definitions through trusted ZLS

## Parent

[fiew v0.2](<docs/specs/fiew-v0-2.md>)

## What to build

Deliver `g d` from the active Zig selection through validated ZLS results to immediate or selected read-only navigation.

## Acceptance criteria

- [ ] One valid result opens directly and multiple valid results use a transient path, line, and source-preview list.
- [ ] Validated outside-repository files open read-only with an **External** label.
- [ ] Preview movement does not affect history; pinning adds exactly one origin and `Ctrl-o`/`Ctrl-i` traverse it.
- [ ] Cancellation, two-second timeout, stale generations, malformed responses, and invalid locations preserve selection, view, and history.
- [ ] No-result and exact unavailable ZLS states are explicit, with no heuristic navigation fallback.
- [ ] Transcript, reducer, and render tests pass offline.

## Blocked by

Managed by native issue relationships.

## Out of scope

References, hover, diagnostics, symbols, and source-writing LSP capabilities.

## Comments
## Resolution

Delivered read-only Zig definition navigation through trusted ZLS.

`g d` now binds a request to the repository, immutable document generation, selection, operation, and owner generation. The request negotiates UTF-8 or UTF-16, opens the immutable snapshot, sends `textDocument/definition`, supports Location and LocationLink responses, requests cancellation, and enforces a two-second wall-clock deadline. Late, changed-document, changed-selection, malformed, failed, and cancelled work cannot navigate.

Validated canonical `file:` targets omit unsupported schemes, nonexistent files, directories, invalid ranges, invalid boundaries, and duplicates. One valid result pins immediately. Multiple results show path, line, source preview, selection, and External state without changing history during preview. Enter records the origin and destination; cancellation restores pinned or unpinned origin state. External files remain read-only and outside Project and Git membership.

Added offline framing, response, URI, target-validation, reducer, history, render-label, exact-status, stale-state, and External coverage. Live ZLS 0.16.0 smoke verification resolved both an in-repository definition and an External Zig standard-library definition.

Verification:
- `zig build test`
- `zig build -Dtarget=x86_64-linux-musl -Dcpu=baseline`
- `zig build -Dtarget=aarch64-linux-musl -Dcpu=baseline`
- `zig fmt --check src build.zig`
- `git diff --check`
- Live ZLS 0.16.0 internal and External definition smoke
