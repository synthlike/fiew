---
id: ISSUE-0032
title: "Plan fiew v0.5"
kind: "initiative"
status: open
created: 2026-08-27
assignee: 
parent: 
blocked_by:
labels: []
---
# Plan fiew v0.5

## Destination

Resolve the authority, synchronization, and publication decisions needed to author a coherent specification for local-first GitHub pull-request review in fiew v0.5.

## Notes

GitHub's official APIs can represent file, line, and multiline comments, replies, review-thread resolution, pending reviews, and explicit COMMENT, REQUEST_CHANGES, and APPROVE submissions. Consult [GitHub pull-request review API feasibility for fiew v0.4](<docs/research/github-pull-request-review-api-feasibility-for-fiew-v0-4.md>).

The accepted direction is local-first. fiew may import a GitHub pull request's diff and thread state into its VCS and Review surfaces, but every remote mutation requires an explicit publish or submit action. The source repository and local Git state remain read-only.

## Decisions so far

- [Confirm the v0.4 GitHub review destination](<.project/issues/ISSUE-0051-confirm-the-v0-4-github-review-destination.md>) — originally confirmed the local-first GitHub pull-request review destination for v0.4; the roadmap now schedules that unchanged destination for v0.5.

## Not yet specified

None beyond the open decision tickets.

## Out of scope

- Automatic publication, background mutation, source editing, staging, committing, merging, or branch management.
- GitLab, Bitbucket, Gerrit, and a generic forge-provider abstraction.
- Assuming local and remote thread identity or conflict behavior without an explicit mapping decision.

## Comments


## Resolution
