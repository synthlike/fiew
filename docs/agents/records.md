# Record routing and operations

`.agents/workflows.yaml` is authoritative for record routing. Workflows must resolve a semantic route and invoke its configured adapter. Do not construct provider paths, identifiers, labels, tags, or links.

## Routes

All routes use the `local` backend instance with type `local-markdown`.

| Semantic route | Enabled | Complete destination |
|---|---:|---|
| `issues` | yes | root `.project` |
| `domain` | yes | path `docs/domain` |
| `arps` | yes | path `docs/decisions`, prefix `ARP` |
| `rfcs` | yes | path `docs/rfcs`, prefix `RFC` |
| `specs` | yes | path `docs/specs` |
| `meetings` | no | path `docs/meetings` |
| `research` | yes | path `docs/research` |
| `questionnaires` | no | path `docs/questionnaires` |
| `technical_baselines` | yes | path `docs/engineering` |
| `problem_framing` | yes | path `docs/product` |
| `prototypes` | no | path `docs/prototypes` |
| `handoffs` | no | path `.agents/handoffs` |

Destinations are created lazily by the adapter on the first approved write.

## Generated adapter assets

The portable contract and local adapter are under `docs/agents/backends/`:

- `contract.py` defines portable request, response, reference, revision, and error shapes.
- `local-markdown.md` is the operational guidance for the configured backend.
- `local-markdown.py` performs local record and issue operations.

Read `docs/agents/backends/local-markdown.md` before invoking the helper. Pass the consumer root, backend instance name, and the complete configured destination to every operation.

## Portable record operations

Non-issue routes support `create`, `read`, `list`, `update`, and `archive`. Creation returns the semantic ID, exact revision, and complete reference. Update and archive require the latest returned revision. Listing may search by query.

Treat IDs, references, and revisions as opaque adapter-owned values. Preserve returned values exactly. Do not derive a filename or link from an ID. When one record refers to another, pass the complete returned reference to the destination adapter's reference renderer. The destination adapter owns the rendered Markdown.

## Portable issue operations

The `issues` route supports `create`, `read`, `list`, `update`, `comment`, `claim`, `resolve`, `cancel`, `parent`, `block`, and `frontier`. Every mutation after creation requires the revision from the latest read. Use `parent` and `block` for native issue relationships. Use `frontier` to find open, unassigned, unblocked children.

Issue status and relationship changes must go through the adapter. Do not simulate dependencies with task lists or body text. Treat issue IDs, references, and revisions as opaque.

## Disabled routes

An `enabled: false` route prohibits repository persistence unless the user separately approves that write. It does not prohibit an approved temporary or external draft. Do not create the configured destination merely to reserve it. The disabled routes are `meetings`, `questionnaires`, `prototypes`, and `handoffs`.

## Approval boundaries

Present workflow drafts before persistence when required by the workflow. Obtain separate approval before persisting through a disabled route, promoting one record into another authoritative route, or committing completed issue work. Configuration approval does not approve future record mutations or commits.

Never move or rewrite an existing record as part of routing. Use revision-gated updates, report stale-state failures, and ask before resolving conflicts.
