---
id: ISSUE-0034
title: "Replace the legacy review flag with the agent review interface"
kind: "implementation"
status: open
created: 2026-08-27
assignee:
parent: "ISSUE-0013-implement-fiew-v0-1.md"
blocked_by:
  - "ISSUE-0033-evolve-local-review-notes-into-reviewer-owned-threads.md"
labels: []
---
# Replace the legacy review flag with the agent review interface

## Parent

[Implement fiew v0.1](<.project/issues/ISSUE-0013-implement-fiew-v0-1.md>)

## What to build

Replace `fiew --review <filename>` with a consistent `fiew review` command family that lets reviewers start or reopen an interactive review and lets agents read complete history or append one reply without arbitrary review-file access.

This follow-up owns the unresolved conformance findings recorded on [Support agent-driven review handoff](<.project/issues/ISSUE-0029-support-agent-driven-review-handoff.md>).

## Acceptance criteria

- [ ] `review start`, `review open`, `review show`, and `review reply` accept the specified operands and default repository selection to the current working directory with optional `--repo`.
- [ ] New IDs always contain the datetime prefix; explicit slugs are sanitized, unnamed interactive starts use bundled adjective-noun names, `.md` is automatic, and collisions receive numeric suffixes.
- [ ] Interactive start prints the canonical review ID only after terminal restoration.
- [ ] `show` emits stable complete JSON by default and supports Markdown output.
- [ ] `reply` appends exactly one `agent` comment to an existing thread and cannot create or change thread status.
- [ ] Invalid identifiers, path separators, missing operands, malformed schemas, and unsupported operations fail explicitly.
- [ ] Exit zero occurs only when every thread is durably reviewer-resolved; persistence failure and Open or Outdated threads cannot produce approval.
- [ ] CLI contract tests cover cwd and `--repo`, naming, reopen, prior-comment history, reply authority, future schemas, write failure, and terminal restoration.

## Blocked by

Managed by native issue relationships.

## Out of scope

General file-writing commands, individual agent identity, remote publication, and compatibility aliases for the legacy flag.

## Comments


## Resolution
