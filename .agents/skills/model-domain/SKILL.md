---
name: model-domain
description: Build and sharpen a project's domain vocabulary and context boundaries. Use when terminology is vague, overloaded, contradictory, or newly resolved.
license: MIT
---

# Model Domain

Maintain the project's ubiquitous language while design work happens.

## Locate the model

Read `.agents/workflows.yaml` and `docs/agents/records.md`. Resolve the `domain` route and follow its generated adapter guidance. Use adapter `list` or search before proposing a new domain record. If the route is disabled, do not persist without approval; use an approved temporary or external draft when appropriate.

## During discussion

- Challenge terms that conflict with the existing language.
- Propose one canonical name for overloaded concepts.
- Invent concrete edge cases to test boundaries and relationships.
- Check whether code and documentation agree with stated behavior.
- Update the domain model immediately after a term is explicitly resolved.

Use [the context format](references/context-template.md). Present the proposed terminology changes before persistence. After confirmation, use adapter `create` or read the latest revision and use guarded `update`.

The domain model is a glossary, not a specification or decision log. It must not contain implementation choices, meeting history, plans, or general programming terms. Send unresolved designs to `develop-rfc` and accepted consequential technical decisions to `record-arp`.

For multiple bounded contexts, maintain a context map using adapter-returned references to each context glossary and describing their relationships. Let the destination adapter render references; do not construct paths or links. Do not introduce multiple contexts merely because the repository is a monorepo.
