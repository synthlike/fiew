---
id: ISSUE-0013
title: "Implement fiew v0.1"
kind: "initiative"
status: open
created: 2026-08-25
assignee: 
parent: 
blocked_by:
labels: []
---
# Implement fiew v0.1

## Destination

Deliver the complete read-first v0.1 behavior defined by [fiew v0.1](<docs/specs/fiew-v0-1.md>) as a verified Apple Silicon macOS binary for Ghostty.

## Acceptance criteria

- All required browse, Git review-note, and Zig definition-navigation workflows pass.
- Optional integrations fail without impairing core viewing or violating the read-only boundary.
- The supported build, test, performance, and Ghostty verification complete honestly.
- A documented `ReleaseSafe` Apple Silicon artifact can be produced from a clean checkout.

## Out of scope

- Behavior excluded by the source specification.
- Automatically publishing a release.
- Signing, notarization, and package-manager distribution.

## Comments

## Resolution
