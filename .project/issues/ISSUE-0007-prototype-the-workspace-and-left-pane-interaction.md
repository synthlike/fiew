---
id: ISSUE-0007
title: "Prototype the workspace and left-pane interaction"
kind: "prototype"
status: resolved
created: 2026-08-25
assignee: 
parent: "ISSUE-0001-plan-fiew-v0-1.md"
blocked_by:
  - "ISSUE-0003-define-the-v0-1-workflows-and-feature-boundary.md"
  - "ISSUE-0006-define-the-modal-interaction-language.md"
labels: []
---
# Prototype the workspace and left-pane interaction

## Question

Which layout and focus behavior makes project navigation, Git state, review notes, code, and diffs fast to inspect without overwhelming the terminal workspace?

## Comments
## Resolution

Accepted from a disposable conversational layout prototype: v0.1 uses a collapsible, single-context left sidebar beside one main view.

## Workspace

- Show one main view at a time. Opening a file or diff replaces it; `Ctrl-o` and `Ctrl-i` traverse pinned location history.
- Defer tabs, arbitrary splits, and simultaneous main views.
- At 100 columns or wider, show the sidebar beside the main view at 30% width, clamped to 24–40 columns.
- Below 100 columns, show the sidebar as a full-height overlay.
- Below 60×20, show an unsupported-size message rather than a degraded workspace.
- Preserve sidebar context, selection, scroll position, and collapsed state across resize.

## Sidebar contexts

- Show exactly one of Project, Git, or Review at a time, with the active context named in the header.
- `Space b`, `Space g`, and `Space r` open and focus the corresponding context. Repeating `Space b` while Project is focused collapses the sidebar.
- Preserve independent selection and scroll state for each context.
- Project uses a directory tree. Git groups changed files by working-tree status. Review groups notes by file and source location.
- `h` collapses or moves to a parent; `l` expands or enters an item. `Enter` activates the selected item, including expanding or collapsing group nodes.
- Group headers do not preview content. Files, diffs, and notes do.

## Focus and preview

- Moving selection in the sidebar previews the corresponding file, diff, or note immediately without moving focus or altering location history.
- `Enter` on a preview pins it, records a history location, and focuses the main view.
- `Esc` cancels the preview and restores the last pinned main view while preserving sidebar focus.
- Collapsing the sidebar also restores the pinned view. If no view has been pinned, cancellation shows an empty welcome view.
- `Tab` and `Shift-Tab` cycle focus; mouse click focuses the clicked region.
- The focused region has an emphasized border or header. Modal keys operate only within that region.

Detailed diff presentation, Git states, and review-note lifecycle remain for ISSUE-0009. The prototype was intentionally not persisted because the configured prototypes route is disabled; this accepted conclusion is recorded in the requesting issue.
