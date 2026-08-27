---
id: ISSUE-0025
title: "Preview Mermaid fences as terminal text"
kind: "implementation"
status: open
created: 2026-08-25
assignee: 
parent: "ISSUE-0052-hold-deferred-fiew-v0-2-implementation-candidates.md"
blocked_by:
  - "ISSUE-0016-complete-the-modal-command-and-workspace-language.md"
  - "ISSUE-0019-add-markdown-syntax-and-fenced-code-structure.md"
labels: []
---
# Preview Mermaid fences as terminal text

## Parent

[Hold deferred fiew v0.2 implementation candidates](<.project/issues/ISSUE-0052-hold-deferred-fiew-v0-2-implementation-candidates.md>)

## Planning status

Deferred from v0.1. This is a candidate v0.2 implementation slice and must be reconciled with the eventual v0.2 specification and portability boundary.

## What to build

Render supported Markdown Mermaid fences as transient Unicode or strict-ASCII views through optional `mermaid-ascii`, with type detection, subprocess bounds, sanitization, caching, and source-preserving fallback across supported terminals.

## Acceptance criteria

- [ ] Flowchart, sequence, and ER fixtures render in supported modes.
- [ ] Unsupported types remain source-only with a disabled reason.
- [ ] Input, output, stderr, and runtime limits are enforced.
- [ ] Escape sequences and control bytes never reach any supported terminal directly.
- [ ] Resize preserves diagram scroll and preview exit restores source location.
- [ ] Missing renderer does not impair Markdown viewing.
- [ ] Ghostty, Kitty, and WezTerm smoke checks cover representative output.

## Blocked by

Managed by native issue relationships.

## Out of scope

Full Mermaid support, graphical rendering, and standalone Mermaid files.

## Comments

## Resolution
