---
id: ISSUE-0085
title: "Rename the executable and persistence contracts to Skaut"
kind: "implementation"
status: resolved
created: 2026-09-01
assignee: "agent"
parent: "ISSUE-0084-rename-fiew-to-skaut-before-v0-2.md"
blocked_by:
labels: []
---
# Rename the executable and persistence contracts to Skaut

## Parent

The Skaut rename initiative.

## What to build

Make the compiled program and every current machine-facing identity Skaut. Rename the Zig package and module imports, executable, installed test binaries, runtime labels, help and version output, private schema prefixes, and platform global-state paths. Regenerate the Zig package fingerprint for the new package identity.

Keep generic repository-local artifact directories unchanged. Introduce no compatibility behavior for fiew names or state.

## Acceptance criteria

- [ ] `zig build` installs only a `skaut` executable, and installed test binaries use Skaut names.
- [ ] Zig package metadata, module imports, runtime labels, help, errors, UI text, and version output use `skaut` or **Skaut** consistently.
- [ ] New canonical data uses `skaut.review/v1`, `skaut.bookmark/v1`, `skaut.trail/v1`, and `skaut.global/v1` as applicable.
- [ ] Global state uses `$HOME/Library/Application Support/skaut` on macOS and the `skaut` child of the accepted XDG paths on Linux.
- [ ] `.reviews/`, `.bookmarks/`, and `.trails/` remain unchanged, and no alias, migration, fallback, old-name detection, or special old-state diagnostic is added.
- [ ] Model, adapter, CLI, render, and state-path fixtures cover the new identity.
- [ ] `zig build test`, `zig build`, and formatting checks pass.

## Blocked by

None.

## Out of scope

Agent Skill and broad documentation updates, GitHub repository administration, changing domain vocabulary, deleting old state, and publishing a release.

## Comments
## Resolution

Renamed the complete compiled and machine-facing identity to Skaut.

The Zig package and module are now `skaut` with a regenerated package fingerprint. Clean builds install `skaut`, `skaut-core-tests`, and `skaut-executable-tests`. CLI usage, errors, version output, commands, terminal labels, LSP client identity, and read-only refusal messages use the accepted Skaut naming convention.

Canonical Review, Bookmark, Trail, and global schemas now use `skaut.*`; public Markdown comment markers use `skaut-comment`; and macOS/XDG global-state paths use `skaut`. Generic repository-local artifact directories remain unchanged. No alias, migration, fallback, or old-name handling was added.

Verification passed: clean `zig build`, `zig build test`, `zig build test-binaries`, modified-source `zig fmt --check`, `git diff --check`, executable version/help smoke checks, and a source/build audit with no old product identity references.
