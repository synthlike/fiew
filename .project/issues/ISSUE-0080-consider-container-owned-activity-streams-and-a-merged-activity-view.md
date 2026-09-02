---
id: ISSUE-0080
title: "Consider container-owned activity streams and a merged Activity view"
kind: "clarification"
status: open
created: 2026-09-01
assignee:
parent:
blocked_by:
labels: []
---
# Consider container-owned activity streams and a merged Activity view

## Question

Should each durable Discovery or Review own a typed append-only activity stream for comments, anchor transitions, lifecycle changes, links, and Trail proposal or acceptance events, with an optional editor-wide Activity view produced only as a merged projection?

## Notes

A merged editor-wide log should not become a second source of truth. Container ownership would preserve repository scope, archival history, privacy, recovery, and artifact authority while permitting a future chronological Activity surface.

This is not part of Skaut v0.2 and has no assigned release. Capture it without expanding the current release boundary.

## Comments

## Resolution
