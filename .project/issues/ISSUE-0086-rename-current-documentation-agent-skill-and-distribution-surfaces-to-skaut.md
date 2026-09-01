---
id: ISSUE-0086
title: "Rename current documentation, Agent Skill, and distribution surfaces to Skaut"
kind: "implementation"
status: open
created: 2026-09-01
assignee: 
parent: "ISSUE-0084-rename-fiew-to-skaut-before-v0-2.md"
blocked_by:
  - "ISSUE-0085-rename-the-executable-and-persistence-contracts-to-skaut.md"
labels: []
---
# Rename current documentation, Agent Skill, and distribution surfaces to Skaut

## Parent

The Skaut rename initiative.

## What to build

Make every current human-facing and agent-facing surface describe and distribute Skaut. Rename the public Agent Skill, current README and authoritative requirements, active engineering and release guidance, package tooling, archive/checksum names, smoke-test commands, and active roadmap wording through their configured record adapters. Record the accepted clean-break rename as an ARP.

Preserve immutable record references, factual historical fiew v0.1 wording, and the actual v0.1 release artifacts.

## Acceptance criteria

- [ ] The public skill lives at `skills/skaut`, identifies itself as `skaut`, invokes the `skaut` CLI, and installs from `synthlike/skaut` with `--skill skaut`.
- [ ] Current README, v0.2 requirements, active engineering guidance, package tooling, archive names, checksums, and smoke tests consistently use Skaut.
- [ ] Current packaging emits `skaut-v<version>-<platform>` artifacts containing the `skaut` executable.
- [ ] Active roadmap and open-issue wording is updated through the issue adapter; other authoritative records are changed through their configured adapters.
- [ ] An accepted ARP records the complete rename, new schemas and paths, no-compatibility boundary, unchanged domain vocabulary, historical-record treatment, and release consequences.
- [ ] Historical record references and truthful fiew v0.1 descriptions remain intact rather than being manually renamed.
- [ ] Documentation does not promise the occupied unscoped npm name; any future npm launcher is explicitly scoped.
- [ ] Documentation, skill, package, link, and active-surface identity checks pass.

## Blocked by

The executable and persistence contract rename.

## Out of scope

GitHub repository administration, rewriting opaque record paths, relabeling old release bytes, publishing v0.2, migrating state, and changing domain vocabulary.

## Comments


## Resolution
