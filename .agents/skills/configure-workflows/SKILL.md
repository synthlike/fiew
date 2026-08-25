---
name: configure-workflows
description: Configure a consumer workspace to use these workflows by selecting explicit record routes, backend instances, and optional capabilities. Use once when adopting the workflow kit in a new or existing project.
disable-model-invocation: true
license: MIT
---

# Configure Workflows

Inspect first, propose second, and write only after confirmation. Installation must not silently migrate existing artifacts.

## Lifecycle assets

Release identity, complete skill inventory, dependencies, and file integrity are defined by the embedded [distribution manifest](references/distribution-manifest.json). Use the deterministic [lifecycle command](references/lifecycle.py) for manifest inspection, closure, and installed verification; keep human intent, dry-run review, write approval, and harness discovery confirmation in this skill.

## Explore

From the consumer workspace root, inspect:

- whether the workspace uses Git, another version-control system, or no version control, and the discovered workspace boundary;
- Git remotes when present, whether the project uses GitHub Issues, authenticated `github.com` accounts, and the currently active account;
- an explicitly selected Bear `bearcli` executable and project workspace tag when Bear persistence is considered;
- the workflows explicitly selected by the user and the exact skill directories discovered by the harness;
- the installed distribution source and exact release version or immutable commit SHA;
- `AGENTS.md`, `CLAUDE.md`, or equivalent agent guidance;
- `.agents/workflows.yaml`, `docs/agents/records.md`, and generated assets under `docs/agents/backends/`;
- existing domain glossaries or context maps;
- directories containing ADRs, ARPs, RFCs, specifications, plans, meeting notes, research, questionnaires, technical baselines, prototypes, or handoffs;
- local issue conventions such as `.project/` or `.scratch/`;
- monorepo signals relevant to domain-document layout; and
- the nature of the project and how people and agents will collaborate on it.

## Recommend

Prefer existing conventions. For a new project, recommend:

- GitHub persistence for any suitable semantic records when an explicit GitHub Cloud repository and login pass identity and capability preflight; use native sub-issues and dependencies when `issues` is routed there;
- Bear persistence only for non-issue semantic records when an explicit absolute `bearcli` command and project workspace pass read-only capability preflight and the installed Bear adapter declares the complete record contract;
- otherwise local Markdown, committed when the workspace uses a commit-based version-control system;
- domain docs under `docs/domain/`;
- ARPs under `docs/decisions/`;
- RFCs under `docs/rfcs/`;
- specifications under `docs/specs/`;
- meeting notes disabled unless requested;
- research enabled under `docs/research/`;
- questionnaires enabled under `docs/questionnaires/`;
- technical baselines enabled under `docs/engineering/`;
- product problem framing enabled under `docs/product/`;
- retained prototypes disabled, with `docs/prototypes/` reserved if enabled;
- durable handoffs disabled, with `.agents/handoffs/` reserved if enabled; and
- a plain-language documentation style unless the project already defines one: use active voice, short sentences, explicit references, established domain terms, and one action per procedural step; avoid idioms, unnecessary synonyms, and ambiguous pronouns.

Git is not required. Do not ask whether Git exists when inspection already answers that question. When no version-control system is detected, ask whether the workspace is intentionally unversioned or whether the user intends to initialize or identify a version-controlled root. Explain that unversioned workspaces have no commit checkpoint or version-control history, but never initialize, change, or configure version control without approval. When another version-control system is present, preserve its conventions and use its landing terminology rather than assuming Git.

Ask what kind of project this is and how people and agents will collaborate on it. Profile questions may offer all-local, all-GitHub, mixed local/GitHub, or Bear-for-non-issues with a complete local/GitHub issue backend as shortcuts, but expand every answer into explicit routes for `issues`, `domain`, `arps`, `rfcs`, `specs`, `meetings`, `research`, `questionnaires`, `technical_baselines`, `problem_framing`, `prototypes`, and `handoffs`. Show and confirm the enabled state, named backend, and complete destination for every route, including disabled routes. Combine the answer with repository evidence to recommend each capability individually and explain the reason. An `enabled: false` route prohibits repository writes without approval but does not prohibit temporary or external output. Do not ask for facts available in the repository. If distribution identity cannot be established from installation metadata or the repository, ask for it rather than proposing a mutable value such as a branch name, `latest`, or `unreleased`.

When GitHub is considered, list authenticated account names and identify the active account without exposing tokens. Ask which login should own backend operations, even when an account is already active, and record the explicit repository and login in the named GitHub backend instance. When several accounts exist, never infer the intended identity from the active account alone. If the selected account is not active, ask the user to run `gh auth switch --hostname github.com --user LOGIN`, wait for confirmation, and recheck; never change global authentication silently.

For every GitHub backend instance, run bundled `references/backends/record-store/github.py --repo OWNER/REPO --login LOGIN --backend INSTANCE preflight` before recommending or asking approval for any route. Confirm the actual API identity, GitHub Cloud repository, enabled Issues, write permission, complete record contract, and—when `issues` uses the instance—native sub-issues and dependencies plus the complete issue contract. Stop on any missing capability or identity mismatch.

For every Bear backend instance, run bundled `references/backends/record-store/bear.py --command ABSOLUTE_BEARCLI --workspace WORKSPACE preflight` before recommending or asking approval for a non-issue route. Confirm the `bearcli` identity, exact single-workspace scope, required MCP tools and schemas, and provider record capabilities. The preflight is read-only and does not provision a tag or note. Stop if provider preflight fails or the immutable adapter declaration lacks the routed type or common operation. Never route `issues` to Bear or add a harness-specific MCP registration.

Generate a label-plan format 2 document with the same explicit repository and login. Show every proposed `workflow:record:*` and `workflow:issue:*` creation or update and apply only the exact reviewed plan after approval. Label provisioning is a separate external mutation; never apply it merely because routes were approved. Do not fall back to task lists, body-text dependencies, or unreviewed labels.

Use the lifecycle command to calculate the selected closure and inspect the exact harness-discovered directories. Require the complete distribution, even when the user explicitly selects only a subset of workflows. If any skill is absent, stop and list every missing skill. Ask the user to complete installation through their external installer or an intact manual copy, then confirm harness discovery and inspect again. Never create, replace, or remove a skill directory.

## Confirm

Show a dry run containing:

1. exact distribution identity;
2. user-selected workflows, calculated closure, and the complete discovered skill inventory;
3. any missing, unexpected, duplicate, incomplete, or modified skill and every blocking conflict;
4. `.agents/workflows.yaml`, based on [the example](references/workflow-config.example.yaml), with schema 3, exact distribution identity, named backend instances, all twelve explicit routes, selected workflows, and complete discovered skill-path inventory;
5. backend preflight and actual-identity results, reviewed GitHub label plans, and every generated file under `docs/agents/backends/`;
6. `docs/agents/records.md`, including all routes, portable operations, opaque references and revisions, disabled-route behavior, and approval boundaries;
7. `docs/agents/workflows.md`, including the authority table, pointer to record guidance, and preserved project writing policy or default plain-language style;
8. detected version-control state, the chosen consumer root, and whether completed issue work will have a commit or equivalent landing checkpoint;
9. the concise agent-instructions block pointing to workflow and record guidance; and
10. every other directory or file that would be created or changed.

Wait for explicit approval.

## Write

- Never write project configuration while the complete distribution is absent or fails integrity inspection.
- Do not require or initialize Git. Use the approved consumer workspace root whether it is Git-controlled, controlled by another system, or intentionally unversioned.
- Ask the harness to rediscover skills after external installation changes. Continue only after it confirms every distributed skill at its consumer-root-contained path.
- Write `.agents/workflows.yaml` as canonical schema 3 with every backend and all twelve routes explicit. Never write a placeholder or mutable distribution version.
- Copy the bundled [portable contract module](references/backends/record-store/contract.py) and exactly the guidance/helper pair for each backend type used by a route: [local Markdown guidance](references/backends/record-store/local-markdown.md) and [helper](references/backends/record-store/local-markdown.py), [GitHub guidance](references/backends/record-store/github.md) and [helper](references/backends/record-store/github.py), and/or [Bear guidance](references/backends/record-store/bear.md) and [helper](references/backends/record-store/bear.py). Do not generate assets for configured but unused backend instances. Do not create a local record destination directory until its first approved write.
- Apply only the exact approved GitHub label plan after configuration approval and a fresh stale-state check. Pass the configured repository, login, backend instance, and route destination explicitly to every helper operation.
- Do not generate legacy issue-tracker guidance or helpers outside `docs/agents/backends/`. Do not move or rewrite existing issues or records.
- Write `docs/agents/records.md` with all twelve configured routes, common operations, opaque references and revisions, destination-adapter reference rendering, generated backend assets, disabled-route behavior, and approval boundaries. Instruct workflows to use semantic keys and operations without constructing provider paths, identifiers, labels, tags, or links.
- Write `docs/agents/workflows.md` with the artifact authority table, a pointer to record routing, and a `## Documentation style` section. Preserve an existing project policy. Otherwise write: "Write clear, direct documentation. Prefer active voice, short sentences, explicit references, and established domain terms. Avoid idioms, unnecessary synonyms, and ambiguous pronouns. Use one action per procedural step."
- Add or update a short `## Engineering workflows` section in the existing agent-guidance file. Use [the seed block](references/agents-section.md). Do not replace surrounding instructions.
- Create `docs/agents/`, but create optional artifact and local-issue directories only when their first artifact is needed.

Run installed lifecycle verification against the exact rediscovered directories. Finish only when it passes, then list detected version-control state, created skill directories, written configuration and guidance, selected workflows, and calculated closure.
