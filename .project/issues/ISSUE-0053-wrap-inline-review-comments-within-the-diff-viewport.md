---
id: ISSUE-0053
title: "Wrap inline review comments within the Diff viewport"
kind: "defect"
status: resolved
created: 2026-08-28
assignee: "agent"
parent: "ISSUE-0013-implement-fiew-v0-1.md"
blocked_by:
labels: []
---
# Wrap inline review comments within the Diff viewport

## Outcome

Long inline review comments remain fully readable within the visible Diff viewport, and reviewer and agent contributions are visually distinct.

## Acceptance criteria

- [ ] Inline comment text wraps within the available Diff-view width.
- [ ] Continuation rows retain their author-specific review-comment styling and do not overwrite subsequent diff rows.
- [ ] Reviewer comments use a distinct color from agent comments in both the author label and body.
- [ ] Resolved threads remain visibly dimmed without losing author distinction.
- [ ] Vertical scrolling can reach all wrapped comment content.
- [ ] Resizing reflows inline comments to the new viewport width.
- [ ] Narrow-width automated coverage includes long ASCII and Unicode comments from both authors.

## Reported impact

A reviewer observed that a long comment shown inline in Diff view goes far enough right that part of it is outside the screen and cannot be read.

## Evidence

The current inline-comment render path emits each logical comment line as one visual row with wrapping disabled. It bounds the emitted row to the viewport rather than laying remaining content onto continuation rows.

Related to ISSUE-0033, which introduced reviewer-owned review threads, and commit `ae420f8`, which introduced inline review comments.

## Blockers

None identified. This is required v0.1 presentation work.

## Comments
## Resolution

Completed the inline review-comment wrapping fix.

- Replaced implicit terminal wrapping with explicit grapheme-aware visual rows that retain the comment gutter and author-specific styling on every continuation row.
- Sanitized comment body control characters before rendering.
- Added visual-row Diff paging so PageUp, PageDown, Ctrl-u, and Ctrl-d can reach wrapped content without changing the selected diff line; ordinary line movement resets the visual offset.
- Kept reviewer and agent colors distinct in labels and bodies and retained resolved-thread dimming.
- Recomputes wrapped rows from the current viewport width on every draw, so resize reflows content.
- Added narrow ASCII and Unicode wrapping coverage, author-style coverage, resize/reflow coverage, visual-row clipping coverage, and paging state/command coverage.

Verification passed with `zig fmt --check src build.zig`, `zig build test`, `zig build`, and `git diff --check`.
