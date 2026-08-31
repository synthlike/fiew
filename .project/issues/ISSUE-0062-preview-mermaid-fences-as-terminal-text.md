---
id: ISSUE-0062
title: "Preview Mermaid fences as terminal text"
kind: "implementation"
status: cancelled
created: 2026-08-28
assignee:
parent: "ISSUE-0057-implement-fiew-v0-2.md"
blocked_by:
  - "ISSUE-0060-normalize-terminal-and-subprocess-behavior.md"
  - "ISSUE-0061-add-markdown-syntax-and-fenced-code-structure.md"
labels: []
---
# Preview Mermaid fences as terminal text

## Parent

[fiew v0.2](<docs/specs/fiew-v0-2.md>)

## What to build

Deliver transient Unicode and strict-ASCII previews for supported Mermaid fences through optional `mermaid-ascii` while always preserving source access.

## Acceptance criteria

- [ ] Supported flowchart, sequence, and entity-relationship fences preview in Unicode and strict ASCII.
- [ ] Renderer invocation is direct, bounded, cancellable, and sanitized before terminal rendering.
- [ ] Unsupported types and missing, incompatible, slow, failed, or malformed renderers retain source with an exact reason.
- [ ] Cache identity and request generations prevent stale output from replacing newer source.
- [ ] Diagram scroll survives resize and preview exit restores the source fence location.
- [ ] Transcript, reducer, and render tests pass without requiring `mermaid-ascii`.

## Blocked by

Managed by native issue relationships.

## Out of scope

Full Mermaid compatibility, standalone Mermaid files, graphical output, browser runtimes, images, and interactivity.

## Comments
## Resolution

Cancelled because Mermaid rendering no longer fits fiew's source-first design and product premise. [Keep Mermaid rendering outside fiew](<docs/decisions/ARP-0012.md>) removes Mermaid-specific preview behavior and dependencies from current scope; Mermaid fences remain ordinary Markdown source. This work is removed rather than deferred.
