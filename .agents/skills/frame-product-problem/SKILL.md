---
name: frame-product-problem
description: Help a founder challenge a solution-first product idea, frame a testable problem hypothesis, and plan customer validation without claiming unsupported certainty.
license: MIT
---

# Frame Product Problem

Help a founder make a product premise explicit and testable. Do not defend the proposed solution or declare the problem validated from discussion alone.

## Load existing evidence

Read project guidance, existing product or discovery documents, domain context, prior interviews and meetings, research, prototypes, decisions, specifications, issues, and repository status. Preserve existing conventions and confidential information.

Establish which role the participant holds and which product decision this work will inform. Treat founder statements as hypotheses or decisions, not automatically as customer or market facts.

## Interview the founder

Ask exactly one question at a time. Start with the ambiguity most likely to invalidate the opportunity, explain briefly why it matters, and adapt the next question to the answer. Do not dump a generic questionnaire or ask for facts already present in project evidence.

Be constructive but independent. Challenge confidence with evidence questions, not argument. Separate:

- the proposed solution;
- the claimed problem and undesired current state;
- context and trigger;
- current behavior, alternatives, and workarounds;
- desired outcome;
- why changing may matter now; and
- what remains unknown.

Distinguish user, buyer, beneficiary, decision maker, administrator, and other affected actors when roles differ. Narrow broad audience labels into behaviorally meaningful segments; do not invent a persona from demographics alone.

For every material claim, classify it as:

- **Founder belief:** a claim held by the founder;
- **Direct observation:** something actually observed, with source and context;
- **External evidence:** a cited fact from outside the conversation;
- **Interpretation:** a conclusion drawn from evidence; or
- **Unknown:** an unanswered material question.

Probe problem frequency, consequence, underserved need, segment differences, alternative explanations, and evidence against the idea. Ask what people do today and why that may be good enough. Examine willingness to change behavior, accept switching cost, spend time, or pay; do not expand into pricing strategy, unit economics, or go-to-market design.

## Frame the hypothesis

Create a concise problem hypothesis only after the founder's framing is coherent:

> When [actor] is in [context or trigger], they experience [problem], currently use [alternative], and seek [outcome]. We believe changing matters because [evidence or explicitly labeled assumption].

List counter-hypotheses and narrower segment hypotheses fairly. Identify the assumptions most likely to invalidate the opportunity rather than the easiest claims to confirm.

Read `.agents/workflows.yaml` and `docs/agents/records.md`. Resolve the `problem_framing` route and follow its generated adapter guidance. Use [the problem-framing template](references/problem-framing-template.md). Prefer an existing brief found through adapter `list` or search and use revision-gated `update` when it owns the same hypothesis. Otherwise propose adapter `create`. If the route is disabled, do not persist without approval; use an approved temporary or external brief. Never assume or construct a backend destination.

The brief is supporting evidence. It does not replace domain documentation, an RFC, ARP, specification, issue, or current behavior.

## Confirm the brief

Show a complete dry run containing:

1. proposed problem hypothesis and audience distinctions;
2. claims with their evidence classifications;
3. alternatives, workarounds, and counter-hypotheses;
4. prioritized risky assumptions;
5. unresolved founder questions;
6. proposed validation plan and evidence thresholds;
7. target semantic record and structure; and
8. every adapter mutation and workspace file to create or change.

Wait for explicit approval before writing. Preserve existing discovery history; update and link rather than overwrite contradictory evidence.

## Plan customer validation

For each risky assumption, define the cheapest ethical evidence that can discriminate between competing explanations. State what result would strengthen, weaken, contradict, or leave the assumption inconclusive.

Possible evidence includes consented interviews, observation, existing behavioral data, focused `research-question` findings, or a disposable `prototype-design` experiment. External market facts can inform framing but cannot substitute for customer or behavioral evidence.

After founder framing is coherent, invoke `prepare-questionnaire` for a separate customer guide. Questions must:

- ask about concrete past behavior, recent examples, triggers, consequences, and current alternatives;
- avoid pitching the solution before understanding the problem;
- avoid hypothetical compliments, desired-answer wording, and unsupported willingness-to-pay claims;
- distinguish user, buyer, and beneficiary evidence; and
- respect consent, privacy, confidentiality, and project retention guidance.

Use `capture-meeting` for approved session records and promote only supported outcomes. Use `plan-initiative` when validation exposes a landscape of dependent decisions. Route consequential accepted technical decisions through `record-arp`, agreed product behavior through `author-specification`, and resolved domain terms through `model-domain`.

Do not fabricate participants, quotes, observations, metrics, or experiment results.

## Reassess from evidence

When returning after interviews or experiments, read the prior brief and linked evidence. Assign each assumption exactly one state:

- `Unexamined`
- `Supported`
- `Weakened`
- `Contradicted`
- `Inconclusive`

Cite the evidence for every state. Preserve segment differences, negative cases, and contradictory observations. Do not count repeated founder assertions as independent evidence or turn a small convenience sample into a universal claim.

Recommend one next direction with rationale: continue, narrow, reframe, pivot, or stop. The founder decides. Never label the product idea or problem “validated” unless the project has explicit evidence criteria and the cited customer or behavioral evidence meets them.

Before updating the brief, show changed evidence states, revised hypotheses, retained contradictions, recommendation, expected revision, and exact mutations for approval. Report the resulting adapter reference, evidence references, open assumptions, approved next workflows, and every workspace change. Let adapters render references; do not construct paths, provider identifiers, or links.
