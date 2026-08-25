---
id: ISSUE-0017
title: "Establish recoverable fiew-owned state"
kind: "implementation"
status: open
created: 2026-08-25
assignee: 
parent: "ISSUE-0013-implement-fiew-v0-1.md"
blocked_by:
  - "ISSUE-0014-bootstrap-a-safe-ghostty-application.md"
labels: []
---
# Establish recoverable fiew-owned state

## Parent

[Implement fiew v0.1](<.project/issues/ISSUE-0013-implement-fiew-v0-1.md>)

## Source specification

[fiew v0.1](<docs/specs/fiew-v0-1.md>)

## What to build

Persist repository identities and schema-versioned global/per-repository JSON state with atomic writes, validated backup recovery, future-version refusal, and bounded redacted diagnostics.

## Acceptance criteria

- [ ] Round trips, corrupt-primary recovery, interrupted writes, and unknown future schemas are tested.
- [ ] Persistent state remains outside repositories and `.git`.
- [ ] Diagnostics redact protected content by default.
- [ ] All writes pass through one serialized state-store adapter.

## Blocked by

Managed by native issue relationships.

## Out of scope

Review-note behavior and ZLS trust interaction.

## Comments

## Resolution
