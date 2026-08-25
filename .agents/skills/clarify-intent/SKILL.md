---
name: clarify-intent
description: Clarify a plan, design, requirement, or decision through a disciplined one-question-at-a-time interview. Use when important intent or constraints remain ambiguous.
license: MIT
---

# Clarify Intent

Interview the user until both sides share a precise understanding. Read `.agents/workflows.yaml` and `docs/agents/records.md` before any durable update. Resolve the semantic route of the authoritative record and follow its generated adapter guidance.

- Explore the environment for facts instead of asking the user.
- Identify dependencies between decisions and resolve prerequisites first.
- Ask exactly one question at a time and wait for the answer.
- For every question, provide a recommended answer and concise rationale.
- Challenge contradictions with existing code, documentation, and domain language.
- Use concrete scenarios and edge cases to sharpen vague answers.
- Distinguish requirements, constraints, assumptions, preferences, and implementation choices.
- Update an authoritative record only when the user confirms the result and its route is enabled. Read its latest revision, use guarded `update`, and preserve the adapter-returned reference. Do not construct a path, provider identifier, or link.

Do not implement the work until the user confirms that clarification is complete.
