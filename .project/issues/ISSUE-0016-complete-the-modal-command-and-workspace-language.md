---
id: ISSUE-0016
title: "Complete the modal command and workspace language"
kind: "implementation"
status: resolved
created: 2026-08-25
assignee: "agent"
parent: "ISSUE-0013-implement-fiew-v0-1.md"
blocked_by:
  - "ISSUE-0015-browse-repository-files-as-immutable-documents.md"
labels: []
---
# Complete the modal command and workspace language

## Parent

[Implement fiew v0.1](<.project/issues/ISSUE-0013-implement-fiew-v0-1.md>)

## Source specification

[fiew v0.1](<docs/specs/fiew-v0-1.md>)

## What to build

Deliver Normal, Extend, and Command interaction; complete movement and selection bindings; the command registry, leader and command surfaces, generated help, focus cycling, status feedback, and location history.

## Acceptance criteria

- [ ] All specified bindings dispatch through one typed command registry.
- [ ] Unavailable commands display stable disabled reasons.
- [ ] Invalid and pending key sequences plus `Esc` behave deterministically.
- [ ] RenderPlan snapshots cover wide, overlay, and unsupported-size workspaces.
- [ ] Reducer tests cover selection, preview, focus, and history transitions.

## Blocked by

Managed by native issue relationships.

## Out of scope

Tree-sitter, Git, LSP, review-note, and Mermaid adapters.

## Comments
## Resolution

**Outcome: Achieved.**

Delivered the selection-first Normal, Extend, and Command interaction model through one typed command registry with stable identifiers. The registry drives character, word, vertical, page, document-boundary, selection, focus, Project, history, leader, help, named-command, cancellation, transient-close, and explicit quit behavior. Future Tree-sitter, Git, Review, ZLS, and note commands remain visible with stable disabled reasons.

The reducer now owns deterministic pending sequences and timeout feedback. `Esc` cancels surfaces and pending input without changing selection, or leaves Extend mode by collapsing to its active end. `q` closes transient views rather than quitting; `Space q`, `:quit`, and the interruption shortcut provide explicit exit paths.

Pinned and preview views preserve independent selections and scroll positions. Pinning records source locations, and `Ctrl-o`/`Ctrl-i` reload backward and forward history. Vertical, document-start, and document-end movement preserve the preferred visual column. Mouse press and drag replace or extend the contiguous grapheme-safe selection.

Added a pure fiew-owned RenderPlan projection with fixed snapshots for wide, overlay, and unsupported dimensions. Generated leader, command-search, and scrollable help surfaces derive labels, bindings, and disabled state from the registry. Region headers communicate focus; the status line shows mode, pending keys, active line/visual column, and feedback.

Verification passed:

- `zig build`
- `zig build test --system zig-pkg` — 29/29 tests
- `zig fmt --check src build.zig`
- ReleaseSafe and explicit `aarch64-macos` builds
- Reducer tests for selection, mode, sequences, timeout, focus, preview restoration, history, registry coverage, disabled reasons, and command surfaces
- RenderPlan snapshots for wide, overlay, and unsupported workspaces
- Manual Ghostty review of modal movement, preferred-column document boundaries, selection rendering, headers, and status presentation

Tree-sitter, Git, LSP, review-note, Mermaid, and persistence integrations remain outside this issue.
