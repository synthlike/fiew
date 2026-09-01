---
id: ISSUE-0085
title: "Rename the executable and persistence contracts to Skaut"
kind: "implementation"
status: open
created: 2026-09-01
assignee: 
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
