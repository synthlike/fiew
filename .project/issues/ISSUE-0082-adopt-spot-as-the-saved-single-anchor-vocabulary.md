---
id: ISSUE-0082
title: "Adopt Spot as the saved single-anchor vocabulary"
kind: "clarification"
status: open
created: 2026-09-01
assignee: 
parent: "ISSUE-0074-plan-fiew-v0-3.md"
blocked_by:
  - "ISSUE-0077-choose-discovery-and-generalized-trail-persistence-compatibility.md"
labels: []
---
# Adopt Spot as the saved single-anchor vocabulary

## Question

Which v0.3 UI labels, commands, bindings, public projections, documentation, and storage compatibility behavior should replace the Bookmark product term with Spot while preserving existing private saved-anchor data safely?

## Established direction

**Spot** is the canonical product term for one durable private source Anchor. **Trail** remains an ordered explanatory artifact with two or more Trail Points. Trail Points do not become shared Spot artifacts merely because both use source Anchors.

The v0.3 target is likely, but exact compatibility with `fiew.bookmark/v1` and whether storage terminology changes must follow the accepted persistence boundary rather than silently rewriting a released schema.

## Comments

## Resolution
