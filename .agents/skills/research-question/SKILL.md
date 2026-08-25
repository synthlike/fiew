---
name: research-question
description: Investigate a focused question using high-trust primary sources and save concise cited findings. Use when a design or decision depends on facts outside the current repository.
license: MIT
---

# Research Question

Investigate one focused question.

Read `.agents/workflows.yaml` and `docs/agents/records.md`. Resolve the `research` route and follow its generated adapter guidance. When the route is disabled, do not persist research without approval; use an approved external or temporary location instead.

1. State the question and what decision it will inform.
2. Prefer primary sources: official documentation, specifications, source code, standards, and first-party APIs.
3. Trace material claims to the source that owns them.
4. Distinguish verified facts, interpretations, and remaining uncertainty.
5. After approval, use adapter `create` or revision-gated `update` for concise findings, or use the approved external or temporary location when the route is disabled.
6. Return the adapter reference to the requesting record and let its destination adapter render the reference. Do not construct paths, provider identifiers, or links, and do not copy findings into several places.

Research informs decisions but does not make them. Do not turn a recommendation into an accepted decision without the decision owner's confirmation.
