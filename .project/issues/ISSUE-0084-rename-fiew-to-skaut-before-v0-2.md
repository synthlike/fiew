---
id: ISSUE-0084
title: "Rename fiew to Skaut before v0.2"
kind: "implementation"
status: open
created: 2026-09-01
assignee: 
parent: "ISSUE-0057-implement-fiew-v0-2.md"
blocked_by:
labels: []
---
# Rename fiew to Skaut before v0.2

## What to build

Replace the complete current product identity with Skaut before v0.2. Rename code, executable, private schemas, global state, package and distribution identities, Agent Skill, current documentation, active planning references, and repository hosting without adding compatibility behavior for old names.

Preserve the established Discovery, Review, Concern, Spot, Trail, Thread, Comment, and Anchor vocabulary. Preserve immutable historical record references and the factual fiew v0.1 release history.

## Acceptance criteria

- [ ] Current product and UI identity is **Skaut**; executable, repository, Zig package, install paths, and global state use `skaut`; environment variables use `SKAUT_*`; private schemas use `skaut.<artifact>/v<version>`.
- [ ] Generic repository-local directories remain domain-named, including `.reviews/`, `.bookmarks/`, `.trails/`, `.discoveries/`, and `.spots/` where applicable.
- [ ] No aliases, migration, fallback paths, old-name detection, or special diagnostics handle fiew identities or state.
- [ ] Current code, tests, Agent Skill, documentation, packaging, release guidance, active plans, and repository links consistently use Skaut.
- [ ] Immutable record references and truthful historical fiew v0.1 release artifacts remain intact.
- [ ] The unscoped npm package name is not used; any future npm launcher requires a scoped identity such as `@synthlike/skaut`.
- [ ] Integrated builds, tests, packaging checks, clean-archive execution, links, and active-surface identity audits pass.

## Blocked by

None.

## Out of scope

Changing established domain vocabulary, migrating or deleting old state, republishing or relabeling fiew v0.1 artifacts as Skaut, publishing v0.2, and reserving an unscoped npm package.

## Comments


## Resolution
