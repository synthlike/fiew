---
id: ISSUE-0078
title: "Specify agent Discovery handoff and proposed Trail attachments"
kind: "clarification"
status: resolved
created: 2026-09-01
assignee: "agent"
parent: "ISSUE-0074-plan-fiew-v0-3.md"
blocked_by:
labels: []
---
# Specify agent Discovery handoff and proposed Trail attachments

## Question

How does an agent show and reply to the current or explicit Discovery, submit a validated Proposed Trail only with a reply, reference it through a structured attachment, and preserve human control over thread lifecycle, acceptance, archival, and current selection?

## Answer

- Canonical Discovery state is private schema-versioned JSON. `fiew discovery show` emits a stable public JSON projection by default and Markdown through `--format markdown`; neither projection is writable canonical storage.
- Agent commands mirror Review handoff: `fiew discovery show [<discovery-id>] [--repo <path>]` and `fiew discovery reply [<discovery-id>] <thread-id> --body-file <path> [--repo <path>]`. Omitted IDs use the explicit current-Discovery pointer. Explicit IDs never change current. Missing, malformed, or dangling current state fails without guessing.
- Agents cannot start, open, restore, rename, archive, answer, accept, reassign, link, delete, or change current Discoveries, Threads, Trails, or Review state.
- Default `show` output excludes Archived Threads and Trails and reports their counts. `--include-archived` deliberately includes them and is required to show an explicitly identified Archived Discovery.
- Projections include Discovery identity, title, lifecycle, current-selection indication, visible Thread IDs and lifecycle, Current or Outdated validity, exact path/range, captured selected source and bounded context, ordered immutable Comments, explicit human reassignment provenance, linked Review Concern references and states, attached Trail provenance/state/point summaries, archived counts, and concise re-evaluation or persistence warnings.
- New Discovery projections use Comment and Trail author roles `human` and `agent`. Existing `fiew.review/v1` compatibility projections retain `reviewer` and `agent`. Future role unification is deferred to ISSUE-0081.
- Agents may reply only to Open Threads, including Outdated ones. Answered or Archived Threads reject replies clearly.
- A reply requires a non-empty bounded body. It may atomically submit at most one new Proposed Trail through a separate bounded JSON input file. Agents cannot attach or mutate an existing Trail.
- A Trail proposal requires a bounded title, optional bounded overview, and at least two ordered points. Each point supplies a repository-relative path, exact one-based start/end positions, expected selected UTF-8 source, and a bounded explanation.
- fiew loads immutable snapshots, verifies every expected selection exactly, rejects External/private/binary/escaping/stale paths, and captures canonical re-anchoring context itself. In Git repositories, agent proposals reject ignored points because no human durability warning was confirmed. Normal repository-relative validation applies without Git.
- Reply and Proposed Trail persistence is all-or-nothing. Any invalid body, point, context, bound, schema, or persistence step saves neither artifact. Success returns opaque Comment and Trail identities.
- The persisted Comment owns a structured attachment reference to the Proposed Trail. Markdown projection renders a readable Trail attachment while the non-empty body preserves the answer when Trail rendering is unavailable.
- Proposed Trails are immediately visible with immutable agent authorship. Only a human may accept or archive them. Humans cannot edit an agent proposal; they may archive it or create a separate human Trail.
- A human may accept a proposal containing Outdated points only after explicit confirmation. Acceptance records human endorsement separately, preserves agent authorship, and never changes point validity.
- Trail archival is independent of Proposed or Accepted state. Restoration recovers the prior state, and the originating Comment attachment remains resolvable while Archived.
- The same optional atomic Proposed Trail input is available to `fiew review reply` in v0.3, with identical validation, provenance, acceptance, archival, and no-approval-effect behavior.

## Comments
## Resolution

Accepted by decision owner synthlike. Agent Discovery handoff uses current-or-explicit public projections and constrained replies, with atomic validated Proposed Trail attachments and human-controlled acceptance and archival under the behavior recorded above.
