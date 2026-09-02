---
id: ISSUE-0081
title: "Unify human author roles across Discovery and Review"
kind: "clarification"
status: open
created: 2026-09-01
assignee:
parent:
blocked_by:
labels: []
---
# Unify human author roles across Discovery and Review

## Question

Should a future schema evolution replace the Review-specific `reviewer` author role and Discovery-specific `human` role with one canonical human-author representation across Comments, Trails, activity projections, and agent interfaces?

## Notes

Skaut v0.3 should use `human` for new Discovery projections while preserving `reviewer` in the established `skaut.review/v1` compatibility surface. Any unification must define schema compatibility and migration explicitly rather than silently changing public Review output.

This follow-up has no assigned release and does not block the v0.3 Discovery behavior decision.

## Comments

## Resolution
