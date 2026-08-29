---
id: ISSUE-0063
title: "Establish trusted ZLS lifecycle and read-only enforcement"
kind: "implementation"
status: resolved
created: 2026-08-28
assignee: "agent"
parent: "ISSUE-0057-implement-fiew-v0-2.md"
blocked_by:
  - "ISSUE-0059-run-the-core-workspace-portably-on-linux.md"
  - "ISSUE-0060-normalize-terminal-and-subprocess-behavior.md"
labels: []
---
# Establish trusted ZLS lifecycle and read-only enforcement

## Parent

[fiew v0.2](<docs/specs/fiew-v0-2.md>)

## What to build

Deliver trusted, observable, bounded ZLS startup and lifecycle for Zig without yet exposing semantic navigation results.

## Acceptance criteria

- [ ] ZLS never launches before persisted trust for the canonical repository identity.
- [ ] Version validation, initialize, document open/close, status, explicit restart, trust revocation, and orderly shutdown work.
- [ ] UTF-8 and UTF-16 positions map only against immutable request snapshots.
- [ ] Workspace edits, formatting, rename, code actions, file operations, dynamic registration, and server commands are refused.
- [ ] Missing, incompatible, starting, crashed, or unavailable ZLS preserves normal Zig and plain-text viewing.
- [ ] Protocol transcript tests pass offline without ZLS.

## Blocked by

Managed by native issue relationships.

## Out of scope

Definitions, references, hover, other languages, source-writing methods, and a generic language-server framework.

## Comments
## Resolution

Delivered the trusted ZLS lifecycle and read-only protocol boundary.

Persisted repository trust now keys ZLS consent by canonical repository identity in fiew-owned global state. Named commands expose the trust warning, status, explicit restart, and revocation. ZLS remains lazy, launches directly without a shell only after persisted trust, validates the 0.16.x version line, initializes one repository workspace, negotiates UTF-8/UTF-16, balances immutable Zig document snapshots, refuses server requests, and performs bounded shutdown and child reaping. Startup, missing executable, incompatibility, crash, and unavailable persistence remain isolated from normal viewing.

Added bounded JSON-RPC framing, lifecycle transcript coverage, read-only refusal coverage, immutable snapshot position-mapping tests, trust persistence/revocation tests, and command reducer coverage. Definition, reference, and hover requests remain deferred to their child issues.

Verification:
- `zig build test`
- `zig build -Dtarget=x86_64-linux-musl -Dcpu=baseline`
- `zig build -Dtarget=aarch64-linux-musl -Dcpu=baseline`
- `zig fmt --check src build.zig`
- `git diff --check`

Live verification with ZLS 0.16.0 found and corrected two protocol defects: the streaming reader did not consume header delimiters, and empty anonymous values serialized as arrays instead of JSON objects. A regression test now covers consecutive framed messages. Temporary live probes then verified initialize/shutdown and initialize/document open/document close/shutdown against the repository.
