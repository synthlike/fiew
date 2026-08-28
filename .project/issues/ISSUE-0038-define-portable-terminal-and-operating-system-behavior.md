---
id: ISSUE-0038
title: "Define portable terminal and operating-system behavior"
kind: "clarification"
status: resolved
created: 2026-08-27
assignee: "agent"
parent: "ISSUE-0030-plan-fiew-v0-2.md"
blocked_by:
labels: []
---
# Define portable terminal and operating-system behavior

## Question

Which platform-specific state paths, filesystem watching, signals, process handling, clipboard behavior, and terminal fallbacks must be normalized or explicitly excluded across macOS/Linux and Ghostty/Kitty/WezTerm?

## Answer

Use `$HOME/Library/Application Support/fiew` for global macOS state. Use `$XDG_STATE_HOME/fiew` on Linux, falling back to `$HOME/.local/state/fiew`. Keep reviews and bookmarks repository-local in `.reviews/` and `.bookmarks/`. If no valid global state directory is available, continue without global persistence and show a diagnostic.

Exclude automatic filesystem watching from v0.2. Keep Git refresh explicit, detect source changes when opening or explicitly reloading a document, retain the immutable current snapshot until replacement succeeds, and report deleted, replaced, or unreadable files without crashing. Do not promise FSEvents, inotify, polling, or terminal-focus refresh.

Restore terminal state on normal exit and handled `SIGINT` and `SIGTERM`; forced termination such as `SIGKILL` is unrecoverable. Let libvaxis own resize handling. Launch Git, ZLS, and Mermaid directly without a shell. Bound, cancel, terminate, and reap every child, and stop ZLS during shutdown or trust revocation. Exclude shell job control, background operation, and `Ctrl-Z` suspend/resume guarantees.

Do not integrate with the system clipboard through native APIs, helper executables, or OSC 52. Users copy through terminal selection, and clipboard availability does not affect core workflows.

Use libvaxis runtime capability detection. Prefer the Kitty keyboard protocol and synchronized output, with conventional VT keyboard input and unsynchronized drawing as fallbacks. Fall back to the available color model. Keep every core workflow keyboard-accessible; mouse support is an optional enhancement. Use Unicode for the normal interface and retain strict ASCII only where separately specified for Mermaid. Show the existing unsupported-size state when necessary. Do not add graphics-protocol, multiplexer, or terminal-specific application branches.

Ghostty, Kitty, and WezTerm must pass the same behavioral smoke suite across the required operating-system targets.

## Comments
## Resolution

Decision owner approved the complete portable operating-system and terminal behavior contract on 2026-08-28.
