---
id: ISSUE-0063
title: "Establish trusted ZLS lifecycle and read-only enforcement"
kind: "implementation"
status: open
created: 2026-08-28
assignee:
parent: "ISSUE-0057-implement-fiew-v0-2.md"
blocked_by:
  - "ISSUE-0059-run-the-core-workspace-portably-on-linux.md"
  - "ISSUE-0060-normalize-terminal-and-subprocess-behavior.md"
labels: []
---
# Establish trusted ZLS lifecycle and read-only enforcement

## Parent

[fiew v0.2](<docs/specs/fiew-v0-2.md>)

## What to build

Deliver trusted, observable, bounded ZLS startup and lifecycle for Zig without yet exposing semantic navigation results.

## Acceptance criteria

- [ ] ZLS never launches before persisted trust for the canonical repository identity.
- [ ] Version validation, initialize, document open/close, status, explicit restart, trust revocation, and orderly shutdown work.
- [ ] UTF-8 and UTF-16 positions map only against immutable request snapshots.
- [ ] Workspace edits, formatting, rename, code actions, file operations, dynamic registration, and server commands are refused.
- [ ] Missing, incompatible, starting, crashed, or unavailable ZLS preserves normal Zig and plain-text viewing.
- [ ] Protocol transcript tests pass offline without ZLS.

## Blocked by

Managed by native issue relationships.

## Out of scope

Definitions, references, hover, other languages, source-writing methods, and a generic language-server framework.

## Comments

## Resolution
