---
name: close-initiative
description: Verify what an initiative delivered and record an honest achieved, partial, or abandoned outcome in its existing artifacts.
license: MIT
---

# Close Initiative

Close one initiative from evidence, not issue counts. Preserve gaps and lessons without creating a competing authority.

## Load the initiative

Read `.agents/workflows.yaml` and `docs/agents/records.md`. Resolve the `issues` route and follow its generated adapter guidance. Initiative maps remain issue structures. If record guidance is absent, stop and ask the user to run `configure-workflows`. If the route is disabled, do not persist closure changes without approval.

Identify the initiative map or equivalent parent artifact, original destination, success criteria, accepted scope changes, linked decision and implementation work, specifications, accepted ARPs, domain documentation, and project guidance. If the destination or closure boundary is ambiguous, ask before proceeding.

Read unresolved, claimed, resolved, cancelled, and blocked work relevant to the destination. Do not assume that issue status proves delivery or that unlinked work is out of scope.

## Verify outcomes

For each success criterion and material scope commitment, identify:

- delivered observable behavior;
- implementation and configuration evidence;
- tests, demonstrations, reviews, or operational evidence;
- relevant specification and decision conformance;
- limitations or unavailable evidence; and
- remaining work.

Inspect current behavior at the highest stable available seam. Use `review-implementation` when material implementation lacks trustworthy conformance evidence. Ask before expensive, destructive, production-facing, or externally visible verification.

Reconcile every unresolved, blocked, cancelled, and deferred item. Distinguish:

- no longer necessary because the destination changed or another outcome superseded it;
- completed elsewhere with evidence;
- still valuable follow-up work; and
- a gap that prevents claiming the destination.

Do not present cancelled, deferred, or merely planned scope as delivered.

## Propose one outcome

Use [the closure template](references/initiative-closure-template.md) and choose exactly one:

- **Achieved:** evidence verifies the destination and success criteria;
- **Partially achieved:** useful outcomes are verified, but explicit gaps remain; or
- **Abandoned:** work stopped intentionally, with rationale, delivered remnants, and consequences recorded.

A partial outcome is not a failed achieved outcome. State its useful delivered value and its gaps precisely. An abandoned outcome may still preserve useful decisions or implementation, but must not imply completion.

Identify lessons as supporting evidence. Route a lasting consequential decision through `record-arp`, agreed behavior through `author-specification`, resolved terminology through `model-domain`, and approved follow-up reports through `triage-issue`. Do not perform those workflows' approval-sensitive writes during closure.

## Confirm

Present a complete closure proposal containing:

1. destination and accepted scope changes;
2. criterion-by-criterion evidence;
3. proposed outcome and rationale;
4. delivered value, limitations, and gaps;
5. disposition of unresolved, blocked, cancelled, and deferred work;
6. proposed follow-up issues and routing;
7. lessons and their correct artifact destinations; and
8. every map, parent, or issue operation that approval would perform.

Wait for explicit approval. Do not change statuses or create follow-up work merely to make the initiative appear closed.

## Record closure

After approval, read the latest parent revision and add a concise closure summary through guarded issue `update`. Pass adapter-returned references for evidence, specifications, ARPs, issues, and supporting lessons to the issue adapter for rendering rather than copying them. Do not construct paths, identifiers, or links. Do not create a separate canonical closure-report type.

Perform only approved operations through the `issues` adapter. Create follow-up issues only after their scope is approved, preserve partial gaps explicitly, and do not silently resolve blocked work.

Report the recorded outcome, updated artifacts and issues, created follow-ups, verification performed, and remaining limitations. If evidence is insufficient to select an outcome, stop with the missing evidence and do not close the initiative.
