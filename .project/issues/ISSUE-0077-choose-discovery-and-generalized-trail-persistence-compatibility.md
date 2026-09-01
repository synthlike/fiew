---
id: ISSUE-0077
title: "Choose Discovery and generalized Trail persistence compatibility"
kind: "clarification"
status: resolved
created: 2026-09-01
assignee: "agent"
parent: "ISSUE-0074-plan-fiew-v0-3.md"
blocked_by:
  - "ISSUE-0075-define-the-complete-discovery-interaction-and-lifecycle.md"
  - "ISSUE-0076-define-discovery-anchors-and-linked-review-concern-behavior.md"
  - "ISSUE-0078-specify-agent-discovery-handoff-and-proposed-trail-attachments.md"
labels: []
---
# Choose Discovery and generalized Trail persistence compatibility

## Question

Which private schemas, repository-local ownership, current pointers, atomicity boundaries, and compatibility behavior preserve `fiew.review/v1`, `fiew.bookmark/v1`, and v0.2 `fiew.trail/v1` while adding durable Discoveries and container-attached Trails?

## Answer

### Canonical locations and units

- `.discoveries/current` and one `.discoveries/<adapter-owned-id>.json` per Discovery, each with one validated backup.
- `.reviews/current` and one `.reviews/<adapter-owned-id>.json` per Review, each with one validated backup.
- One `.trails/<adapter-owned-id>.json` per Trail, each with one validated backup. Review ownership never requires physical storage under `.reviews/`.
- One bounded `.spots/spots.json` private collection with one validated backup.
- fiew neither inspects nor modifies Git ignore configuration and never uses filenames as persisted relationship identity.

### Schema boundary

- `fiew.discovery/v1` owns one Discovery's title, active or archived lifecycle, stable Threads and Comments, source anchors, explicit human reassignment provenance, linked Review Concern references, relationship tombstones, and Trail attachment references.
- `fiew.review/v2` cleanly replaces the development v1 contract and owns stable Concern and Comment IDs, Discovery-origin references, relationship tombstones, and Trail attachment references alongside established Review behavior.
- Redesign pre-release `fiew.trail/v1` before v0.2 release as one canonical Trail per file. It owns one immutable Review, Discovery, or repository-private owner; immutable human or agent authorship; Proposed or Accepted state; active or archived lifecycle; title, overview, ordered points, and point anchor validity.
- `fiew.spot/v1` replaces the Bookmark storage term with one private bounded collection. Spot product interaction remains ISSUE-0082.
- `fiew.review/v1`, `fiew.bookmark/v1`, and development collection-form Trail files receive no migration or reinterpretation. They are ignored or refused until manually purged and are never overwritten as new schemas.
- Breaking persistence changes are acceptable while no production records exist. Revisit compatibility based on evidence when real users or valuable production records exist.

### Trail ownership and visibility

- Every Trail has exactly one immutable owner. A Review- or Discovery-owned Trail may remain private.
- Container files own explicit attachment references. Absence of a reference keeps an owned Trail out of agent projections.
- Human-created Trails default private. Agent proposals are attached to their originating Comment immediately under the separately accepted atomic reply behavior.
- Ownership changes require an explicit link or human-created copy; agents cannot mutate ownership or attach existing Trails.

### Identity, validation, and recovery

- Discovery, Review, Thread, Concern, Comment, Trail, and Spot relationships use opaque repository-local IDs. Adapter-controlled filenames may contain an owning ID but never define cross-artifact identity.
- Canonical artifacts remain private JSON with schema validation, bounded reads and writes, future-schema refusal, atomic single-file replacement, and one validated previous backup.
- Preserve at least the current 4 MiB per-artifact bound and apply stricter field, collection, and transaction limits where specified later.
- A malformed or future individual Trail disables only that Trail and its attachments. A malformed container or current pointer disables only the affected capability without impairing source browsing.

### Multi-artifact transactions

- Discovery-coordinated intents live under `.discoveries/.transactions/`; Review-coordinated intents live under `.reviews/.transactions/`. Standalone single-file Trail and Spot writes require no journal.
- A bounded versioned intent contains expected opaque revisions and fully validated replacement payloads. Repository-local fiew mutations are serialized, each target uses atomic replacement, commit is marked durably, and completed intents are removed.
- Before exposing or mutating an affected container, fiew completes or rolls back interrupted work. It never exposes a Comment without its attached Trail or an attached Trail without its Comment.
- Unrecoverable transactions disable mutation and agent projection only for the affected Review or Discovery, report explicit non-success, and preserve repository browsing and unrelated containers. fiew never guesses which side wins.

### Release consequences

- Before v0.2 release, move Review-owned Trail persistence from `.reviews/*.trails` to one-file-per-Trail `.trails/` storage and redefine the pre-release `fiew.trail/v1` contract accordingly.
- No legacy Trail data exists. Ignore development `.reviews/*.trails` without migration or diagnostic.
- Update the v0.2 specification, supersede ARP-0011's physical review-companion decision, and add implementation work before integrated v0.2 verification.

## Comments
## Resolution

Accepted by decision owner synthlike. Discovery, Review v2, standalone Trail, and Spot persistence use the clean JSON, identity, ownership, backup, transaction, and purge-only compatibility boundary recorded above; v0.2 Trail storage moves to `.trails/` before release.
