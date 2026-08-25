---
name: prepare-questionnaire
description: Prepare a focused Markdown questionnaire for a stakeholder who holds facts or decisions the current team lacks. Use for asynchronous discovery or meeting preparation.
disable-model-invocation: true
license: MIT
---

# Prepare Questionnaire

Grill the send, not the subject.

Read `.agents/workflows.yaml` and `docs/agents/records.md`. Resolve the `questionnaires` route and follow its generated adapter guidance. When the route is disabled, do not persist a questionnaire without approval; use an approved external location instead.

1. Ask who will receive the questionnaire: their role, expertise, and relationship to the work.
2. Ask what facts or decisions the user needs back in order to proceed.
3. Draft questions targeting that gap, most important first.
4. Give each question one idea and an answer area. Add why it matters only when needed to prevent a shallow answer.
5. Include enough context for someone who was not part of the preceding conversation.
6. State expected effort, deadline when known, and that partial or uncertain answers are useful.
7. After approval, use adapter `create` or revision-gated `update`. Return its adapter reference to the requesting RFC, meeting, map, or specification and let that destination adapter render it. When the route is disabled, save only to the approved external location. Do not construct a path, provider identifier, or link; report the returned reference.

Use [the questionnaire template](references/questionnaire-template.md). Answers are input. Promote them to RFCs, ARPs, specifications, domain docs, or issues only after the appropriate owner confirms them.
