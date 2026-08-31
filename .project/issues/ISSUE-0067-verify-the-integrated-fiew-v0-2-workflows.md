---
id: ISSUE-0067
title: "Verify the integrated fiew v0.2 workflows"
kind: "implementation"
status: open
created: 2026-08-28
assignee:
parent: "ISSUE-0057-implement-fiew-v0-2.md"
blocked_by:
  - "ISSUE-0058-fuzzy-find-and-open-repository-files.md"
  - "ISSUE-0060-normalize-terminal-and-subprocess-behavior.md"
  - "ISSUE-0061-add-markdown-syntax-and-fenced-code-structure.md"
  - "ISSUE-0064-navigate-to-zig-definitions-through-trusted-zls.md"
  - "ISSUE-0065-find-zig-references-through-trusted-zls.md"
  - "ISSUE-0066-show-zig-hover-information-through-trusted-zls.md"
  - "ISSUE-0073-record-and-revisit-review-local-trails.md"
labels: []
---
# Verify the integrated fiew v0.2 workflows

## Parent

[fiew v0.2](<docs/specs/fiew-v0-2.md>)

## What to build

Deliver an integrated conformance pass demonstrating that every approved v0.2 capability works together without weakening v0.1 review behavior or the read-only boundary.

## Acceptance criteria

- [ ] The complete deterministic offline suite covers all accepted matcher, parser, subprocess, protocol, reducer, persistence, and render seams.
- [ ] Opt-in Git and ZLS integrations pass when their executables are installed.
- [ ] Unavailable optional tools are verified separately from successful integration behavior.
- [ ] Ghostty, Kitty, and WezTerm smoke evidence covers required macOS and Linux startup, restoration, input, resize, fallback, Markdown, finder, and Zig navigation behavior.
- [ ] No v0.1 review, bookmark, persistence, or agent-authority contract regresses.

## Blocked by

Managed by native issue relationships.

## Out of scope

Release packaging and behavior excluded by the v0.2 specification.

## Comments

## Resolution
