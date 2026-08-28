---
id: ISSUE-0034
title: "Replace the legacy review flag with the agent review interface"
kind: "implementation"
status: resolved
created: 2026-08-27
assignee: "agent"
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

**Outcome: Achieved.**

Replaced the legacy `--review` handoff with the command-mediated review interface:

- `fiew review start [--name <slug>] [--repo <path>]` creates a durable empty review and opens it interactively.
- `fiew review open <review-id> [--repo <path>]` validates and opens exactly one existing review.
- `fiew review show <review-id> [--format json|markdown] [--repo <path>]` emits stable, complete JSON by default or canonical Markdown.
- `fiew review reply <review-id> <thread-id> --body-file <path> [--repo <path>]` appends exactly one `agent` comment without changing thread status or granting lifecycle authority.

New IDs use a `YYYYMMDD-HHMMSS-slug` shape. Explicit names are lowercased and sanitized; unnamed starts use bundled adjective-noun combinations; `.md` is internal; collisions receive `-2`, `-3`, and later suffixes. Strict identifier validation prevents separators, extensions, malformed datetime prefixes, and arbitrary review basenames.

Interactive start routes output through an ordering contract that invokes the TUI to completion before printing the canonical ID, so terminal-restoration defers run first. Named interactive sessions load only their exact validated review and propagate load/allocation failures instead of silently falling back. Deleting the final thread persists an empty review rather than deleting its canonical identity.

Exact-file storage loading preserves validated backup recovery while ignoring malformed unrelated review files. Future schemas remain refused without overwrite. Agent reply writes use the existing validated backup and atomic replacement path. Command errors exit 2; approval-sensitive commands exit 0 only when all threads are Resolved, with Open, Outdated, malformed, missing, failed-write, or unsaved state producing non-success.

Verification passed:

- `zig build --system zig-pkg`
- `zig build test --system zig-pkg`
- `zig build test --system zig-pkg -Dgit-integration --summary all` — 115/115 tests
- `zig fmt --check src build.zig`
- `zig build -Doptimize=ReleaseSafe --system zig-pkg`
- `zig build -Dtarget=aarch64-macos --system zig-pkg`
- `git diff --check`

CLI smoke checks exercised default-cwd and `--repo` show, JSON and Markdown output, agent reply persistence, malformed/missing operands, invalid IDs, and legacy-flag refusal. Contract tests cover parsing, naming/sanitization/collisions, reopen, stable complete history, reply role and lifecycle preservation, future-schema refusal, unrelated-file isolation, persistence failure, approval, and output-after-restoration ordering. No manual interactive Ghostty session was performed.
