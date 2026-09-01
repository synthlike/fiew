---
id: ISSUE-0076
title: "Define Discovery anchors and linked Review Concern behavior"
kind: "clarification"
status: resolved
created: 2026-09-01
assignee: "agent"
parent: "ISSUE-0074-plan-fiew-v0-3.md"
blocked_by:
labels: []
---
# Define Discovery anchors and linked Review Concern behavior

## Question

Which source selections may anchor Discovery Threads, when are they re-evaluated or explicitly reassigned, and how does a human create a linked Review Concern without coupling Answered and Resolved lifecycle?

## Answer

- A non-collapsed Discovery source selection preserves its exact byte boundaries and displayed line/column extent. A collapsed selection anchors the complete active line.
- Creation captures the exact selected raw bytes plus up to three complete surrounding source lines for conservative matching and agent context.
- Anchors require valid UTF-8 source beneath the canonical repository root. Refuse binary data, invalid byte mappings, `.git`, fiew-owned private storage, and paths whose canonical target escapes the repository.
- Git-visible status is not an ownership boundary. A human may anchor an ignored repository file after confirming that its captured context becomes durable and agent-visible. This preserves Discovery in non-Git repositories.
- Re-evaluate an anchor after accepting a complete opened or reloaded snapshot for its path, immediately before preview or pin, and before agent-facing projection. Do not watch, poll, scan periodically, or evaluate partial snapshots.
- Validate exact target bytes at the stored location first. If they no longer match, relocate only through one complete raw-byte context match in the same path or an explicit rename in an accepted Git snapshot. Never normalize or guess.
- Missing or unreadable files and zero or multiple matches preserve stored identity and context but mark validity Outdated. A later exact validation may restore Current.
- A human may explicitly reassign an active Current or Outdated Thread to any valid repository-source range. Show old captured and proposed new anchors and require confirmation. Archived state must be restored before reassignment.
- Human reassignment preserves Thread identity, Comments, and Open or Answered lifecycle, marks the new anchor Current, and records immutable timestamped old/new anchor provenance with human actor role. Automatic relocation retains original and current anchor evidence but does not append routine history entries.
- **Create Linked Review Concern** begins from an active Open or Answered Discovery Thread, whether Current or Outdated. It requires an explicitly current Review, a separately selected valid Review Diff anchor, and a required new human concern Comment. Cancellation creates nothing; fiew never translates the Discovery source anchor into review evidence.
- One Discovery Thread may originate multiple Review Concerns, including within one Review. Each v0.3 Review Concern has at most one originating Discovery Thread. Lifecycles and validity remain independent in both directions.
- Discovery Threads list their linked Review identities, concern identities, and current concern states. Review Concerns show their origin. Following links provides navigation or read-only preview without changing either current-container pointer or any lifecycle.
- An Archived Discovery or Thread remains available through a linked read-only historical preview. It must be explicitly restored before comments, reassignment, or new links.
- Existing permanent Review Concern deletion removes its comment and anchor content but retains a relationship tombstone with Review identity, former concern identity, and Deleted state.

## Comments
## Resolution

Accepted by decision owner synthlike. Discovery uses exact repository-source anchors, bounded conservative relocation, explicit human reassignment provenance, and independently linked Review Concerns under the behavior recorded above.
