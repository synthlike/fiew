---
name: investigate-failure
description: Reproduce unexpected behavior, test competing hypotheses, and establish a supported root cause or bounded uncertainty without implementing a permanent fix.
license: MIT
---

# Investigate Failure

Diagnose one unexpected behavior. Investigation produces evidence; it does not silently become repair work.

## Bound the investigation

Read `.agents/workflows.yaml` and `docs/agents/records.md`. Resolve the `issues` route and follow its generated adapter guidance for any approved publication. If the route is disabled, do not persist findings without approval. Read project guidance, the requesting issue or report, specifications and accepted ARPs, relevant code and configuration, tests, logs, recent changes, workspace status, and existing related issues.

State:

- expected behavior and its authoritative source;
- observed behavior without interpretation;
- affected environment and known scope;
- current reproducibility; and
- the decision or next action the diagnosis will inform.

If expected behavior is only a stakeholder belief, label it an unconfirmed expectation and use `clarify-intent` when human intent blocks diagnosis. Use `research-question` when an external platform fact materially determines expected behavior. Do not turn an unsupported expectation into a defect.

Preserve the initial repository state. Do not overwrite existing user changes, expose secrets or personal data, or broaden the work into unrelated cleanup.

## Reproduce

Find the smallest reliable command or procedure that exhibits the behavior. Record exact inputs, environment assumptions, expected signal, observed signal, frequency, and relevant timestamps or correlation identifiers.

Prefer an existing stable test or interface over a low-level implementation detail. Before running expensive, destructive, production-facing, or externally visible experiments, show the action and obtain approval.

If reproduction fails, vary one relevant factor at a time. Do not claim that inability to reproduce disproves the report.

## Test hypotheses

List multiple plausible hypotheses before committing to a cause. For each hypothesis, state:

- evidence it explains;
- evidence that would distinguish it from alternatives; and
- the cheapest safe discriminating check.

Test high-information, low-cost checks first. Update hypothesis status as supported, weakened, falsified, or untested. Inspect current code, configuration, logs, tests, and recent changes as evidence; do not infer cause from temporal proximity alone.

## Control probes

Use disposable instrumentation, test changes, or local data only when existing evidence cannot discriminate between hypotheses.

Before creating a probe:

1. show its files, scope, command, and expected evidence;
2. confirm it will not mutate production or shared state; and
3. obtain approval when it writes files or invokes an external system.

Track every probe. Remove it before completion and verify repository state unless the user explicitly approves retaining it as separate work. A useful probe is not automatically a durable regression check.

## Conclude

A root-cause conclusion must explain the observed mechanism and be supported by discriminating evidence. Otherwise state bounded uncertainty: what is known, what was falsified, what remains plausible, and which missing observation would continue the investigation.

Use [the findings template](references/failure-findings-template.md). Include:

- expected and observed behavior;
- reproduction reliability and exact procedure;
- environment and scope;
- evidence timeline;
- hypotheses and dispositions;
- supported root cause or bounded uncertainty;
- removed or retained probes;
- the smallest recommended next action; and
- verification performed.

A confirmed defect may next use `capture-regression`, but do not create a permanent test or implement a production fix in this workflow.

## Confirm publication

Present the findings before writing them to an issue or project document. Ask whether to:

- add detailed findings and a concise summary to the requesting issue or parent through guarded `comment` or `update`;
- continue investigation; or
- propose separately tracked regression or repair work.

Use the `issues` adapter for approved operations and read the latest revision before mutation. Do not create a separate failure-findings record. Use adapter-returned references and let destination adapters render them; do not construct paths, provider identifiers, or links. Do not create follow-up work, change issue status, or treat a recommendation as approved without confirmation.

Report every command run, file changed, probe removed or retained, source consulted, remaining uncertainty, and approved durable output. If investigation is blocked, stop with the evidence gathered and the smallest concrete requirement for resuming; do not claim a diagnosis.
