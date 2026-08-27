---
id: ISSUE-0029
title: "Support agent-driven review handoff"
kind: "implementation"
status: resolved
created: 2026-08-27
assignee: "agent"
parent: "ISSUE-0013-implement-fiew-v0-1.md"
blocked_by:
labels: []
---
# Support agent-driven review handoff

## Parent

[Implement fiew v0.1](<.project/issues/ISSUE-0013-implement-fiew-v0-1.md>)

## Source specification

[fiew v0.1](<docs/specs/fiew-v0-1.md>)

## What to build

Let a coding agent open fiew for review and read the result deterministically, without scraping the interactive TUI's stdout.

- Add a `--review <name>` flag. When set, the session's review file is `.reviews/<name>` (a basename, no path separators, kept within `.reviews/` to honor the read-only boundary). New notes append to that exact file, and existing notes in it load and are editable.
- On exit, set the process exit code from that review file: `1` when it has one or more Open notes (changes requested), `0` otherwise (approved / nothing to address). Terminal state is restored before the process exits with the code.
- Without `--review`, behavior is unchanged: a timestamped session file and exit code `0`.

The agent flow becomes: choose a path, run `fiew --review <name> <repo>`, then branch on the exit code and read `<repo>/.reviews/<name>` for the notes.

## Acceptance criteria

- [x] `--review <name>` routes the session's notes to `.reviews/<name>` and loads existing notes from it; names with path separators are rejected.
- [x] Exit code is `1` when the review file has Open notes and `0` otherwise; the terminal is restored first.
- [x] Without the flag, the session filename and a `0` exit code are unchanged.
- [x] Only `.reviews/` is written; source, tracked files, `.gitignore`, and Git metadata are untouched.

## Blocked by

Managed by native issue relationships.

## Out of scope

A machine-readable exit summary file, watching for external edits, and any non-note output channel.

## Comments

## Resolution

**Outcome: Achieved.**

Added a deterministic review handoff for a coding agent that opens fiew and reads the result from files, with no TUI stdout scraping.

- `--review <name>` (a bare filename, path separators rejected) routes the session's notes to `.reviews/<name>`; existing notes in that file load and remain editable/resolvable. Without the flag, the timestamped session filename is unchanged.
- On quit, the process exit code is `1` when the named review file has one or more Open notes and `0` otherwise. `run` returns the code and `main` calls `std.process.exit` only after the terminal-restoring defers have run, so the terminal is restored first. Without `--review`, the exit code stays `0`.
- Writes remain confined to `.reviews/`.

The agent flow is: pick a name, run `fiew --review <name> <repo>`, branch on the exit code (0 approved / 1 changes requested), and read `<repo>/.reviews/<name>` for the notes.

Verification passed:

- `zig build test --system zig-pkg -Dgit-integration` — 92/92; `zig fmt --check`; ReleaseSafe and aarch64-macos builds.
- Manual: `fiew --review pre-commit.md <repo>` → created a note and quit → exit code `1`, notes written to `.reviews/pre-commit.md`. Re-ran, resolved the note, quit → exit code `0`, `status: resolved` on disk.
