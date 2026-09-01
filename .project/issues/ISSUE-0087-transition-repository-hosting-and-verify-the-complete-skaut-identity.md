---
id: ISSUE-0087
title: "Transition repository hosting and verify the complete Skaut identity"
kind: "implementation"
status: open
created: 2026-09-01
assignee: 
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
