---
name: triage-issue
description: Evaluate an incoming report, identify its correct disposition, and propose actionable issue scope or another workflow before any issue mutation.
license: MIT
---

# Triage Issue

Turn one incoming report into an evidence-based disposition. Triage decides the next route; it does not implement the work or invent missing intent.

## Load the project contract

Read `.agents/workflows.yaml` and `docs/agents/records.md`. Resolve the `issues` route and follow its generated adapter guidance. If record guidance is absent, stop and ask the user to run `configure-workflows`. If the route is disabled, do not persist triage output or mutate an issue without approval.

Read the complete report or request, relevant project guidance, current repository evidence, domain documentation, specifications, accepted ARPs, RFC resolutions, and related open and resolved issues. Search by behavior and outcome, not only matching words.

Preserve the reporter's observation separately from agent interpretation. Do not expose secrets or unnecessary personal information copied from a report.

## Check prior work

Identify:

- exact or functional duplicates;
- broader issues that already contain the outcome;
- previously rejected, cancelled, or resolved work and its rationale;
- regressions of behavior claimed as fixed; and
- authoritative artifacts that establish or contradict expected behavior.

Do not close a report as duplicate merely because it shares a component. Link the existing issue and explain how its outcome covers the report.

## Classify and assess

Use the closest project classification, including defect, enhancement, question, design ambiguity, operational task, or duplicate. Keep these distinctions explicit:

- **Reported impact:** what the reporter says happened;
- **Verified evidence:** what repository or runtime evidence establishes;
- **Urgency:** a stakeholder scheduling decision; and
- **Severity:** demonstrated consequence within an established project scale.

Do not invent urgency, severity, affected users, business value, or priority. State what is unknown.

Identify missing facts, reproduction needs, unresolved human intent, external facts, design choices, and the smallest useful next step. Route:

- uncertain runtime behavior to `investigate-failure`;
- focused external facts to `research-question`;
- unresolved human intent to `clarify-intent`;
- material design ambiguity to `develop-rfc`; and
- decomposition of an approved broad outcome to `plan-implementation`.

Do not perform the routed workflow's approval-sensitive writes during triage.

## Draft a disposition

Use [the triage template](references/triage-proposal-template.md). Recommend one disposition:

- link as duplicate or already covered;
- answer as a question with authoritative evidence;
- request specific missing evidence;
- route to another workflow;
- create one bounded executable issue; or
- update an existing issue materially affected by the report.

A proposed issue must state one observable outcome, acceptance criteria, relevant authority and evidence, and only blockers that genuinely prevent starting. Avoid speculative implementation, file lists, and solutions not established by a decision.

## Confirm

Before any issue creation or material rewrite, present:

1. classification and rationale;
2. duplicate and related-work analysis;
3. reported impact versus verified evidence;
4. missing facts and decisions;
5. recommended disposition and routing;
6. proposed title, outcome, acceptance criteria, links, and blockers when an issue is appropriate; and
7. exact adapter operations that approval would perform.

Wait for approval. A duplicate, unsupported report, or answered question may need no new issue; explain the disposition and ask before preserving evidence in an existing artifact.

## Publish

Perform only the approved adapter operations through the `issues` route. Recheck duplicates with adapter `list` or search immediately before `create`. Read the latest revision before guarded updates. Preserve issue semantics, assign no owner or priority unless approved, and do not mark implementation complete.

Report the adapter-returned issue or record reference, performed operations, unresolved evidence, and recommended next workflow. Treat references and revisions as opaque; do not construct paths, provider identifiers, labels, tags, or links. If issue state changed or new evidence invalidates the approved draft, stop and present a revised proposal rather than publishing stale scope.
