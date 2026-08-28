---
id: ISSUE-0072
title: "Unify active selection behavior and restore Review Diff ranges"
kind: "implementation"
status: resolved
created: 2026-08-28
assignee: "agent"
parent:
blocked_by:
labels: []
---
# Unify active selection behavior and restore Review Diff ranges

## Parent

The selection-first modal interaction and Review Diff behavior defined by the fiew v0.1 specification and retained by fiew v0.2.

## What to build

Route selection operations consistently through the active main-view context so document and Review Diff selections share one observable interaction language, and make Review Diff ranges visibly agree with the range used for thread anchors.

## Acceptance criteria

- [ ] `v` anchors the active diff line and movement visibly highlights the complete contiguous range.
- [ ] `x` selects the active diff line and repeated `x` extends the linewise selection downward.
- [ ] `;` collapses a Review Diff selection to its active line and `Alt-;` reverses its active and anchored ends.
- [ ] Normal movement clears an `x` Review Diff range like document movement, while Extend movement preserves its anchor.
- [ ] `Esc` clears an explicit Review Diff range while preserving its active cursor.
- [ ] App-level selection operations route toggle, line selection, collapse, reversal, clearing, and movement without command handlers reaching context-specific selection storage.
- [ ] Review Diff selection styling remains distinct from its active cursor and preserves addition/deletion presentation.
- [ ] Thread creation captures exactly the visible one-side range and continues to refuse mixed-side ranges.
- [ ] Command, reducer, anchor, and fixed render tests cover `v`, `x`, movement, collapse, reversal, clearing, and multiline selection.

## Blocked by

None.

## Out of scope

Multiple selections, selection persistence across Git refresh, changing thread anchor rules, source editing, or a generic view framework.

## Comments
## Resolution

Implemented a consistent App-level selection routing boundary for document and Review Diff contexts. Command dispatch now routes Extend toggling and line selection through the App alongside routed movement, collapse, reversal, and explicit-range clearing. Review Diff owns linewise select, collapse, reverse, clear, and selected-range projection without leaking that storage into command handling.

Review Diff now visibly reverses every selected line while preserving addition/deletion colors. The active cursor remains distinct through bold underline styling. `v` plus movement and repeated `x` produce contiguous visible ranges; normal movement exits an `x` range while Extend movement preserves its anchor; `;` and `Alt-;` collapse and reverse ranges; `Esc` clears either an `x` or `v` range while retaining the cursor. Thread creation continues to consume the same projected range and mixed-side capture remains refused.

Verification passed:

- `zig build test`
- `zig build -Dtarget=x86_64-linux-musl`
- `zig build -Dtarget=aarch64-linux-musl`

Reducer coverage exercises production `x`, `v`, Normal and Extend movement, collapse, reversal, clearing, and multiline thread creation. Review-model tests cover linewise range projection and clearing, and render-seam tests distinguish selected, active, and idle diff styles.
