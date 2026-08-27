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

Deliver the review-first v0.1 behavior defined by [fiew v0.1](<docs/specs/fiew-v0-1.md>) as a verified Apple Silicon macOS binary for Ghostty.

## Acceptance criteria

- Immutable repository browsing and Zig structural navigation work without source or Git mutation.
- The Git-backed VCS view publishes only complete, consistent snapshots and preserves repository-root identity.
- Reviewer-owned threads, agent replies, strict reviewer resolution, and the non-interactive review interface work against durable review state.
- Private repository bookmarks and the Project/VCS/Review/Bookmarks context bindings work as specified.
- The supported build, test, performance, and Ghostty verification complete honestly.
- A documented `ReleaseSafe` Apple Silicon artifact can be produced from a clean checkout.

## Out of scope

- Markdown, Mermaid, fuzzy file finding, ZLS, Linux, and additional terminals; these move to v0.2.
- Remote review providers, source editing, and Git mutation.
- Automatically publishing a release, signing, notarization, or package-manager distribution.

## Comments

## Resolution
