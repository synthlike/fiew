---
id: ISSUE-0030
title: "Plan fiew v0.2"
kind: "initiative"
status: open
created: 2026-08-27
assignee:
parent:
blocked_by:
labels: []
---
# Plan fiew v0.2

## Destination

Settle the remaining portability and interaction decisions needed to author a coherent fiew v0.2 specification covering richer document navigation and a broader supported platform.

## Notes

The accepted release boundary includes Markdown structure, terminal-text Mermaid preview, fuzzy file finding, and Zig/ZLS go-to-definition, references, and hover documentation. ZLS remains optional, trusted, user-installed, Zig-specific, and read-only; no generic language-server framework is required yet.

v0.2 must release for Apple Silicon macOS and x86_64 Linux. ARM64 Linux must remain buildable from source but is not a release gate. Ghostty, Kitty, and WezTerm form the required smoke-test matrix. Other xterm-compatible terminals are best-effort. Consult [Terminal compatibility boundary for fiew v0.2](<docs/research/terminal-compatibility-boundary-for-fiew-v0-2.md>).

Existing deferred implementation scopes for Markdown, Mermaid, fuzzy finding, and ZLS navigation are retained under [Hold deferred fiew v0.2 implementation candidates](<.project/issues/ISSUE-0052-hold-deferred-fiew-v0-2-implementation-candidates.md>). They are not part of this decision frontier and remain candidates until the v0.2 specification and implementation plan confirm their observable contract and dependencies.

## Decisions so far

- [Confirm the v0.2 capability and compatibility boundary](<.project/issues/ISSUE-0049-confirm-the-v0-2-capability-and-compatibility-boundary.md>) — Markdown, Mermaid, fuzzy finding, expanded Zig navigation, x86_64 Linux releases, ARM64 Linux source builds, and the Ghostty/Kitty/WezTerm matrix define v0.2.

## Not yet specified

None beyond the open decision tickets.

## Out of scope

- Go, JavaScript, TypeScript, React, and generic multi-language capability; these belong to v0.3.
- GitHub and other remote review providers; these belong to v0.4.
- Windows releases, package-manager distribution, source editing, and generic VCS abstraction.

## Comments


## Resolution
