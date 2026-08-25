---
name: prepare-handoff
description: Prepare a compact handoff so another agent or session can continue work without duplicating durable artifacts. Use when work will continue in a fresh context.
disable-model-invocation: true
license: MIT
---

# Prepare Handoff

Write a compact handoff tailored to the next session's purpose. Read `.agents/workflows.yaml` and `docs/agents/records.md`. Resolve the `handoffs` route and follow its generated adapter guidance. When the route is disabled, keep the handoff temporary or external and do not persist it without approval.

Include:

- the intended next outcome;
- current state and what changed in this session;
- unresolved questions and immediate next actions;
- relevant paths, issue links, branches, and commands;
- verification already performed; and
- suggested skills for the next session.

Do not duplicate specifications, RFCs, ARPs, maps, issues, commits, or diffs. Link them. Redact credentials, secrets, and unnecessary personal information.

After approval, use adapter `create` or revision-gated `update` and report its returned reference. Do not construct a path, provider identifier, or link. The adapter owns lazy destination creation.
