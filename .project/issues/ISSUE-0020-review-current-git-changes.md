---
id: ISSUE-0020
title: "Review current Git changes"
kind: "implementation"
status: claimed
created: 2026-08-25
assignee: "agent"
parent: "ISSUE-0013-implement-fiew-v0-1.md"
blocked_by:
  - "ISSUE-0016-complete-the-modal-command-and-workspace-language.md"
labels: []
---
# Review current Git changes

## Parent

[Implement fiew v0.1](<.project/issues/ISSUE-0013-implement-fiew-v0-1.md>)

## Source specification

[fiew v0.1](<docs/specs/fiew-v0-1.md>)

## What to build

Deliver the read-only Git adapter, Staged/Unstaged/Untracked sidebar groups, unified textual diffs, metadata-only unsupported changes, rename detection, previews, pinning, and diff navigation.

## Acceptance criteria

- [ ] Standard, linked, unborn, non-Git, and unsupported bare repositories behave as specified.
- [ ] Added, modified, deleted, renamed, binary, mode-only, and submodule fixtures pass.
- [ ] Git invocations are shell-free, machine-readable, and non-mutating.
- [ ] File, hunk, changed-line, source-context, and return navigation work.
- [ ] Git and source state remain unchanged after verification.

## Blocked by

Managed by native issue relationships.

## Out of scope

Automatic refresh, syntax-layered diffs, and review notes.

## Comments

## Resolution
