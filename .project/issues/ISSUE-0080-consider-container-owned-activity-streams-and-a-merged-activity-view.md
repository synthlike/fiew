---
id: ISSUE-0080
title: "Consider container-owned activity streams and a merged Activity view"
kind: "clarification"
status: open
created: 2026-09-01
assignee:
parent: "ISSUE-0074-plan-fiew-v0-3.md"
blocked_by:
labels: []
---
# Consider container-owned activity streams and a merged Activity view

## Question

Should each durable Discovery or Review own a typed append-only activity stream for comments, anchor transitions, lifecycle changes, links, and Trail proposal or acceptance events, with an optional editor-wide Activity view produced only as a merged projection?

## Notes

A merged editor-wide log should not become a second source of truth. Container ownership would preserve repository scope, archival history, privacy, recovery, and artifact authority while permitting a future chronological Activity surface.

This is a Skaut v0.3 planning question. Resolve its release disposition without expanding the v0.2 boundary.

## Comments

## Resolution
