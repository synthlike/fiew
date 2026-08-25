---
id: ISSUE-0011
title: "Decide Mermaid rendering scope and approach"
kind: "research"
status: resolved
created: 2026-08-25
assignee: 
parent: "ISSUE-0001-plan-fiew-v0-1.md"
blocked_by:
  - "ISSUE-0003-define-the-v0-1-workflows-and-feature-boundary.md"
  - "ISSUE-0007-prototype-the-workspace-and-left-pane-interaction.md"
labels: []
---
# Decide Mermaid rendering scope and approach

## Question

Which Mermaid sources and terminal rendering behavior are useful enough for v0.1, and what implementation or external-tool approach fits the project's constraints?

## Comments
## Resolution

Accepted based on [Mermaid ASCII rendering constraints for fiew v0.1](<docs/research/mermaid-ascii-rendering-constraints-for-fiew-v0-1.md>). The consequential rendering boundary is recorded in [Render a Mermaid subset as terminal text](<docs/decisions/ARP-0004.md>).

## Source and compatibility scope

- Recognize only fenced code blocks explicitly labeled `mermaid` inside Markdown files. Keep source visible and render only on explicit request.
- Support flowcharts beginning with `graph` or `flowchart`, `sequenceDiagram`, and `erDiagram`. Recognize other Mermaid fences but disable preview with an unsupported-type reason.
- Use a user-installed `mermaid-ascii` 1.5.x executable from `PATH`. Do not download or bundle it. Record release 1.5.0 at commit `b1b35f67d6a5dd0699ccfc968c00a763db573076` as researched; other 1.5 patches are policy-compatible but unverified.
- Defer standalone `.mmd`/`.mermaid` files, inferred sources, and Mermaid embedded in comments.

## Interaction

- `Space m p` previews the Mermaid fence containing the selection as Unicode box-drawing text. `Space m a` previews strict ASCII.
- Preview temporarily replaces the main view. `q` or `Esc` returns to the exact source selection without adding location history.
- Normal movement and paging navigate output. Use horizontal scrolling when the diagram exceeds the viewport.
- Render with fixed compact spacing: border padding 1, horizontal padding 3, and vertical padding 2. Preserve scroll across resize; do not promise width-responsive reflow.
- Disable preview outside a recognized fence with a visible reason.

## Process and data safety

- Invoke `mermaid-ascii` directly without a shell. Pass only diagram text through stdin, use no repository-derived arguments or configuration, and run outside the repository.
- Repository trust is not required because the process receives diagram data and does not evaluate repository build logic.
- Limit source to 256 KiB, captured output to 2 MiB, and execution to one second. Cancel obsolete work when source changes or preview closes.
- Cache successful sanitized output by renderer version, source hash, and ASCII/Unicode mode.
- Treat output as untrusted data: decode UTF-8, normalize line endings, expand tabs, and reject or strip control characters and escape sequences except newline. Never forward bytes directly to Ghostty. Bound and sanitize stderr before display.
- Missing executable, incompatible version, timeout, crash, oversize, unsupported syntax, invalid UTF-8, or parser failure preserves source and reports a concise error.

## Deferred rendering

Do not use Mermaid CLI, Node, Chromium, SVG, PNG, PDF, or Kitty graphics in v0.1. Full Mermaid coverage, automatic inline rendering, hyperlinks, interactive nodes, zoom, and rich diagram navigation are deferred.
