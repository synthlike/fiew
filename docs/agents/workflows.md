# Engineering workflows

This repository develops `fiew`, a Zig-based editor for agentic workflows. It focuses on viewing code and diffs and navigating codebases. Its design draws inspiration from the fx agent harness and flow editor.

Read `.agents/workflows.yaml` for installed workflows and route configuration. Perform all semantic record operations according to `docs/agents/records.md` ([record routing and operations](records.md)).

## Artifact authority

| Information | Authoritative artifact or route | Workflow |
|---|---|---|
| Current implemented behavior | Source code and verified tests | Implementation work |
| Planned work, initiative maps, and decision tickets | `issues` | `plan-implementation`, `plan-initiative` |
| Domain vocabulary and context boundaries | `domain` | `model-domain` |
| Consequential accepted technical decisions | `arps` | `record-arp` |
| Unresolved technical or design discussions | `rfcs` | `develop-rfc` |
| Agreed observable behavior and requirements | `specs` | `author-specification` |
| Historical meeting evidence | `meetings` | `capture-meeting` |
| Findings from external sources | `research` | `research-question` |
| Questions sent to other people | `questionnaires` | `prepare-questionnaire` |
| Production-compatible engineering foundation | `technical_baselines` | `establish-technical-baseline` |
| Product problem hypotheses and validation plans | `problem_framing` | `frame-product-problem` |
| Retained experimental artifacts | `prototypes` | `prototype-design` |
| Durable session continuation notes | `handoffs` | `prepare-handoff` |

Meeting notes, prototypes, and handoffs do not override specifications, accepted ARPs, source code, or resolved issues. Promote information through the workflow that owns the authoritative artifact.

## Working boundaries

Use the configured semantic route instead of constructing storage paths, labels, identifiers, or links. Review drafts before persistence when the workflow requires confirmation. A disabled route prohibits repository persistence without separate approval, but it may use an approved temporary or external output.

Treat each completed implementation issue as a landing boundary. Verify and resolve the issue before asking whether to commit its reviewed scope. Never commit automatically.

## Documentation style

Write clear, direct documentation. Prefer active voice, short sentences, explicit references, and established domain terms. Avoid idioms, unnecessary synonyms, and ambiguous pronouns. Use one action per procedural step.
