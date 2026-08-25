---
id: ISSUE-0027
title: "Produce the v0.1 Apple Silicon release artifact"
kind: "implementation"
status: open
created: 2026-08-25
assignee: 
parent: "ISSUE-0013-implement-fiew-v0-1.md"
blocked_by:
  - "ISSUE-0026-verify-the-integrated-read-first-workflows.md"
labels: []
---
# Produce the v0.1 Apple Silicon release artifact

## Parent

[Implement fiew v0.1](<.project/issues/ISSUE-0013-implement-fiew-v0-1.md>)

## Source specification

[fiew v0.1](<docs/specs/fiew-v0-1.md>)

## What to build

Produce a `ReleaseSafe` Apple Silicon binary archive from a clean checkout and document manual GitHub Release installation and optional-tool prerequisites.

## Acceptance criteria

- [ ] A clean checkout produces the documented archive reproducibly.
- [ ] The artifact runs in Ghostty on supported macOS.
- [ ] Version and linked-dependency information are inspectable.
- [ ] Installation plus Git, ZLS, and Mermaid prerequisites are documented.
- [ ] The release checklist does not claim signing, notarization, Homebrew, or automatic publishing.

## Blocked by

Managed by native issue relationships.

## Out of scope

Signing, notarization, package managers, and automatic release publishing.

## Comments

## Resolution
