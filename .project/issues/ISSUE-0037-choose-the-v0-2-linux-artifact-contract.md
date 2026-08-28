---
id: ISSUE-0037
title: "Choose the v0.2 Linux artifact contract"
kind: "clarification"
status: resolved
created: 2026-08-27
assignee: "agent"
parent: "ISSUE-0030-plan-fiew-v0-2.md"
blocked_by:
  - "ISSUE-0036-research-the-v0-2-linux-binary-portability-boundary.md"
labels: []
---
# Choose the v0.2 Linux artifact contract

## Question

Based on portability research, what exact x86_64 Linux artifact, compatibility floor, installation instructions, and release verification are required, and what claim is made for ARM64 Linux source builds?

## Answer

Ship `fiew-v0.2.0-linux-x86_64.tar.gz`, containing one executable named `fiew`, with a matching `.sha256` file. Build the executable for a baseline x86_64 CPU, link it statically against musl, and document installation at `$HOME/.local/bin/fiew`. Do not require root access or provide an installer, package-manager package, or bundled runtime tools.

The verified compatibility floor is Ubuntu 22.04 with Linux 5.15 or later. Other x86_64 Linux distributions meeting the kernel floor are expected to work but remain best-effort unless explicitly tested.

Gate the Linux release on deterministic tests on Ubuntu 22.04 x86_64, exact `fiew --version` output, ELF architecture and static-linkage inspection, clean archive extraction and execution, SHA-256 verification, and Linux TTY smoke tests for startup, resize, keyboard input, and terminal restoration in Ghostty, Kitty, and WezTerm.

Require `aarch64-linux-musl` compilation with Zig 0.16.0 and locked dependencies in CI. Claim only that v0.2 is buildable from source for ARM64 Linux. Do not publish an ARM64 archive or promise ARM64 runtime compatibility and terminal smoke testing.

## Comments
## Resolution

Decision owner approved the complete Linux artifact contract on 2026-08-28.
