---
id: ISSUE-0074
title: "Plan Skaut v0.3"
kind: "initiative"
status: open
created: 2026-09-01
assignee:
parent:
blocked_by:
labels: []
---
# Plan Skaut v0.3

## Destination

Settle the observable Discovery behavior and shared Review/Discovery boundaries needed to author a coherent Skaut v0.3 specification centered on Skaut's main human-agent code-understanding workflow.

## Notes

Consult [Add durable Discoveries and explanatory Trails alongside Reviews](<docs/rfcs/RFC-0004.md>), [Keep Discovery and Review distinct while sharing anchored artifacts](<docs/decisions/ARP-0013.md>), and [Human-agent code understanding](<docs/domain/human-agent-code-understanding.md>).

Discovery is knowledge-oriented; Review remains approval-oriented. Both remain read-only with respect to source and Git state. v0.3 should polish their primary human-agent use cases rather than accumulate unrelated capabilities.

## Decisions so far

- [Define the complete Discovery interaction and lifecycle](<.project/issues/ISSUE-0075-define-the-complete-discovery-interaction-and-lifecycle.md>) — Discovery uses durable named containers, transactional first-question creation, repository-source threads, explicit human lifecycle, archive/restore, current selection, and a dedicated interaction surface without Review approval behavior.

- [Define Discovery anchors and linked Review Concern behavior](<.project/issues/ISSUE-0076-define-discovery-anchors-and-linked-review-concern-behavior.md>) — Discovery preserves exact source selections, re-evaluates through constrained exact context, supports explicit human reassignment provenance, and links independently-lived Review Concerns through separately selected diff anchors.

- [Specify agent Discovery handoff and proposed Trail attachments](<.project/issues/ISSUE-0078-specify-agent-discovery-handoff-and-proposed-trail-attachments.md>) — Agents use current-or-explicit Discovery projections and constrained Open-thread replies, may atomically attach one validated Proposed Trail, and cannot control lifecycle, acceptance, relationships, or current selection.

- [Choose Discovery and generalized Trail persistence compatibility](<.project/issues/ISSUE-0077-choose-discovery-and-generalized-trail-persistence-compatibility.md>) — Clean one-file-per-container and one-file-per-Trail JSON stores use opaque IDs, explicit private-versus-attached Trail references, owner-local recoverable transactions, and purge-only development compatibility; v0.2 Trails move to `.trails/` before release.

## Not yet specified

None beyond the open decision tickets.

## Out of scope

- Go and TypeScript/React multi-language support, which belongs to v0.4.
- GitHub pull-request synchronization, which belongs to v0.5.
- Source editing, Git mutation, automatic archival, fuzzy anchor guessing, and External-file Discovery anchors.
- Treating Trails as inferred execution traces, call graphs, or approval evidence.

## Comments

## Resolution
