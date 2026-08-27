---
id: ISSUE-0049
title: "Confirm the v0.2 capability and compatibility boundary"
kind: "clarification"
status: resolved
created: 2026-08-27
assignee:
parent: "ISSUE-0030-plan-fiew-v0-2.md"
blocked_by:
labels: []
---
# Confirm the v0.2 capability and compatibility boundary

## Question

Which deferred capabilities, operating systems, architectures, and terminals define v0.2?

## Answer

v0.2 adds Markdown structure, terminal-text Mermaid preview, fuzzy file finding, and Zig/ZLS definition, references, and hover documentation while remaining source-read-only. It requires Apple Silicon macOS and x86_64 Linux releases, supports ARM64 Linux builds from source without making them a release gate, and smoke-tests Ghostty, Kitty, and WezTerm. Other xterm-compatible terminals are best-effort.

## Comments
## Resolution

Accepted by the decision owner during the roadmap clarification session on 2026-08-27. The answer in this ticket is the confirmed release boundary and is indexed by its initiative map.
