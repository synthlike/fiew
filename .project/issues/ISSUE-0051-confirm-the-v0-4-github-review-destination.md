---
id: ISSUE-0051
title: "Confirm the v0.4 GitHub review destination"
kind: "clarification"
status: resolved
created: 2026-08-27
assignee:
parent: "ISSUE-0032-plan-fiew-v0-4.md"
blocked_by:
labels: []
---
# Confirm the v0.4 GitHub review destination

## Question

What remote-review provider and authority model define the v0.4 planning destination?

## Answer

v0.4 targets GitHub pull-request reviews with a local-first model. fiew imports remote diffs and threads, keeps local work useful offline, and mutates GitHub only through explicit publication or submission actions, including COMMENT, REQUEST_CHANGES, and APPROVE. Source and local Git state remain read-only; other forge providers are excluded.

## Comments
## Resolution

Accepted by the decision owner during the roadmap clarification session on 2026-08-27. The answer in this ticket is the confirmed release boundary and is indexed by its initiative map.
