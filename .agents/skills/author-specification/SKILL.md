---
name: author-specification
description: Synthesize established requirements and decisions into a coherent implementation-neutral specification. Use when ambiguity is sufficiently resolved to describe what should be built.
disable-model-invocation: true
license: MIT
---

# Author Specification

Synthesize what is already established; do not silently reopen or invent decisions.

1. Read `.agents/workflows.yaml` and `docs/agents/records.md`. Resolve the `specs` route and follow its generated adapter guidance. Use adapter `list` or search for an existing specification that owns the same behavior. Read relevant domain records, accepted ARPs, resolved RFCs, and source issues or meeting outcomes through their semantic routes.
2. Explore the existing system enough to describe the current problem accurately.
3. Identify the highest stable seams through which behavior can be verified. Prefer existing seams.
4. Ask only about contradictions or missing decisions that prevent a coherent specification. Use `develop-rfc` when substantial ambiguity remains.
5. Draft using [the specification template](references/specification-template.md).
6. Review the draft with the user before adapter `create` or revision-gated `update`. If the `specs` route is disabled, do not persist without approval; use an approved temporary or external draft when appropriate.
7. Use adapter-returned references for sources and results rather than copying full contents or constructing paths, provider identifiers, or links.

Describe behavior and constraints, not a brittle sequence of file edits. Include code only when a small schema, state machine, or type shape encodes an accepted decision more precisely than prose.
