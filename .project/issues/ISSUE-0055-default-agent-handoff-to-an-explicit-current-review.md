---
id: ISSUE-0055
title: "Default agent handoff to an explicit current review"
kind: "implementation"
status: resolved
created: 2026-08-28
assignee: "agent"
parent: "ISSUE-0013-implement-fiew-v0-1.md"
blocked_by:
labels: []
---
# Default agent handoff to an explicit current review

## Parent

Implement fiew v0.1.

## Source authority

RFC-0002, ARP-0009, and the fiew v0.1 specification.

## What to build

Remove routine review-ID exchange by persisting one explicit current review per repository and making routine reviewer and agent commands default to it without weakening historical access or authority boundaries.

## Acceptance criteria

- [ ] `review start` atomically marks the created review current; `review open` opens current, while `review open <review-id>` opens and atomically makes that review current.
- [ ] `review show` defaults to current and explicit `review show <review-id>` accesses history without changing current.
- [ ] `review reply <thread-id> --body-file <path>` replies to current, while the existing explicit `<review-id> <thread-id>` form remains available; neither agent form changes current.
- [ ] Approval leaves current unchanged, and only reviewer start/open operations update it.
- [ ] Missing, malformed, and dangling current state fails explicitly without newest-file, timestamp, directory-order, staged-content, or other inference.
- [ ] Current-pointer persistence is repository-local, validated, atomic, and preserves the source/Git mutation boundary.
- [ ] Command parsing, terminal restoration, public output, role authority, persistence failures, and approval-sensitive exit codes remain covered.

## Blockers

None identified.

## Out of scope

Content-derived review IDs, removal of opaque review IDs, multiple simultaneous current reviews, automatic newest-review selection, automatic clearing after approval, and remote review discovery.

## Comments
## Resolution

Implemented one explicit repository-local current-review pointer at `.reviews/current`. Review creation and explicit reviewer open validate the target and atomically update current; ID-optional open/show and short-form reply resolve it without inference. Explicit show/reply preserve current, approval never clears it, and missing, malformed, or dangling pointers return typed failures. Existing opaque IDs and explicit historical forms remain available. Added parser, pointer atomicity/rollback, authority, corruption, dangling-target, and no-inference coverage. Verification passes with 128/128 tests, ReleaseSafe, Apple Silicon macOS build, and command-level smoke checks for current/default, malformed, and explicit historical show behavior.
