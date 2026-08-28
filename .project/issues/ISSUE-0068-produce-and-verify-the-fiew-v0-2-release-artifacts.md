---
id: ISSUE-0068
title: "Produce and verify the fiew v0.2 release artifacts"
kind: "implementation"
status: open
created: 2026-08-28
assignee:
parent: "ISSUE-0057-implement-fiew-v0-2.md"
blocked_by:
  - "ISSUE-0067-verify-the-integrated-fiew-v0-2-workflows.md"
labels: []
---
# Produce and verify the fiew v0.2 release artifacts

## Parent

[fiew v0.2](<docs/specs/fiew-v0-2.md>)

## What to build

Deliver installable, deterministic v0.2 archives and checksums whose documented platform claims match verified behavior.

## Acceptance criteria

- [ ] Apple Silicon macOS and static baseline x86_64 Linux archives are deterministic and contain the expected `fiew` executable.
- [ ] The Linux archive is named `fiew-v0.2.0-linux-x86_64.tar.gz` and has a matching SHA-256 file.
- [ ] Version output, ELF architecture and static linkage, checksum verification, and clean extraction/execution pass on Ubuntu 22.04.
- [ ] The locked source compiles for ARM64 Linux without publishing an ARM64 archive or runtime claim.
- [ ] Installation, optional-tool, compatibility-floor, best-effort-terminal, and release documentation match tested evidence.

## Blocked by

Managed by native issue relationships.

## Out of scope

Signing, notarization, package managers, automatic updates, Windows, Intel macOS, and ARM64 Linux release artifacts.

## Comments

## Resolution
