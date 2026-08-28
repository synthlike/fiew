---
id: ISSUE-0065
title: "Find Zig references through trusted ZLS"
kind: "implementation"
status: open
created: 2026-08-28
assignee:
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
