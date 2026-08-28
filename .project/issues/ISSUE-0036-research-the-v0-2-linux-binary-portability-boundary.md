---
id: ISSUE-0036
title: "Research the v0.2 Linux binary portability boundary"
kind: "research"
status: resolved
created: 2026-08-27
assignee: "agent"
parent: "ISSUE-0030-plan-fiew-v0-2.md"
blocked_by:
labels: []
---
# Research the v0.2 Linux binary portability boundary

## Question

Which libc, minimum distribution/kernel, dynamic-linking, archive, and CI choices can produce a practical x86_64 Linux release while retaining a non-gating ARM64 Linux source build?

## Findings

The approved findings are recorded in [Linux binary portability boundary for fiew v0.2](<docs/research/linux-binary-portability-boundary-for-fiew-v0-2.md>).

Use a baseline-CPU, statically linked `x86_64-linux-musl` release archive built and tested on Ubuntu 22.04. Treat Ubuntu 22.04 and Linux 5.15 as the verified floor. Keep `aarch64-linux-musl` as a non-gating source-build compile check. Current Linux cross-compilation also requires POSIX/default feature-test macros for the vendored Tree-sitter C sources.

## Comments
## Resolution

Research approved on 2026-08-28. The retained research recommends a statically linked `x86_64-linux-musl` archive, Ubuntu 22.04/Linux 5.15 as the verified floor, and a non-gating `aarch64-linux-musl` compile check. It also records the current Tree-sitter feature-test-macro build blocker.
