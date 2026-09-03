---
id: ISSUE-0067
title: "Verify the integrated Skaut v0.2 workflows"
kind: "implementation"
status: resolved
created: 2026-08-28
assignee: "agent"
parent: "ISSUE-0057-implement-fiew-v0-2.md"
blocked_by:
  - "ISSUE-0058-fuzzy-find-and-open-repository-files.md"
  - "ISSUE-0060-normalize-terminal-and-subprocess-behavior.md"
  - "ISSUE-0061-add-markdown-syntax-and-fenced-code-structure.md"
  - "ISSUE-0064-navigate-to-zig-definitions-through-trusted-zls.md"
  - "ISSUE-0065-find-zig-references-through-trusted-zls.md"
  - "ISSUE-0066-show-zig-hover-information-through-trusted-zls.md"
  - "ISSUE-0073-record-and-revisit-review-local-trails.md"
  - "ISSUE-0083-move-v0-2-trails-to-standalone-trails-artifacts.md"
  - "ISSUE-0087-transition-repository-hosting-and-verify-the-complete-skaut-identity.md"
labels: []
---
# Verify the integrated Skaut v0.2 workflows

## Parent

[Skaut v0.2](<docs/specs/fiew-v0-2.md>)

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

Integrated implementation review verdict: **Conforms**.

The deterministic offline suite passed with Git and ZLS absent from `PATH` (214 passed, 9 expected opt-in skips). The Git integration suite passed (221 passed, 2 performance-only skips), the 10,000-file performance profile passed, and the combined live Git/ZLS suite passed (222 passed, 2 performance-only skips). The new `-Dzls-integration` check exercises ZLS 0.16.0 definition, references, hover, cancellation, orderly shutdown, and process reaping. README development guidance documents the external-tool test modes.

Native build and test binaries passed. The baseline static x86_64 Linux test binaries ran on Ubuntu 22.04 x86_64 with 194 core tests and 20 executable tests passing; the static executable reported `skaut 0.2.0`. Baseline static `x86_64-linux-musl` and `aarch64-linux-musl` builds passed. Formatting, source/Git mutation, lingering-ZLS-process, and diff checks passed.

The complete portable terminal checklist passed at Skaut commit `9638f41`. Apple Silicon macOS 26.6 passed with Ghostty 1.3.1, Kitty 0.48.2, and WezTerm 20240203-110809-5046fc22. Ubuntu 26.04 LTS x86_64 with kernel 7.0 passed with the same terminal versions. Evidence covers startup and restoration, keyboard and mouse input, resize and capability fallback, Markdown, finders, trusted ZLS navigation, optional-tool behavior, shutdown, and source/Git immutability.

Current Review, Bookmark, persistence, Trail, rendering, and agent-authority tests passed without a material v0.1 regression. No material conformance findings remain. Release artifact production remains assigned to ISSUE-0068.
