---
id: ISSUE-0006
title: "Define the modal interaction language"
kind: "clarification"
status: resolved
created: 2026-08-25
assignee: 
parent: "ISSUE-0001-plan-fiew-v0-1.md"
blocked_by:
  - "ISSUE-0003-define-the-v0-1-workflows-and-feature-boundary.md"
labels: []
---
# Define the modal interaction language

## Question

Which Helix/Kakoune-inspired selection, movement, mode, command, and discoverability rules should form fiew's coherent v0.1 interaction model?

## Comments
## Resolution

Accepted: v0.1 uses a selection-first, single-selection modal language.

## Modes and selection

- Normal mode movement replaces the active selection.
- Extend mode keeps a fixed anchor while movement extends the selection.
- Command mode is a temporary named-command prompt. It may also host a transient Note Composer for editing fiew-owned review-note text; this does not permit source editing.
- The Note Composer accepts multiline UTF-8 plain text. Normal modal bindings are suspended while typing. `Ctrl-Enter` saves; `Esc` cancels and asks for confirmation only when modified. Stable `note-save` and `note-discard` command identifiers expose both actions.
- Pane focus and workflow context are application state, not modes.
- Insert and Replace modes, multiple or discontiguous selections, macros, syntax-object selections, and search-result selections are deferred.
- `v` toggles Extend mode. `Esc` returns to Normal mode, cancels transient interaction, and collapses to the active end when leaving Extend mode.
- `x` selects the current line, `;` collapses to the active end, and `Alt-;` reverses anchor and active ends.
- Mouse click replaces the selection; mouse drag creates an extended selection.

## Movement

- `h j k l` move by character or line; `w b e` move by words; `g g` and `g e` move to document start and end.
- `Ctrl-u` and `Ctrl-d` move by half pages; PageUp and PageDown move by full pages.
- Movement operates on displayed grapheme clusters and never selects inside a UTF-8 code point or displayed grapheme cluster.
- Vertical movement preserves a preferred visual column across short lines and tabs, selecting the nearest valid target while retaining that preferred column.
- Tree-sitter structural movement is deferred until parsing architecture is settled.

## Command language

- `Space` opens a discoverable leader menu; `:` opens a searchable named-command prompt. Both invoke one command registry.
- Unavailable commands remain visible and disabled with a concise reason.
- `Enter` opens or activates the selection; `g d` goes to definition; `Ctrl-o` and `Ctrl-i` traverse location history.
- `z` opens the folding namespace. `Space f`, `Space b`, `Space g`, and `Space r` enter repository-file, project, Git/diff, and review-note actions respectively.
- `q` closes a transient view but does not quit the application. Quitting requires explicit `:quit` or its leader command.
- Detailed pane, diff, folding, and review-note commands remain with their owning issues.

## Feedback and configuration

- The status line always shows mode, focused context, pending keys, and concise command or error feedback.
- `Esc` safely cancels leader menus, prompts, and pending sequences without changing the selection. Invalid or timed-out sequences explain the failure and return to Normal mode without changing application state.
- v0.1 has a fixed keymap. User remapping and macros are deferred.
- Commands have stable identifiers, and `Space ?` displays a key reference generated from the command registry.
