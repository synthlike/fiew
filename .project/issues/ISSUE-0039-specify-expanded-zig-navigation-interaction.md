---
id: ISSUE-0039
title: "Specify expanded Zig navigation interaction"
kind: "clarification"
status: resolved
created: 2026-08-27
assignee: "agent"
parent: "ISSUE-0030-plan-fiew-v0-2.md"
blocked_by:
labels: []
---
# Specify expanded Zig navigation interaction

## Question

How should definition results, reference lists, and hover documentation appear, navigate, dismiss, preserve history, and report unavailable or stale ZLS state?

## Answer

`g d` requests the definition for the active Zig selection. One valid result opens immediately. Multiple valid results open a transient list showing path, line, and source preview. `g r` requests references and opens the same result-list pattern, grouped by file and ordered by repository path then source position. Include a declaration only when ZLS returns it. Valid locations outside the repository are allowed, remain read-only, and carry an **External** label.

Moving through definition or reference results with `j`/`k` or arrows updates only the preview and does not add history. `Enter` closes the list, pins the selected location, and adds exactly one origin entry. `Esc` closes it without changing the view or history. `Ctrl-o` returns to the origin and `Ctrl-i` moves forward again. Omit invalid results; report when no valid results remain. Display at most 5,000 results and report truncation explicitly.

`K` requests hover documentation and type information for the active Zig selection. Show sanitized Markdown as terminal text in a bounded, scrollable overlay without moving selection or adding history. Preserve unsupported markup as readable plain text. `j`/`k` scroll long content; `Esc` or `q` dismisses it. A new hover replaces the old one, and document navigation or snapshot replacement dismisses it. Report when hover information is unavailable.

Show non-blocking pending status after 100 milliseconds. `Esc` cancels an active request. Definition and hover requests time out after two seconds; reference requests time out after five seconds. A newer request or changed document cancels the older request. Late, stale, malformed, mismatched, and invalid responses never navigate or replace visible information.

Report concise exact states such as **ZLS untrusted**, **not installed**, **incompatible**, **starting**, **timed out**, **crashed**, or **result discarded because the document changed**. Every failure preserves selection, view, and history. Never use heuristic navigation as a fallback.

The accepted repository trust, ZLS lifecycle, position conversion, read-only enforcement, and External-file contracts remain in force.

## Comments
## Resolution

Decision owner approved the complete expanded Zig/ZLS navigation interaction on 2026-08-28.
