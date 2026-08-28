<!-- agent-workflows-record
{"archived":false,"created":"2026-08-28T14:13:21Z","id":"distributing-and-activating-a-fiew-agent-skill","modified":"2026-08-28T14:13:21Z","record_type":"research","title":"Distributing and activating a fiew Agent Skill"}
-->
# Question

What repository layout, installation commands, scopes, and activation semantics does the first-party Skills CLI support, and can those semantics implement fiew's "suggest review after every change" behavior?

This informs whether `synthlike/fiew` can distribute one portable skill directly or requires additional persistent agent guidance.

# Findings

## Verified facts

- The npm package `skills` is the Vercel Labs Skills CLI. `npm view skills` reported version `1.5.23` during this investigation.
- The CLI installs from GitHub shorthand such as `owner/repo`; project scope is the default and `--global` selects user scope.
- `--skill <name>` selects one skill from a repository.
- The CLI discovers root `SKILL.md` files and skills below standard containers including `skills/` and `.agents/skills/`.
- A skill is a directory containing `SKILL.md`. The Agent Skills specification requires `name` and `description`; the name must match the parent directory.
- Agent Skills use progressive disclosure: agents see skill names and descriptions at discovery, then load full instructions when a task matches a description.
- Hooks are not portable across the CLI's supported agents. The CLI compatibility table reports hook support for only a subset of agents.

## Repository consequence

This repository already contains internal workflow skills under `.agents/skills/`, a location the CLI scans. A distributable fiew skill should therefore live at `skills/fiew/SKILL.md` and installation should explicitly select it:

```sh
npx skills add synthlike/fiew --skill fiew
npx skills add synthlike/fiew --skill fiew --global
```

This avoids a custom npm package and avoids selecting the repository's internal workflow skills.

## Interpretation

A standard skill can provide broad, portable best-effort coverage by making its description explicitly match:

- any task that modifies repository files;
- completion of a reviewable change; and
- an explicit handoff after a fiew review.

The body can require the agent to suggest `fiew .` after changes and use `fiew review show` and `fiew review reply` after an explicit handoff.

## Remaining uncertainty

The open specification leaves activation to each agent. A portable skill cannot strictly guarantee that every supported agent will activate it or suggest fiew after every change. There is no cross-agent completion hook. Achieving a strict guarantee would require agent-specific hooks or persistent instructions and would reduce portability.

# Recommendation

Start with one standard `fiew` skill and document the activation limitation. Do not maintain a custom installer yet. Test post-change activation and review handoff behavior in representative supported agents before adding harness-specific guidance.

# Primary sources

- Vercel Labs Skills CLI README: https://github.com/vercel-labs/skills/blob/main/README.md
- Vercel Labs Skills CLI source and discovery tests: https://github.com/vercel-labs/skills
- Agent Skills specification: https://agentskills.io/specification
- Agent Skills overview and activation model: https://agentskills.io/home
