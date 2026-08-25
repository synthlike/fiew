---
id: ISSUE-0005
title: "Establish the Zig and terminal UI technical baseline"
kind: "research"
status: resolved
created: 2026-08-25
assignee: 
parent: "ISSUE-0001-plan-fiew-v0-1.md"
blocked_by:
  - "ISSUE-0003-define-the-v0-1-workflows-and-feature-boundary.md"
  - "ISSUE-0004-choose-initial-platform-and-terminal-compatibility.md"
labels: []
---
# Establish the Zig and terminal UI technical baseline

## Question

Which supported Zig version, build structure, terminal UI approach, testing seams, and dependency constraints provide the smallest viable engineering baseline for the selected v0.1 scope?

## Comments
## Resolution

Accepted: the v0.1 technical foundation is recorded in [fiew v0.1 engineering baseline](<docs/engineering/fiew-v0-1-engineering-baseline.md>), with the terminal UI dependency decision recorded in [Adopt libvaxis’s low-level API for fiew v0.1](<docs/decisions/ARP-0001.md>).

The baseline targets Zig 0.16.0 on Apple Silicon macOS and Ghostty. It uses libvaxis's low-level API at immutable revision `c060d314930c5552b99a89278a6a695baf0352da`; `vxfw` and the Zig-0.13-only v0.5.1 tag are excluded. The project starts as a standard Zig executable, pins dependency integrity hashes, separates terminal I/O from testable application behavior, uses Zig tests plus a manual Ghostty smoke check, and builds GitHub Release artifacts with `ReleaseSafe`.

Build and test commands remain explicitly unverified until project files exist. Product-dependent module boundaries, integration architecture, note persistence, and release signing remain deferred to their owning decisions.
