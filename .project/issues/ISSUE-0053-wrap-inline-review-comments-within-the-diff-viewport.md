---
id: ISSUE-0053
title: "Wrap inline review comments within the Diff viewport"
kind: "defect"
status: open
created: 2026-08-28
assignee:
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
