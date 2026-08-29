---
id: ISSUE-0065
title: "Find Zig references through trusted ZLS"
kind: "implementation"
status: resolved
created: 2026-08-28
assignee: "agent"
parent: "ISSUE-0057-implement-fiew-v0-2.md"
blocked_by:
  - "ISSUE-0064-navigate-to-zig-definitions-through-trusted-zls.md"
labels: []
---
# Find Zig references through trusted ZLS

## Parent

[fiew v0.2](<docs/specs/fiew-v0-2.md>)

## What to build

Deliver `g r` from the active Zig selection through bounded, validated ZLS results to grouped preview and pinned navigation.

## Acceptance criteria

- [ ] References are grouped by file and ordered by repository path then source position.
- [ ] The declaration is included only when ZLS returns it; invalid locations are omitted.
- [ ] Preview, pin, dismissal, history, and **External** behavior match definition navigation.
- [ ] At most 5,000 results display and truncation is explicit.
- [ ] Cancellation, five-second timeout, stale results, malformed responses, and no valid results preserve current state.
- [ ] Transcript, reducer, and render tests pass offline.

## Blocked by

Managed by native issue relationships.

## Out of scope

Call hierarchy, workspace symbols, diagnostics, and semantic re-anchoring.

## Comments
## Resolution

Delivered trusted ZLS reference navigation through `g r`.

Reference requests now advertise and send the read-only LSP references capability with ZLS-controlled declaration inclusion. Results pass through the existing canonical file-location validation, immutable position mapping, External handling, preview, pin, dismissal, and history behavior. Valid references are deduplicated, sorted by displayed path and source position, visibly grouped by file, capped at 5,000 rows, and marked explicitly when truncated.

Reference work is bound to the request document, selection, operation, and generation. It shows pending state after 100 milliseconds, requests cancellation, times out after five seconds, and rejects stale, malformed, failed, or empty valid result sets without replacing the current view or history.

Added offline protocol, command-registry, grouping, ordering, bound, truncation, and render coverage while retaining the existing semantic-navigation reducer and validation coverage.

Verification:
- `zig build test`
- `zig build -Dtarget=x86_64-linux-musl -Dcpu=baseline`
- `zig build -Dtarget=aarch64-linux-musl -Dcpu=baseline`
- `zig fmt --check src build.zig`
- `git diff --check`
