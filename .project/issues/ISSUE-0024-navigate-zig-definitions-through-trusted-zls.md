---
id: ISSUE-0024
title: "Navigate Zig through trusted ZLS"
kind: "implementation"
status: cancelled
created: 2026-08-25
assignee: 
parent: "ISSUE-0052-hold-deferred-fiew-v0-2-implementation-candidates.md"
blocked_by:
  - "ISSUE-0016-complete-the-modal-command-and-workspace-language.md"
  - "ISSUE-0017-establish-recoverable-fiew-owned-state.md"
labels: []
---
# Navigate Zig through trusted ZLS

## Parent

[Hold deferred fiew v0.2 implementation candidates](<.project/issues/ISSUE-0052-hold-deferred-fiew-v0-2-implementation-candidates.md>)

## Planning status

Deferred from v0.1 and expanded for v0.2. This candidate slice must be reconciled with the v0.2 interaction decision and specification before implementation.

## What to build

Deliver repository trust, ZLS version validation and lifecycle, go-to-definition, find references, hover documentation and type information, position mapping, result previews, External views where allowed, cancellation, timeout, and strict read-only protocol enforcement.

## Acceptance criteria

- [ ] ZLS never launches before explicit repository trust.
- [ ] Definition navigation, reference results, hover content, and history return work with transcript and opt-in integration tests.
- [ ] Stale, late, malformed, cancelled, and timed-out responses never navigate or replace current information.
- [ ] Multiple definitions and references use the accepted v0.2 result interaction; hover is dismissible and preserves selection/history.
- [ ] Workspace edits, formatting, rename, code actions, file operations, and server commands are refused.
- [ ] Missing, incompatible, or crashed ZLS preserves Tree-sitter and plain-text behavior.
- [ ] Shutdown, restart, and trust revocation cleanly stop the process.

## Blocked by

Managed by native issue relationships.

## Out of scope

Other languages, source-writing LSP methods, and a generic language-server framework.

## Comments
## Resolution

Cancelled as a deferred candidate after approval of the v0.2 specification and executable plan. Its scope is replaced by vertical slices under [Implement fiew v0.2](<.project/issues/ISSUE-0057-implement-fiew-v0-2.md>); this cancellation does not abandon the approved product behavior.
