---
id: ISSUE-0031
title: "Plan Skaut v0.4"
kind: "initiative"
status: open
created: 2026-08-27
assignee:
parent:
blocked_by:
labels: []
---
# Plan Skaut v0.4

## Destination

Settle a shared read-only language-capability model and the Go and TypeScript/React behavior needed to author a coherent multi-language Skaut v0.4 specification.

## Notes

Go with `gopls` and JavaScript/JSX/TypeScript/TSX with React-capable language tooling are required ecosystems. Language servers are optional, user-installed, and trusted. Tree-sitter structure and plain-text viewing remain available when a server is absent or fails.

The shared boundary must support language-aware diffs and semantic anchors where the selected ecosystems can provide reliable identity. Candidate capabilities include workspace symbols, read-only diagnostics, import/module navigation, test-to-implementation navigation, and semantic reanchoring across file moves. These candidates must be prioritized explicitly; listing them does not make every capability a release gate.

## Decisions so far

- [Confirm the v0.3 multi-language destination](<.project/issues/ISSUE-0050-confirm-the-v0-3-multi-language-destination.md>) — originally confirmed the multi-language destination for v0.3; the roadmap now schedules that unchanged destination for v0.4.

## Not yet specified

None beyond the open decision tickets.

## Out of scope

- Source editing, formatting, rename, code actions, workspace edits, and server commands.
- A promise to support arbitrary language servers.
- Remote GitHub review synchronization, which belongs to v0.5.
- Making every candidate navigation or diagnostic capability a release gate before prioritization.

## Comments


## Resolution
