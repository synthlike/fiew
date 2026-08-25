---
name: develop-rfc
description: Develop a technical or design RFC from unresolved ambiguity through structured discussion to an explicit outcome. Use when alternatives need analysis or multi-person agreement before implementation.
license: MIT
---

# Develop RFC

Read `.agents/workflows.yaml` and `docs/agents/records.md`. Resolve the `rfcs` route and follow its generated adapter guidance. If the route is disabled, ask before persistence and use an approved temporary or external draft when appropriate.

## Start or resume

Use adapter `list` or search for overlapping RFCs and ARPs. Resume the existing RFC through revision-gated `update` when it asks the same material question. Otherwise use adapter `create`, which allocates the identifier, with [the RFC template](references/rfc-template.md).

## Develop

- State the ambiguity as a decision to be made.
- Separate requirements, constraints, assumptions, preferences, and non-goals.
- Explore repository facts before asking people.
- Use `clarify-intent` for unresolved human decisions.
- Use `research-question` for external facts.
- Use `prototype-design` when higher-fidelity feedback is needed.
- Describe meaningful alternatives fairly, including doing nothing.
- Keep open questions explicit and assign a decision owner.

## Resolve

Only the decision owner can establish the outcome. Set the RFC to `accepted`, `rejected`, or `withdrawn`, and fill in its resolution.

After acceptance:

- invoke `record-arp` for each outcome meeting the ARP threshold;
- invoke `author-specification` when agreed behavior needs a coherent contract; and
- create implementation work through the `issues` route.

Use adapter-returned references for resulting records and let the destination adapter render them. Do not construct paths, identifiers, or links, and do not duplicate full content in the RFC.
