---
id: ISSUE-0023
title: "Re-anchor review threads and bookmarks"
kind: "implementation"
status: resolved
created: 2026-08-25
assignee: "agent"
parent: "ISSUE-0013-implement-fiew-v0-1.md"
blocked_by:
  - "ISSUE-0021-keep-git-views-current-and-consistent.md"
  - "ISSUE-0022-create-and-manage-local-review-notes.md"
  - "ISSUE-0033-evolve-local-review-notes-into-reviewer-owned-threads.md"
  - "ISSUE-0035-add-private-repository-bookmarks.md"
labels: []
---
# Re-anchor review threads and bookmarks

## Parent

[Implement fiew v0.1](<.project/issues/ISSUE-0013-implement-fiew-v0-1.md>)

## Source authority

[fiew v0.1](<docs/specs/fiew-v0-1.md>), RFC-0003, and ARP-0010.

## What to build

Relocate review-thread and bookmark anchors across source and Git refreshes only through constrained exact raw-byte context. Preserve identity and reviewer lifecycle on success, expose Outdated when content disappears or becomes ambiguous, and never guess across unrelated paths.

## Acceptance criteria

- [ ] Stored locations are validated first; an exact match there is retained even if identical content exists elsewhere.
- [ ] When stored validation fails, relocation requires exactly one complete match of anchored content plus up to three surrounding source lines; whitespace and syntax are not normalized.
- [ ] Bookmarks retain the selected byte offset within the anchored line and are evaluated after accepted Git refreshes and immediately before opening.
- [ ] Line threads follow one exact unchanged change among Untracked, Unstaged, and Staged groups; path changes are followed only through explicit Git rename metadata.
- [ ] File threads use an exact whole-change fingerprint covering canonical diff bytes and metadata, or available blob and non-text metadata identity.
- [ ] Missing and ambiguous matches preserve identity and stored location but become Outdated without moving.
- [ ] Thread reviewer lifecycle (Open or Resolved) is independent from anchor validity; Outdated blocks approval and a later exact match restores the remembered lifecycle.
- [ ] Re-evaluation occurs only after a complete generation-current Git snapshot is accepted. Persistence failure keeps that snapshot visible, marks transitions dirty, reports failure, and blocks approval or clean quit.
- [ ] Whole-repository movement carries local artifacts without anchor mutation or identity reassociation.
- [ ] Shared pure transition fixtures cover original retention, line movement, group transition, explicit rename, unrelated paths, ambiguity, missing content, file changes, root movement, and persistence failure.
- [ ] Exact context is mandatory in pre-release `fiew.review/v1` and `fiew.bookmark/v1`; missing context is malformed and no legacy migration is provided.

## Blocked by

Managed by native issue relationships.

## Out of scope

Whitespace-normalized, fuzzy, heuristic, semantic, language-server, or cross-unrelated-path relocation; remote synchronization; and compatibility with purged pre-context development records.

## Comments
## Resolution

Delivered constrained exact-context re-anchoring for review threads and bookmarks. Added mandatory raw-byte context with three surrounding lines, bookmark byte offsets, whole-change file fingerprints, stored-location-first matching, exact-unique relocation, explicit Git rename constraints, cross-group line-thread transitions, independent reviewer lifecycle and anchor validity, Outdated restoration, and root-movement-safe repository-relative state. Re-evaluation now runs only after accepted generation-current Git snapshots, bookmarks also validate before opening, and failed persistence leaves transitions dirty while preserving the accepted snapshot and blocking clean quit/approval. Ordinary browsing re-anchors only the explicit current review rather than mutating history. Pre-context v1 artifacts are rejected without migration. Shared fixtures cover retention, movement, ambiguity, missing content, group transitions, renames, unrelated paths, file fingerprints, lifecycle restoration, and repository movement. Verification passes with 137/137 tests, ReleaseSafe, Apple Silicon macOS build, formatting, and diff checks.
