---
name: review-implementation
description: Review actual implementation against authoritative intent and return an evidence-based conformance verdict without modifying the work under review.
license: MIT
---

# Review Implementation

Review one bounded implementation. Find material discrepancies; do not silently repair them. Read `.agents/workflows.yaml` and `docs/agents/records.md`, resolve the `issues` route, and follow its generated adapter guidance for any approved publication. If the route is disabled, do not persist the review without approval.

## Establish scope

Read project guidance and repository status. Identify the implementation issue or settled plan, relevant commit range or working-tree changes, and the behavior or component under review. If the authoritative intent or change set is ambiguous, ask for clarification before reviewing.

Read only context relevant to that scope:

- issue outcome and acceptance criteria;
- agreed specifications;
- accepted ARPs;
- applicable domain and project conventions;
- RFC resolution when it explains, but does not replace, authority;
- actual code and configuration;
- tests and fixtures;
- user and operator documentation; and
- relevant diff, commits, build output, and runtime evidence.

Use this authority ordering:

1. specifications define agreed behavior;
2. accepted ARPs constrain consequential technical choices;
3. issues define the executable slice;
4. project guidance defines documented conventions; and
5. code and tests show current behavior but do not override unmet intent.

RFC discussion is context. Supporting research, prototypes, maps, meetings, and review notes are evidence. Report contradictions between authoritative artifacts instead of choosing one silently.

## Inspect the implementation

Trace each in-scope acceptance criterion and material authoritative requirement to concrete implementation and verification evidence. Inspect important failure behavior, boundary conditions, compatibility, security, operability, documentation, and unintended scope changes where applicable.

Run the narrowest stable existing verification that can test disputed or high-risk behavior. Ask before expensive, destructive, production-facing, or externally visible commands. A passing test suite is evidence, not proof of conformance; a test name is not evidence that its assertion covers the requirement.

When observed runtime behavior is uncertain, recommend `investigate-failure`. When an accepted defect lacks durable protection, recommend `capture-regression`. Route an approved follow-up report through `triage-issue` rather than creating it silently.

Do not edit code, configuration, tests, fixtures, documentation, or generated files. Do not run formatters or commands known to rewrite the repository.

## Record findings

Report only material correctness, safety, security, operability, compatibility, scope, documented-convention, or verification gaps. Do not report undocumented style preferences.

Use [the review template](references/implementation-review-template.md). Each finding must include:

- **Severity:** `Blocking` when the implementation cannot claim conformance; `Follow-up` when accepted behavior is present but a material non-blocking improvement remains;
- authoritative expectation with a precise link or quotation;
- concrete code, configuration, test, documentation, or runtime evidence;
- impact within the reviewed scope; and
- recommended disposition without implementing it.

Order findings by severity and impact. Do not hide a blocking discrepancy in a general summary.

## Assign one verdict

Return exactly one verdict:

- **Conforms:** no material discrepancy was found within the stated scope;
- **Conforms with follow-up:** accepted behavior is present and every finding is non-blocking; or
- **Does not conform:** at least one material conflict exists with agreed behavior, an accepted decision, an acceptance criterion, or required failure handling.

`Conforms` does not prove that no defect exists. An empty findings list must still identify scope, authorities, inspected implementation, and verification performed. If verification could not run, state the limitation and reduce confidence; do not convert missing evidence into a passing claim.

## Confirm disposition

Present the complete review and verdict before any issue operation. Ask the user whether to:

- add the review to the implementation issue;
- leave the issue unchanged;
- change issue status;
- route an approved finding for triage; or
- request further evidence.

Use the `issues` adapter for approved operations, reading the latest revision before guarded `comment` or `update`. Add the review to the requesting issue; do not create a separate review record. Do not create follow-up issues, alter status, or modify the implementation without separate approval and workflow. Report performed operations and adapter-returned references; do not construct paths, provider identifiers, or links.
