---
id: ISSUE-0068
title: "Produce and verify the Skaut v0.2 release artifacts"
kind: "implementation"
status: resolved
created: 2026-08-28
assignee: "agent"
parent: "ISSUE-0057-implement-fiew-v0-2.md"
blocked_by:
  - "ISSUE-0067-verify-the-integrated-fiew-v0-2-workflows.md"
labels: []
---
# Produce and verify the Skaut v0.2 release artifacts

## Parent

[Skaut v0.2](<docs/specs/fiew-v0-2.md>)

## What to build

Deliver installable, deterministic v0.2 archives and checksums whose documented platform claims match verified behavior.

## Acceptance criteria

- [ ] Apple Silicon macOS and static baseline x86_64 Linux archives are deterministic and contain the expected `skaut` executable.
- [ ] The Linux archive is named `skaut-v0.2.0-linux-x86_64.tar.gz` and has a matching SHA-256 file.
- [ ] Version output, ELF architecture and static linkage, checksum verification, and clean extraction/execution pass on Ubuntu 22.04.
- [ ] The locked source compiles for ARM64 Linux without publishing an ARM64 archive or runtime claim.
- [ ] Installation, optional-tool, compatibility-floor, best-effort-terminal, and release documentation match tested evidence.

## Blocked by

Managed by native issue relationships.

## Out of scope

Signing, notarization, package managers, automatic updates, Windows, Intel macOS, and ARM64 Linux release artifacts.

## Comments
## Resolution

Delivered deterministic Skaut v0.2 packaging for Apple Silicon macOS and baseline static x86_64 Linux.

`tools/package-release.py` now emits both `skaut-v0.2.0-darwin-arm64.tar.gz` and `skaut-v0.2.0-linux-x86_64.tar.gz` with matching SHA-256 files. Each archive contains exactly one executable named `skaut`. The default packages both targets; `--platform darwin-arm64` and `--platform linux-x86_64` support isolated builds. Release builds use ReleaseSafe, Linux uses a baseline CPU and musl, archive timestamps derive from `SOURCE_DATE_EPOCH` or the release commit, and tar ownership and gzip metadata are normalized. Absolute and repository-relative output directories are supported.

README installation guidance now covers checksum verification and rootless installation for both platforms, the Ubuntu 22.04/Linux 5.15 floor, verified and best-effort terminals, optional Git and ZLS behavior, unsigned and unnotarized macOS binaries, and the ARM64 Linux source-build-only boundary. The managed Skaut v0.2 release checklist records the clean-checkout gate, exact commands, deterministic rebuild comparison, platform inspection, terminal evidence, and manual publication boundary while preserving the historical fiew v0.1 release.

Verification passed from the working tree and from a clean committed verification snapshot. Two consecutive package runs produced identical checksum files. Both checksums verified and both archives listed only `skaut`. The macOS artifact was Mach-O ARM64, used only the system library, and reported `skaut 0.2.0`. The Linux artifact was a statically linked x86-64 ELF; clean extraction and execution in Ubuntu 22.04 x86_64 reported `skaut 0.2.0`. The baseline `aarch64-linux-musl` source build passed without producing an ARM64 release artifact. Deterministic tests, combined Git/ZLS integrations, formatting, Python compilation, single-platform packaging, and `git diff --check` passed.

No v0.2 tag or GitHub release was published by this issue.
