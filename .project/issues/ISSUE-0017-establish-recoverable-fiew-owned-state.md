---
id: ISSUE-0017
title: "Establish recoverable fiew-owned state"
kind: "implementation"
status: resolved
created: 2026-08-25
assignee: "agent"
parent: "ISSUE-0013-implement-fiew-v0-1.md"
blocked_by:
  - "ISSUE-0014-bootstrap-a-safe-ghostty-application.md"
labels: []
---
# Establish recoverable fiew-owned state

## Parent

[Implement fiew v0.1](<.project/issues/ISSUE-0013-implement-fiew-v0-1.md>)

## Source specification

[fiew v0.1](<docs/specs/fiew-v0-1.md>)

## What to build

Persist repository identities and schema-versioned global/per-repository JSON state with atomic writes, validated backup recovery, future-version refusal, and bounded redacted diagnostics.

## Acceptance criteria

- [x] Round trips, corrupt-primary recovery, interrupted writes, and unknown future schemas are tested.
- [x] Persistent state remains outside repositories and `.git`.
- [x] Diagnostics redact protected content by default.
- [x] All writes pass through one serialized state-store adapter.

## Blocked by

Managed by native issue relationships.

## Out of scope

Review-note behavior and ZLS trust interaction.

## Comments

## Resolution

**Outcome: Achieved.**

Established the recoverable fiew-owned persistence foundation as a single serialized state-store adapter, a pure repository-identity model, and a bounded redacting diagnostics log. Review-note behavior and ZLS trust interaction remain out of scope; their consumers are deferred to their own issues, so no live persistence flow was wired into the terminal loop.

Delivered:

- `src/adapters/storage/state_store.zig` — the one serialized adapter. Every save and load holds a single `std.Io.Mutex`, so all writes pass through one owner. Records are schema-versioned JSON envelopes (`{schema, version, data}`). Writes use a same-directory temporary file, flush, best-effort sync, and atomic replacement via `File.Atomic`. A valid current primary is rotated to one validated `.bak` backup before replacement. Loads recover from that backup when the primary is missing or undecodable, refuse to touch a stored file that declares a newer schema version (`future_version`), and report `absent`/`unrecoverable` distinctly. Strings are parsed with `alloc_always` so results outlive the transient file bytes.
- `src/model/repository_identity.zig` — derives a deterministic, filesystem-safe 128-bit hex slug from a canonical repository path, keying per-repository state files while retaining the canonical path for anchoring.
- `src/app/diagnostics.zig` — a fixed-capacity ring (bounded history) that redacts protected detail (source, note bodies, environment values, protocol payloads) by default; verbatim inclusion is an explicit opt-in. Recording never allocates and is guarded for worker-thread use.
- `dataDirectoryPath` resolves the fiew-owned `~/Library/Application Support/fiew` base from a caller-supplied home, keeping environment values out of the store and persistent state outside repositories and `.git`.

Acceptance criteria:

- Round trips, corrupt-primary recovery, interrupted writes, and unknown future schemas are covered by tests, alongside absent/unrecoverable outcomes, future-version refusal without overwrite, redaction, bounded history, and identity stability.
- Persistent state stays outside repositories and `.git`: the store operates only on the fiew-owned base directory.
- Diagnostics redact protected content by default (tested).
- All writes pass through the one serialized state-store adapter.

Verification passed:

- `zig build`
- `zig build test --system zig-pkg` — 44/44 tests
- `zig fmt --check src build.zig`
- `zig build -Doptimize=ReleaseSafe --system zig-pkg`
- `zig build -Dtarget=aarch64-macos --system zig-pkg`

Tests use no network access or optional executables. Config, trust, review-note, and Git/LSP/Mermaid integrations that will consume this store remain outside this issue.
