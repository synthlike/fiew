# fiew

**fiew improves the human-in-the-loop process when working with AI agents.**

It is a read-first terminal workspace for reviewing current Git changes.
The reviewer inspects a diff, leaves comments, asks an agent to respond,
and approves only after every concern is explicitly resolved.

## The workflow

An agent can make a large, plausible-looking change quickly. fiew gives the
reviewer a compact place to slow down, inspect the actual diff, and retain
questions that need answers.

1. Open the repository in fiew.
2. Open **Review · Diff · Git** and inspect Staged, Unstaged, and Untracked
   changes.
3. Create a thread on a changed line/range or on a whole file.
4. Ask an agent to read the review and append replies through the non-interactive
   review CLI.
5. Use **Review · Threads** to revisit, resolve, or delete complete threads.
6. Approve only when every thread is current and explicitly resolved.

fiew also supports bookmarks for source locations you need to revisit while
reviewing. Zig files receive Tree-sitter-powered syntax highlighting, code
folding, and basic structural navigation; other files remain plain text.

## Screenshots

**Review Diff** lets you focus on the actual change, with its anchored
discussion and agent replies alongside it.

<p>
  <img src="docs/images/review-diff-dark.png" alt="Dark Review Diff showing an inline reviewer-agent thread" width="49%">
  <img src="docs/images/review-diff-light.png" alt="Light Review Diff showing an inline reviewer-agent thread" width="49%">
</p>

**Project** provides the read-only repository context around the change, so you
can inspect related source between review passes.

<p>
  <img src="docs/images/project-browser-dark.png" alt="Dark Project sidebar and welcome view" width="49%">
  <img src="docs/images/project-browser-light.png" alt="Light Project sidebar and welcome view" width="49%">
</p>

## Quick start

Install Zig 0.16.0, fetch the locked dependencies, and run fiew in Ghostty:

```sh
zig build --fetch
zig build run -- /path/to/repository
```

Start the review workflow inside fiew:

```text
Space r d    open Review · Diff · Git
Space r t    open Review · Threads
```

In Review Diff, select a changed line or a one-side range and press `Space r n`
to create a thread. Use `Space r f` to comment on a whole changed file.

In Review Threads, select a thread and use:

```text
Space r a    append a reviewer comment
Space r r    resolve or reopen the thread
Space r x    delete the complete thread (with confirmation)
Enter        return to the thread's current diff anchor
```

## Agent handoff

The reviewer owns the review lifecycle. An agent receives a narrow, explicit
interface for discovering the current review, reading its public history, and
adding a reply:

```sh
# Create a reviewer-owned local review interactively.
fiew review start

# An agent can inspect the current review.
fiew review show

# It can add a reply to an existing thread, but cannot create, resolve,
# reopen, delete, or change the current review.
fiew review reply <thread-id> --body-file response.md
```

Review state is private repository-local JSON in `.reviews/`. fiew keeps one
explicit current-review pointer per repository, so routine `show` and `reply`
commands do not need to guess which review is active.

### Install the agent cooperation skill

The optional `fiew` Agent Skill teaches compatible coding agents to suggest a
review after a completed repository change and to respond when you explicitly
hand back a completed review. The `fiew` executable must already be installed
and available on the agent's `PATH`.

Install the skill for the current project:

```sh
npx skills add synthlike/fiew --skill fiew
```

Or install it globally for your user:

```sh
npx skills add synthlike/fiew --skill fiew --global
```

After reviewing, tell the agent **“Review done”**. It will use `fiew review
show` and `fiew review reply` to address Open or Outdated threads while leaving
thread resolution and approval to you. Skill activation is best-effort and
depends on the agent; the portable Agent Skills format cannot guarantee a
post-change hook on every supported agent. The skill never launches fiew or
blocks task completion while waiting for a review.

## Everyday navigation

| Key | Action |
| --- | --- |
| `Space r d` | Open or resume Review Diff |
| `Space r d r` | Refresh the current Diff snapshot |
| `Space r t` | Open Review Threads |
| `Space p` | Open Project |
| `Space b` | Open Bookmarks |
| `] f` / `[ f` | Next / previous changed file |
| `] h` / `[ h` | Next / previous hunk |
| `] c` / `[ c` | Next / previous changed line |
| `Enter` | Pin a preview or open source from a diff line |
| `Ctrl-o` / `Ctrl-i` | Back / forward through locations |
| `Space ?` | Generated key help |
| `:quit` or `Space q` | Quit |

The status line shows the current mode (`NOR`, `EXT`, or `CMD`) and active
leader path, such as `LDR r d`.

## What v0.1 supports

- Apple Silicon macOS in Ghostty;
- immutable repository browsing with location history;
- current Git review of Staged, Unstaged, and Untracked changes, including
  textual unified diffs and explicit metadata for unsupported textual forms;
- reviewer-owned file and line/range threads with agent replies, explicit
  resolution, and constrained exact-context re-anchoring after Git refreshes;
- private repository-local bookmarks for reviewer navigation; and
- Tree-sitter-powered Zig syntax highlighting, folding, and basic structural
  navigation (Zig is the only structural language in v0.1); and
- keyboard and mouse navigation with a selection-first modal interaction model.

## Development

```sh
zig build
zig build test
zig fmt --check src build.zig
```

`zig build test` is deterministic and does not need a network connection or an
installed Git executable. Git integration tests are opt-in:

```sh
zig build test -Dgit-integration
```

## Project documentation

- [v0.1 specification](docs/specs/fiew-v0-1.md)
- [engineering baseline](docs/engineering/fiew-v0-1-engineering-baseline.md)
- [architecture decisions](docs/decisions/)

## License

MIT. See [LICENSE](LICENSE).
