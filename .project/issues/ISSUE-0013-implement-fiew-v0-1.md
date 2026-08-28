---
id: ISSUE-0013
title: "Implement fiew v0.1"
kind: "initiative"
status: resolved
created: 2026-08-25
assignee: 
parent: 
blocked_by:
labels: []
---
# Implement fiew v0.1

## Destination

Deliver the review-first v0.1 behavior defined by [fiew v0.1](<docs/specs/fiew-v0-1.md>) as a verified Apple Silicon macOS binary for Ghostty.

## Acceptance criteria

- Immutable repository browsing and Zig structural navigation work without source or Git mutation.
- The Git-backed VCS view publishes only complete, consistent snapshots and preserves repository-root identity.
- Reviewer-owned threads, agent replies, strict reviewer resolution, and the non-interactive review interface work against durable review state.
- Private repository bookmarks and the Project/VCS/Review/Bookmarks context bindings work as specified.
- The supported build, test, performance, and Ghostty verification complete honestly.
- A documented `ReleaseSafe` Apple Silicon artifact can be produced from a clean checkout.

## Out of scope

- Markdown, Mermaid, fuzzy file finding, ZLS, Linux, and additional terminals; these move to v0.2.
- Remote review providers, source editing, and Git mutation.
- Automatically publishing a release, signing, notarization, or package-manager distribution.

## Comments
## Resolution

Outcome: Achieved.

fiew v0.1 delivers the specified review-first workflow as a verified Apple Silicon macOS binary for Ghostty.

- Immutable repository browsing, location history, Zig highlighting, folding, and structural navigation passed deterministic and manual verification without source or Git mutation.
- Git-backed Staged, Unstaged, and Untracked review passed nested-root, linked-worktree, consistency, cancellation, stale-result, failure, and mutation-boundary verification.
- Reviewer-owned threads, ordered agent replies, constrained lifecycle authority, exact-context re-anchoring, strict approval, explicit current-review handling, canonical private JSON, public projections, refusal, and recovery behavior passed automated and CLI integration checks.
- Private repository-local bookmarks and the Project, Review Diff, Review Threads, and Bookmarks contexts passed automated coverage and the complete Ghostty checklist.
- The deterministic suite, Git integration suite, full 10,000-file profile, `ReleaseSafe` build, and extracted-artifact Ghostty checks passed. Measured filesystem scan and clean Git snapshot times were 437 ms and 189 ms on the supported machine.
- Two clean-checkout packaging runs produced identical `fiew-v0.1.0-darwin-arm64.tar.gz` checksums. The executable reports version and pinned dependency metadata, and installation and manual release publication are documented.
- All 19 direct child issues are resolved. No unresolved direct work remains.

Accepted limitations remain unchanged: v0.1 supports only Apple Silicon macOS in Ghostty and manual unsigned, unnotarized GitHub Release distribution. Linux, other terminals, Markdown structure, Mermaid, fuzzy finding, ZLS, remote providers, source or Git mutation, signing, notarization, package managers, and automatic publication remain deferred or out of scope under their existing initiatives.
