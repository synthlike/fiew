---
id: ISSUE-0087
title: "Transition repository hosting and verify the complete Skaut identity"
kind: "implementation"
status: resolved
created: 2026-09-01
assignee: "agent"
parent: "ISSUE-0084-rename-fiew-to-skaut-before-v0-2.md"
blocked_by:
  - "ISSUE-0085-rename-the-executable-and-persistence-contracts-to-skaut.md"
  - "ISSUE-0086-rename-current-documentation-agent-skill-and-distribution-surfaces-to-skaut.md"
labels: []
---
# Transition repository hosting and verify the complete Skaut identity

## Parent

The Skaut rename initiative.

## What to build

Make `synthlike/skaut` the canonical repository and verify the complete renamed product from source checkout through packaged execution and Agent Skill installation. Rename the GitHub repository, update the local remote, validate redirects and current links, and run integrated identity and distribution checks.

Keep the existing v0.1.0 tag, release title, fiew binary, and fiew-named assets as truthful historical artifacts. Leave the first Skaut release to the v0.2 release workflow.

## Acceptance criteria

- [ ] GitHub hosts the canonical repository at `synthlike/skaut`, the local `origin` uses that location, and the old repository URL redirects.
- [ ] Current repository, installation, source, issue, and Agent Skill links resolve through the new canonical location.
- [ ] The published v0.1.0 release remains unchanged and accurately represents fiew v0.1.
- [ ] A clean package dry run produces a Skaut archive whose extracted `skaut --version` succeeds and whose checksum verifies.
- [ ] The public Skaut Agent Skill installs from the renamed repository and references only current commands.
- [ ] Full tests, native builds, supported cross-build checks, packaging verification, and an active-surface old-name audit pass.
- [ ] No v0.2 release is published by this issue.

## Blocked by

The executable/persistence rename and the documentation/Skill/distribution rename.

## Out of scope

Publishing v0.2, rewriting the v0.1 tag or release assets, reserving npm names, state migration or deletion, and changing domain vocabulary.

## Comments
## Resolution

Renamed the GitHub repository to `synthlike/skaut` and updated the local `origin` to `git@github.com-synthlike:synthlike/skaut.git`. The canonical repository, README, public Skill path, raw Skill document, and issue page return successfully from the new location. The old `https://github.com/synthlike/fiew` repository and Git transport URLs redirect to the canonical repository.

The v0.1.0 release remains unchanged: its title is `fiew v0.1.0`; its tag still resolves to the original commit; its two fiew-named assets retain their IDs, timestamps, sizes, and digests; the published checksum verifies; and the extracted historical binary reports `fiew 0.1.0`. The repository has no v0.2 release or tag.

A temporary project successfully installed the public `skaut` Agent Skill from `synthlike/skaut` for Pi. The installed Skill identifies itself as `skaut`, contains the current `skaut review` commands, and contains no old product command.

Verification from a clean canonical checkout passed `zig fmt --check build.zig src`, `zig build test`, `zig build test-binaries`, native `zig build`, exact `skaut 0.2.0` output, baseline static `x86_64-linux-musl` and `aarch64-linux-musl` builds, and a clean package dry run. The package checksum verified, the archive contained only `skaut`, and the extracted executable reported `skaut 0.2.0`. Active source, tooling, Skill, documentation, and open-issue audits found no unintended old identity; remaining fiew references are truthful history, rename requirements, or immutable record paths.
