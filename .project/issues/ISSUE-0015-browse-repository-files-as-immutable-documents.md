---
id: ISSUE-0015
title: "Browse repository files as immutable documents"
kind: "implementation"
status: resolved
created: 2026-08-25
assignee: "agent"
parent: "ISSUE-0013-implement-fiew-v0-1.md"
blocked_by:
  - "ISSUE-0014-bootstrap-a-safe-ghostty-application.md"
labels: []
---
# Browse repository files as immutable documents

## Parent

[Implement fiew v0.1](<.project/issues/ISSUE-0013-implement-fiew-v0-1.md>)

## Source specification

[fiew v0.1](<docs/specs/fiew-v0-1.md>)

## What to build

Open a directory, display its Project tree, preview and pin files, navigate plain text, handle binary and invalid UTF-8 files, and apply the responsive sidebar layout.

## Acceptance criteria

- [ ] The Project tree remains usable at the 10,000-tracked-file target.
- [ ] Preview, pin, collapse, focus, and resize behavior matches the specification.
- [ ] Text navigation is grapheme-safe and preserves byte mappings.
- [ ] Binary and invalid UTF-8 behavior is verified.
- [ ] Source files remain byte-for-byte unchanged.

## Blocked by

Managed by native issue relationships.

## Out of scope

Complete modal command surfaces and external integrations.

## Comments
## Resolution

**Outcome: Achieved.**

Delivered read-only directory browsing with a collapsible Project tree, file previews and pinning, explicit sidebar/main focus, responsive beside/overlay layouts, and preserved selection and scroll state across resize. The terminal adapter accepts an optional directory argument and supports keyboard and mouse focus.

Every opened file becomes an owned, immutable `DocumentSnapshot` with source bytes, generation, captured metadata, source/display mappings, line mappings, and Unicode grapheme ranges. NUL-containing files use binary metadata views. Invalid UTF-8 renders replacement characters while preserving original byte ranges. Terminal-bound source and path text is sanitized before rendering.

Verification passed:

- `zig build`
- `zig build test --system zig-pkg` — 20/20 tests
- `zig fmt --check src build.zig`
- ReleaseSafe and explicit `aarch64-macos` builds
- A 10,000-file tree navigation test
- Automated source-byte preservation, binary, invalid UTF-8, grapheme, layout, preview, pin, collapse, focus, and scrolling checks
- Manual Ghostty checks for browsing, pinning, navigation, keyboard and mouse focus, responsive resize, unsupported dimensions, and terminal restoration

Repository files are opened only through read operations. Complete modal commands, history, parsing, Git, persistence, LSP, review notes, and Mermaid remain outside this issue.
