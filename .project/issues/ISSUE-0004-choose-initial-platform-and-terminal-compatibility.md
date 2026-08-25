---
id: ISSUE-0004
title: "Choose initial platform and terminal compatibility"
kind: "clarification"
status: resolved
created: 2026-08-25
assignee: 
parent: "ISSUE-0001-plan-fiew-v0-1.md"
blocked_by:
labels: []
---
# Choose initial platform and terminal compatibility

## Question

Which operating systems, terminal capabilities, repository sizes, and installation methods must the first usable version support?

## Comments
## Resolution

Accepted: v0.1 supports macOS only and officially targets Ghostty only. Rendering, keyboard handling, and mouse behavior are validated for Ghostty; support for other macOS terminals is deferred.

Distribute prebuilt macOS binaries through GitHub Releases. Installation is manual; a Homebrew formula and other package-manager integrations are deferred.

Target repositories with up to 10,000 tracked files. Larger repositories may open, but v0.1 makes no responsiveness guarantee for them.
