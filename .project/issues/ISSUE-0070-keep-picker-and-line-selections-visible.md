---
id: ISSUE-0070
title: "Keep picker and line selections visible"
kind: "implementation"
status: resolved
created: 2026-08-28
assignee: "agent"
parent: "ISSUE-0057-implement-fiew-v0-2.md"
blocked_by:
labels: []
---
# Keep picker and line selections visible

## Parent

[Implement fiew v0.2](<.project/issues/ISSUE-0057-implement-fiew-v0-2.md>)

## What to build

Keep active selections visible when navigating the file finder or repeatedly extending whole-line selections in a document, and support Tab-based finder movement.

## Acceptance criteria

- [ ] File finder selection scrolling uses the visible result-row count rather than the main document height.
- [ ] `Tab` previews the next finder result and `Shift-Tab` previews the previous result while arrow movement remains available.
- [ ] Repeated `x` keeps the active selected line within the File viewport.
- [ ] Reducer and fixed-dimension regression tests cover movement beyond each visible viewport.
- [ ] Offline deterministic tests pass without source or Git mutation.

## Blocked by

None.

## Out of scope

Mouse picker interaction, changes to fuzzy ranking, alternate finder layouts, and changes to general document movement semantics.

## Comments
## Resolution

Fixed both selection visibility defects and added Tab-based finder movement.

The finder now derives navigation scrolling from its rendered result-row count, including after terminal resize, rather than from the taller document viewport. `Tab` previews the next result and `Shift-Tab` previews the previous result; arrow movement remains available. Repeated `x` now applies the existing document visibility adjustment after extending a whole-line selection in a visible source view.

Added reducer regressions that move beyond a three-row finder viewport and a five-row File viewport, plus fixed-dimension finder-row tests.

Verification:
- `zig build`
- `zig build test`
- `zig build test -Dgit-integration=true`
- `zig fmt --check src build.zig`
- `git diff --check`
