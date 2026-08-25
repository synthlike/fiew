---
name: capture-regression
description: Encode an accepted, reproducible defect as the smallest durable automated check without changing production behavior.
license: MIT
---

# Capture Regression

Turn an established defect into a durable check that fails for the diagnosed reason before the production fix.

## Verify the starting point

Read `.agents/workflows.yaml` and `docs/agents/records.md`. Resolve the `issues` route and follow its generated adapter guidance for any approved issue update. If the route is disabled, do not persist an issue update without approval. Read project guidance, the defect issue, specification or other source of expected behavior, referenced investigation findings, existing tests and fixtures, test commands, workspace status, and affected implementation.

Proceed only when the defect is accepted and either reliably reproduced or supported by a sufficiently established failure mechanism. If the behavior or cause remains speculative, stop and use `investigate-failure`; do not encode an assumption as a contract.

Record the current working tree and existing test baseline. Preserve unrelated user changes. Never expose secrets, personal data, production records, or unstable shared services through a regression fixture.

## Select the test seam

Choose the narrowest stable test level that demonstrates the violated user-visible or contract-visible behavior. Prefer public interfaces and existing test conventions over private implementation details.

A useful regression check:

- fails before the production fix for one recognizable reason;
- would pass when the accepted behavior is restored;
- minimizes fixtures, assertions, timing, data, network, and environment requirements;
- does not duplicate an existing check; and
- remains meaningful after internal refactoring.

Use a broader seam only when a narrower check cannot express the defect. If durable automation is impractical, explain why and propose a precise manual or higher-level verification alternative.

## Confirm

Show a dry run containing:

1. the accepted defect and authoritative expected behavior;
2. the proposed test level and why it is the narrowest stable seam;
3. every test and fixture file to create or change;
4. the exact narrow verification command;
5. the expected failing assertion or signal;
6. how the result will distinguish the diagnosed defect from setup failure; and
7. the project's policy for an intentionally red working tree or commit.

Wait for explicit approval before writing.

## Write the check

Change only approved test and fixture files. Do not change production code, configuration, documentation, or unrelated tests. Follow project naming, organization, isolation, cleanup, and assertion conventions.

Keep the check focused on observable behavior. Avoid broad snapshots, incidental implementation assertions, arbitrary sleeps, live external dependencies, and oversized fixtures when a smaller stable signal exists.

Run the approved narrow command. Confirm that:

- the new check executes;
- it fails at the intended assertion or observable signal;
- the failure matches the diagnosed mechanism;
- unrelated setup or environment errors do not explain it; and
- pre-existing checks have not been silently rewritten to accommodate the defect.

If it passes before the fix or fails for another reason, stop and revise the proposed seam or return to investigation. Do not weaken the expected behavior to manufacture the desired result.

## Report and hand off

If approved, add the regression result to the requesting issue through guarded `comment` or `update`; do not create a separate regression record. Use adapter-returned references and let the issue adapter render them rather than constructing paths, provider identifiers, or links.

Report:

- the protected defect and source of expected behavior;
- changed test and fixture files;
- exact command and relevant failing output;
- why the failure represents the defect;
- repository state and any unrelated pre-existing failures; and
- the separately tracked production-fix work or recommended next action.

Do not commit automatically. When project policy prohibits a failing commit, leave the approved check for the fix workflow to land atomically, or preserve the approved patch outside the committed branch as the user directs. A test captured here does not authorize implementing the fix.
