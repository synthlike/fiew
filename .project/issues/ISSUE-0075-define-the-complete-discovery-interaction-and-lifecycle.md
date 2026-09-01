---
id: ISSUE-0075
title: "Define the complete Discovery interaction and lifecycle"
kind: "clarification"
status: resolved
created: 2026-09-01
assignee: "agent"
parent: "ISSUE-0074-plan-fiew-v0-3.md"
blocked_by:
labels: []
---
# Define the complete Discovery interaction and lifecycle

## Question

How does a human start, open, browse, archive, and restore a named Discovery; create and navigate source-anchored Discovery Threads; and mark them Answered, reopen them, or archive them without inheriting Review approval behavior?

## Answer

- A Discovery is durable and named. A human may explicitly create and select an empty Discovery.
- Creating a first Discovery Thread without a current Discovery composes a required Discovery title and non-empty initial question as one transaction. Cancellation or persistence failure creates neither artifact and leaves current selection unchanged.
- A Discovery Thread anchors the active contiguous repository-source selection, falling back to the active line when collapsed. Whole-file anchors, External files, and direct Review Diff creation are excluded.
- The initial question is the first immutable human Comment. Its first non-empty line provides the bounded thread summary; no separate thread title is required.
- `Space d` owns a dedicated Discovery namespace. `Space d t` shows current threads, `Space d n` creates a thread, `Space d a` appends a human Comment, `Space d r` marks Answered or reopens, `Space d x` archives a thread, and `Space d o` opens or switches Discovery. Rename, container archive/restore, and archived browsing remain explicit generated-menu and named commands.
- Opening Discovery shows current Discovery Threads when current exists and otherwise shows the Discovery list. Switching is explicit.
- Selecting a thread previews its source anchor and renders only that conversation beneath the range as virtual read-only rows. Preview movement does not alter history; `Enter` pins the source and adds one history entry.
- Threads list Open before Answered and retain creation order within each group. Rows show path, range, and Current or Outdated anchor validity. Archived threads require an explicit filter.
- The Discovery list shows current first, then other active Discoveries by descending last activity. Agent replies count as activity but never change current. Archived Discoveries require an explicit filter.
- Discovery titles are bounded human-editable labels, not identities, and need not be unique. Only active Discoveries may be renamed.
- Answered and Archived threads reject new human and agent Comments. A human must reopen an Answered thread first. An Open Outdated thread remains discussable because anchor validity is independent of lifecycle.
- Archiving an Answered thread is immediate. Archiving an Open thread requires confirmation. Restoration recovers its previous Open or Answered lifecycle.
- Archiving a Discovery with Open threads requires confirmation and preserves every thread lifecycle and anchor validity. Archiving current clears the pointer without selecting another Discovery.
- Opening archived state fails without mutation. Explicit restoration restores and selects the Discovery.
- v0.3 provides archival and restoration, not permanent deletion. A later purge design must preserve structured-reference integrity.

## Comments
## Resolution

Accepted by decision owner synthlike. Discovery uses the approved durable named-container, transactional first-question, source-selection anchor, explicit lifecycle, archive/restore, current-pointer, thread presentation, ordering, and `Space d` interaction behavior recorded above.
