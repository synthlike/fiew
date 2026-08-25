---
id: ISSUE-0001
title: "Plan fiew v0.1"
kind: "initiative"
status: resolved
created: 2026-08-25
assignee: 
parent: 
blocked_by:
labels: []
---
# Plan fiew v0.1

## Destination

Settle enough product, interaction, and technical decisions to author a coherent `fiew` v0.1 specification and implementation plan for a usable read-first vertical slice.

## Notes

`fiew` is a hobby project and a terminal CLI editor written in Zig. It is primarily for quickly viewing code and diffs and navigating codebases. Standing preferences include a Helix/Kakoune-inspired modal experience, a left pane for project, Git, and review-note contexts, code folding, Tree-sitter-aware structure, simple LSP navigation, and Mermaid rendering. Inspirations include fx, flow, and druk.

Use `clarify-intent` for product and interaction choices, `research-question` for external technical facts, and `prototype-design` for interaction questions that need a concrete artifact.

## Decisions so far

- [Decide the v0.1 editing boundary](<.project/issues/ISSUE-0002-decide-the-v0-1-editing-boundary.md>) — v0.1 never modifies source files or Git state; only explicit fiew-owned state and disposable caches may be written.

## Not yet specified

Further decisions exposed by technical research and interaction prototypes.

## Out of scope

- Implementing the editor during this planning initiative.
- Product-market validation, monetization, and go-to-market work; this is a hobby project.
- Matching a full general-purpose IDE in v0.1.

## Comments
## Resolution

**Outcome: Achieved.**

The planning destination was to settle enough product, interaction, and technical decisions to author a coherent v0.1 specification and implementation plan for a usable read-first slice. That destination is achieved.

## Delivered planning value

- The approved behavior is consolidated in [fiew v0.1](<docs/specs/fiew-v0-1.md>).
- The production-compatible foundation is indexed by [fiew v0.1 engineering baseline](<docs/engineering/fiew-v0-1-engineering-baseline.md>).
- Consequential decisions are recorded in [Adopt libvaxis’s low-level API for fiew v0.1](<docs/decisions/ARP-0001.md>), [Integrate Tree-sitter behind a direct C adapter](<docs/decisions/ARP-0002.md>), [Use trusted ZLS as an optional definition provider](<docs/decisions/ARP-0003.md>), [Render a Mermaid subset as terminal text](<docs/decisions/ARP-0004.md>), and [Structure fiew as a single-owner event-driven application](<docs/decisions/ARP-0005.md>).
- The executable vertical-slice plan is published under [Implement fiew v0.1](<.project/issues/ISSUE-0013-implement-fiew-v0-1.md>), with fourteen dependency-linked implementation issues.
- Every planning child issue is resolved; no blocked, cancelled, or unresolved planning work remains.

## Limitations and remaining work

No production behavior was delivered or claimed by this planning initiative. Build, runtime, performance, Ghostty, Tree-sitter, Git, ZLS, Mermaid, persistence, and release behavior remain unverified until the implementation initiative delivers evidence. Signing, notarization, release automation, and replacement of the libvaxis commit pin remain non-blocking future decisions.

Implementation proceeds independently under [Implement fiew v0.1](<.project/issues/ISSUE-0013-implement-fiew-v0-1.md>).
