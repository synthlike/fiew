---
id: ISSUE-0027
title: "Produce the v0.1 Apple Silicon release artifact"
kind: "implementation"
status: resolved
created: 2026-08-25
assignee: "agent"
parent: "ISSUE-0013-implement-fiew-v0-1.md"
blocked_by:
  - "ISSUE-0026-verify-the-integrated-read-first-workflows.md"
  - "ISSUE-0056-distribute-the-fiew-agent-cooperation-skill.md"
labels: []
---
# Produce the v0.1 Apple Silicon release artifact

## Parent

[Implement fiew v0.1](<.project/issues/ISSUE-0013-implement-fiew-v0-1.md>)

## Source specification

[fiew v0.1](<docs/specs/fiew-v0-1.md>)

## What to build

Produce a `ReleaseSafe` Apple Silicon binary archive from a clean checkout and document manual GitHub Release installation, the Git prerequisite, repository-local review and bookmark storage behavior, and the v0.1 compatibility boundary.

## Acceptance criteria

- [ ] A clean checkout produces the documented archive reproducibly.
- [ ] The artifact runs in Ghostty on supported macOS.
- [ ] Version and linked-dependency information are inspectable.
- [ ] Installation, Git requirements, `.reviews/` canonical JSON and public projections, and `.bookmarks/` storage are documented.
- [ ] Documentation does not claim Markdown source syntax, Mermaid, fuzzy finding, ZLS, Linux, or non-Ghostty support in v0.1.
- [ ] The release checklist does not claim signing, notarization, package-manager support, or automatic publication.

## Blocked by

Managed by native issue relationships.

## Out of scope

Signing, notarization, package managers, automatic release publishing, and v0.2 capabilities.

## Comments
## Resolution

Produced and verified the v0.1 Apple Silicon release artifact workflow.

- Set the package and executable version to `0.1.0` and added `fiew --version` / `fiew version` output containing Zig, libvaxis, Tree-sitter, and tree-sitter-zig versions or immutable revisions.
- Added `tools/package-release.py`, which fetches locked dependencies, builds `ReleaseSafe` for `aarch64-macos`, verifies the executable version and architecture, and writes a deterministic `fiew-v0.1.0-darwin-arm64.tar.gz` plus SHA-256 file.
- Verified two fresh builds from a synthetic clean checkout produced the identical checksum `b30674154572f0d70d90d19cfeb146cf09ba2cf2d1dbed33493d2a98821479cc`.
- Verified the archive contains exactly one executable named `fiew`; extraction, checksum validation, Mach-O ARM64 inspection, version/dependency output, and dynamic linkage inspection passed. The only dynamic dependency is `/usr/lib/libSystem.B.dylib`.
- Added a manual release checklist covering clean-checkout tests, reproducibility, inspection, extracted-artifact Ghostty smoke testing, and manual GitHub Release publication without claiming signing, notarization, package-manager support, or automatic publication.
- Documented checksum-verified installation into `~/.local/bin`, the Git prerequisite, unsigned/unnotarized status, canonical `.reviews/` and `.bookmarks/` JSON storage, public review projections, ignore responsibility, and the v0.1 compatibility boundary in `README.md`.
- Updated the engineering baseline with release packaging and extracted-artifact evidence.
- The reviewer confirmed the extracted archive starts correctly in Ghostty, displays Project and Review Diff, and restores the terminal after normal quit and `Ctrl-C`.

Final verification passed with `zig fmt --check src build.zig build.zig.zon`, `zig build test --summary all`, `zig build test -Dgit-integration --summary all`, Python compilation, and `git diff --check`.
