---
id: ISSUE-0002
title: "Decide the v0.1 editing boundary"
kind: "clarification"
status: resolved
created: 2026-08-25
assignee: "agent"
parent: "ISSUE-0001-plan-fiew-v0-1.md"
blocked_by:
labels: []
---
# Decide the v0.1 editing boundary

## Question

Will v0.1 be read-only, support narrowly scoped edits, or behave as a general text editor, and what user-visible guarantees follow from that boundary?

## Answer

v0.1 is read-only with respect to source files and Git state. It retains modal selections, navigation, folding, and commands without offering source-editing operations.

`fiew` may write only its own explicit review-note and configuration state plus disposable cache data. It must not modify source files or Git state, invoke mutating Git commands, or apply LSP workspace edits. Viewing, navigation, and integration failures must preserve this boundary.

## Comments
## Resolution

Accepted: fiew v0.1 is a read-only source and Git viewer. It may persist only explicit fiew-owned review/configuration state and disposable caches; mutating Git operations and LSP workspace edits are excluded.
