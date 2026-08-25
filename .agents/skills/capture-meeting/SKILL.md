---
name: capture-meeting
description: Capture concise meeting minutes and identify decisions, requirements, actions, and open questions for promotion to canonical artifacts. Use only when meeting records are wanted.
disable-model-invocation: true
license: MIT
---

# Capture Meeting

Meeting notes are optional historical evidence. They are not the canonical source of technical decisions, requirements, or work.

Read `.agents/workflows.yaml` and `docs/agents/records.md`. Resolve the `meetings` route and follow its generated adapter guidance. If the route is disabled, ask before persistence and use an approved temporary or external draft when appropriate. Use [the meeting template](references/meeting-template.md).

## Capture

- Record purpose, participants when appropriate, and concise discussion notes.
- Separate observed decisions, new or changed requirements, actions, and open questions.
- Attribute owners and due dates only when stated.
- Mark uncertainty; do not infer consensus from silence.
- Avoid unnecessary personal or sensitive information.

## Promote

After drafting, ask which extracted items should become authoritative:

- technical ambiguity -> `develop-rfc`;
- consequential accepted technical decision -> `record-arp`;
- agreed behavior or requirement -> `author-specification`;
- action or implementation slice -> the `issues` route; and
- resolved terminology -> `model-domain`.

Present the minutes before persistence. After confirmation, use meeting adapter `create` or revision-gated `update`. Create promoted records only after separate confirmation through their semantic routes, then have the meeting adapter render their returned references in the minutes. Treat references and revisions as opaque; do not construct paths, provider identifiers, or links. A fact appearing only in meeting notes remains non-authoritative.
