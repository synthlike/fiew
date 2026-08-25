---
id: ISSUE-0012
title: "Choose the v0.1 internal architecture and dependency strategy"
kind: "clarification"
status: resolved
created: 2026-08-25
assignee: 
parent: "ISSUE-0001-plan-fiew-v0-1.md"
blocked_by:
  - "ISSUE-0005-establish-the-zig-and-terminal-ui-technical-baseline.md"
  - "ISSUE-0007-prototype-the-workspace-and-left-pane-interaction.md"
  - "ISSUE-0008-decide-parsing-highlighting-and-folding-architecture.md"
  - "ISSUE-0009-define-the-git-diff-and-review-note-workflow.md"
  - "ISSUE-0010-define-the-initial-lsp-navigation-contract.md"
  - "ISSUE-0011-decide-mermaid-rendering-scope-and-approach.md"
labels: []
---
# Choose the v0.1 internal architecture and dependency strategy

## Question

Given the settled interaction and integration decisions, which boundaries for documents, views, commands, parsing, Git, LSP, rendering, and external dependencies will support the v0.1 specification and implementation plan?

## Comments
## Resolution

Accepted: the internal architecture and dependency strategy is recorded in [Structure fiew as a single-owner event-driven application](<docs/decisions/ARP-0005.md>) and indexed by the updated [fiew v0.1 engineering baseline](<docs/engineering/fiew-v0-1-engineering-baseline.md>).

## State, commands, and effects

- One UI thread owns mutable `AppState`, focus, selection, view state, command dispatch, and event application.
- Every action uses one typed command registry with stable identity, labels, keys, contexts, preconditions, pure transitions, optional typed effects, and disabled reasons.
- A bounded worker pool handles loading, parsing, Git, and Mermaid work. Each repository's ZLS process uses a dedicated ordered supervisor. Filesystem events coalesce.
- Effects and results carry owner, operation ID, source generation, deadline, and cancellation. Workers never mutate UI state; the UI thread rejects stale events.
- Bounded queues apply backpressure. Shutdown cancels effects, stops ZLS, closes queues, restores the terminal, then frees state.

## Documents and rendering

- Immutable versioned `DocumentSnapshot` values own origin, source bytes, line/display mappings, generation, UTF-8 status, and captured metadata.
- Selections, locations, folds, highlights, diffs, and LSP requests refer to snapshot identity plus byte ranges.
- NUL-containing files are binary metadata views. Invalid UTF-8 renders replacement characters while preserving byte mapping and disables Tree-sitter, LSP, and Mermaid without modifying bytes.
- Rendering is pure: application snapshot and dimensions produce a ViewModel, which produces a fiew-owned cell RenderPlan. The libvaxis adapter only applies the plan and performs no feature logic or I/O decisions.

## Boundaries and source layout

- Core code uses only fiew-owned types. External libraries, protocols, subprocess output, and persistence formats terminate in adapters behind ports.
- Use `src/main.zig` as composition root with `model/`, `app/`, `view/`, `ports/`, and `adapters/{terminal,parser,git,lsp,mermaid,storage}/`.
- Keep imports acyclic: model is foundational; app uses model and ports; view consumes model/application snapshots; adapters implement ports; main wires concrete implementations.

## Git and persistence

- Use the installed Git CLI directly without a shell, with explicit read-only machine-readable options and no pager, prompt, color, external diff, text conversion, or optional locks.
- Build one immutable Git snapshot and verify repository/index/worktree fingerprints around collection; discard and retry once on change.
- Store global repository/trust/preferences state and per-repository review notes in schema-versioned JSON outside repositories and Git metadata.
- Write through one state adapter using same-directory temporary files, flush and atomic rename, retain one validated backup, refuse unknown future versions, and never overwrite an unrecoverable newer/corrupt store.

## Dependencies

- Linked: pinned libvaxis, Tree-sitter core, Zig grammar, and Markdown grammars only.
- External: Git when Git workflows are used; optional ZLS 0.16.x; optional `mermaid-ascii` 1.5.x.
- Use Zig standard library for JSON/JSON-RPC, subprocesses, queues, files, persistence, hashing, diagnostics, and tests.
- Do not add libgit2, SQLite, a generic LSP library, `vxfw`, Node, Chromium, or an application framework without a later accepted decision.

## Verification and failures

- `zig build test` must require no network or optional executable. Use pure unit/reducer tests, fixed-dimension RenderPlan snapshots, fixture/transcript adapter contracts, ownership/leak tests, and fuzz/property checks. Installed-tool tests are opt-in; Ghostty protocol behavior has a manual smoke check.
- Adapters map failures to typed events and concise messages. Recoverable failures disable only the affected capability and preserve the last valid snapshot.
- Diagnostics use a bounded in-memory ring. File logging is opt-in, bounded, fiew-owned, and redacts source, notes, environment values, and protocol payloads by default. Fatal terminal failures restore the terminal before reporting.
