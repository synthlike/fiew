---
id: ISSUE-0016
title: "Complete the modal command and workspace language"
kind: "implementation"
status: open
created: 2026-08-25
assignee: 
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
