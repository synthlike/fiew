---
name: plan-initiative
description: Plan a large ambiguous initiative as a map of dependent decision tickets, resolving the frontier until the destination is sufficiently clear for specification or execution planning.
disable-model-invocation: true
license: MIT
---

# Plan Initiative

Use this when the route to an outcome cannot fit in one planning session. This workflow resolves decisions; it does not normally execute the resulting implementation.

Read `.agents/workflows.yaml` and `docs/agents/records.md`. Resolve the `issues` route and follow its generated adapter guidance. Initiative maps and decision tickets remain issue structures; do not create separate record routes for them. If record guidance is absent, stop and ask the user to run `configure-workflows`. If the route is disabled, do not persist the initiative without approval.

## Concepts

- **Destination:** what completion of planning makes possible.
- **Map:** a low-resolution index of settled decisions, unresolved fog, and scope boundaries.
- **Decision ticket:** one question or prerequisite sized for one focused session.
- **Frontier:** open, unblocked, unclaimed tickets.
- **Fog:** in-scope uncertainty that cannot yet be phrased as a precise question.

The map indexes answers; the detailed answer lives in exactly one resolved ticket. Use adapter-returned references and let the issue adapter render them by title; do not construct identifiers or links.

## Ticket types

- **Clarification:** human decision resolved with `clarify-intent`; human-in-the-loop.
- **Research:** external fact established with `research-question`; may run independently.
- **Prototype:** concrete artifact created with `prototype-design`, then evaluated by a human.
- **Prerequisite:** action required before a later decision that is not implementation of the destination.

Never let the agent stand in for a human on a human-in-the-loop ticket.

## Chart a map

1. Use `clarify-intent` and `model-domain` to name a precise destination. The destination fixes scope.
2. Explore breadth-first for decisions and immediately actionable investigations.
3. If the whole route is already clear and fits one session, explain that a map is unnecessary and ask whether to author a specification or implementation plan.
4. Use issue adapter `create`, `parent`, and `block` operations to create the initiative map and tickets represented by [the map template](references/map-template.md).
5. Create every precise decision ticket currently visible, then add parent and blocking relationships in a second pass.
6. Put only unformulable in-scope uncertainty under `Not yet specified`. Put ruled-out work under `Out of scope`.
7. Start independent research only when the environment supports safe parallel work.
8. Stop after charting; do not hand-resolve a human ticket in the same invocation.

## Work the map

Resolve at most one non-research ticket per session.

1. Load the map, not every child.
2. Use a ticket named by the user, or select the first ticket returned by adapter `frontier`.
3. Use adapter `claim` as the first write.
4. Read related detail only as needed and invoke the ticket's workflow.
5. Read the latest revision, record the answer with guarded `update`, and use adapter `resolve`.
6. Append a one-line gist and the adapter-rendered ticket reference to `Decisions so far`.
7. Create newly visible tickets, graduate sharpened fog, and update dependencies.
8. Cancel tickets shown to be outside the destination and link their scope reason under `Out of scope`; do not index them as decisions.

The initiative is planned when no unresolved ticket or fog remains before the destination. Then offer `author-specification` or `plan-implementation`.

## Durable outcomes

A resolved decision ticket is planning history, not automatically an ARP. Invoke `record-arp` only when the accepted answer meets the ARP threshold. Use `develop-rfc` if a ticket exposes a discussion too broad for one resolution session.
