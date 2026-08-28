---
id: ISSUE-0054
title: "Store canonical reviews as private JSON"
kind: "implementation"
status: resolved
created: 2026-08-28
assignee: "agent"
parent: "ISSUE-0013-implement-fiew-v0-1.md"
blocked_by:
labels: []
---
# Store canonical reviews as private JSON

## Parent

Implement fiew v0.1.

## Source authority

RFC-0001, ARP-0008, and the fiew v0.1 specification.

## What to build

Replace canonical repository-local review Markdown with private canonical JSON while preserving the reviewer-owned thread model and command-mediated agent interface.

## Acceptance criteria

- [ ] New reviews use `.reviews/<review-id>.json` with the common `{ "schema": "fiew.review/v1", "data": ... }` envelope and no separate numeric version.
- [ ] `review show --format json` remains a stable complete public review projection, and `--format markdown` remains a human-readable projection; neither is treated as canonical storage.
- [ ] Arbitrary Markdown comment bodies round-trip as JSON strings without structural interpretation.
- [ ] `.reviews/*.md` is rejected as unsupported legacy state and is not migrated.
- [ ] Same-directory atomic persistence, validated `.bak` recovery, future-schema refusal, exact review loading, authority rules, and approval-sensitive exit status remain intact.
- [ ] Tests distinguish private canonical storage from public JSON and Markdown projections.

## Blockers

None identified.

## Out of scope

Migration of Markdown reviews, direct agent file access, changes to reviewer authority, remote reviews, and bookmark behavior beyond the shared envelope contract.

## Comments
## Resolution

Implemented canonical private review JSON under `.reviews/<review-id>.json` using the `fiew.review/v1` schema-plus-data envelope. Public JSON and Markdown remain explicit command projections; arbitrary Markdown bodies round-trip as JSON strings. Exact loading, reviewer/agent authority, approval exit status, atomic replacement, `<review-id>.bak` recovery, future-schema refusal, and persistence failure behavior remain intact. Legacy `.reviews/*.md` is rejected without migration. Automated verification passes, including projection-versus-storage and named legacy rejection coverage.
