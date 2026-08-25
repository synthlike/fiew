---
id: ISSUE-0003
title: "Define the v0.1 workflows and feature boundary"
kind: "clarification"
status: resolved
created: 2026-08-25
assignee: 
parent: "ISSUE-0001-plan-fiew-v0-1.md"
blocked_by:
  - "ISSUE-0002-decide-the-v0-1-editing-boundary.md"
labels: []
---
# Define the v0.1 workflows and feature boundary

## Question

Which concrete viewing, diff-review, and navigation workflows must the v0.1 vertical slice complete, and which desired capabilities are explicitly deferred?

## Comments
## Resolution

Accepted: v0.1 must complete three read-first workflows:

1. Browse code: open a repository, find and open files, inspect their structure, and move through or fold code.
2. Review a diff: inspect the current repository diff, move among changed files and hunks, open surrounding code, and create fiew-owned review notes.
3. Navigate code: jump to a symbol definition and return, with a graceful fallback when no language server is available.

Defer project-wide or full-text search, references and rename, source editing, Git staging or committing, merge and conflict workflows, and rich Mermaid interaction. This boundary preserves a coherent read-first vertical slice; detailed Git, LSP, layout, and Mermaid behavior remains for their dependent issues.
