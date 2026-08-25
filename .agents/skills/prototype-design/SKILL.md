---
name: prototype-design
description: Build a cheap disposable artifact to answer a specific product, interaction, state, or technical design question. Use when discussion needs something concrete to react to.
license: MIT
---

# Prototype Design

A prototype exists to answer a named question, not to begin production implementation.

Read `.agents/workflows.yaml` and `docs/agents/records.md`. Resolve the `prototypes` route and follow its generated adapter guidance. Route durable prototype metadata and conclusions through adapter `create` or revision-gated `update` only after approval. Executable prototype files may remain temporary or external. When the route is disabled, do not persist a prototype record without approval.

1. State the question and the evidence that would answer it.
2. Choose the cheapest artifact with sufficient fidelity: diagram, schema, state machine, API stub, single HTML file, or throwaway code.
3. Mark it clearly as disposable and avoid production integration unless explicitly requested.
4. Present materially different alternatives when comparison is the point.
5. Ask the relevant human to react to the artifact; do not simulate their judgment.
6. Record the conclusion in the requesting RFC, map, or issue. When a durable prototype record exists, pass its adapter-returned reference to the requesting record's adapter for rendering. Do not construct a path, provider identifier, or link.
7. Delete or archive the prototype when it would otherwise be mistaken for supported code.

A prototype is evidence. Promote accepted outcomes to an RFC resolution, ARP, specification, or issue.
