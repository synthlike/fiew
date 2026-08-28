<!-- agent-workflows-record
{"archived":false,"created":"2026-08-25T21:48:04Z","id":"fiew-v0-1","modified":"2026-08-28T08:58:45Z","record_type":"specs","title":"fiew v0.1"}
-->
# fiew v0.1

## Problem

Developers working with coding agents need a fast terminal workspace for inspecting a repository, reviewing current changes, discussing findings with an agent, and withholding approval until every concern is resolved. A general editor exposes source and Git mutation that is unnecessary and risky for this review-first workflow.

## Desired behavior

On Apple Silicon macOS in Ghostty, a reviewer can browse immutable source, inspect current staged, unstaged, and untracked Git changes through a VCS view, hold anchored reviewer-agent conversations, keep private bookmarks for later inspection, and approve only after explicitly resolving every thread. An agent can discover a named review, read its complete history, and append replies through a stable non-interactive interface without receiving source-write or review-lifecycle authority.

## Requirements

### 1. Read-only boundary

1. fiew must never modify source files, tracked files, `.gitignore`, Git metadata, the index, branches, commits, or other Git state.
2. fiew must not invoke mutating Git commands, apply workspace edits, execute language-server commands, or expose general file-writing operations.
3. fiew may write only fiew-owned global state, bounded diagnostics when explicitly enabled, disposable caches, canonical review files within `.reviews/`, and canonical bookmark files within `.bookmarks/`. fiew neither checks nor modifies Git ignore configuration.
4. Agent review commands may mutate only the operation explicitly granted by that command. In v0.1, the only agent mutation is appending a reply to an existing thread.
5. Integration failures, cancellation, malformed input, and persistence errors must preserve this boundary.

### 2. Platform and workspace

1. v0.1 supports Apple Silicon macOS in Ghostty.
2. The supported repository target is up to 10,000 tracked files.
3. At 100 columns or wider, the sidebar appears beside the main view at 30% width, clamped to 24–40 columns. Below 100 columns it becomes a full-height overlay. Below 60×20 fiew shows an unsupported-size message.
4. v0.1 displays one main view at a time. Tabs, arbitrary splits, and simultaneous main views are excluded.
5. Location history supports backward and forward navigation.

### 3. Sidebar contexts and previews

1. The sidebar has four user-visible contexts: Project, VCS, Review, and Bookmarks.
2. `Space p`, `Space v`, `Space r`, and `Space b` open their respective context namespaces. Git is the only v0.1 VCS backend and is identified as the active backend in the VCS view.
3. Each context preserves its own selection and scroll position.
4. Project uses a directory tree; VCS groups changed files by Git state; Review groups threads by file, anchor, and status; Bookmarks lists private saved source locations.
5. Moving over an item previews it without moving focus or altering history. `Enter` pins the preview, adds a history location where applicable, and focuses the main view.
6. `Esc` or sidebar collapse restores the last pinned view. `Tab`, `Shift-Tab`, and mouse clicks move focus. The focused region is visually explicit.

### 4. Modal interaction

1. v0.1 uses one contiguous, selection-first selection.
2. Persistent modes are Normal, Extend, and Command. Command may host transient fiew-owned text composers.
3. Insert and Replace modes, multiple selections, macros, remapping, and search-result selections are excluded.
4. Character movement operates on displayed grapheme clusters. Vertical movement preserves the preferred visual column.
5. Required movement bindings are `h j k l`, `w b e`, `g g`, `g e`, `Ctrl-u`, `Ctrl-d`, PageUp, and PageDown.
6. Required selection bindings are `v`, `x`, `;`, and `Alt-;`.
7. `Space` opens the leader menu; `:` opens named-command search. Both use one command registry and show disabled reasons.
8. `Space ?` shows generated key help. `Esc` safely cancels transient interaction. Quitting requires an explicit named or leader command.

### 5. Immutable documents and Zig structure

1. Every displayed document is an immutable, versioned snapshot. Selections, history, parsing, diffs, folds, threads, and bookmarks refer to snapshot identity and byte ranges.
2. NUL-containing files appear as binary metadata views. Other invalid UTF-8 renders replacement characters while preserving byte mapping and disables structural processing.
3. External reloads publish a new snapshot, and stale asynchronous results cannot alter the current view.
4. Tree-sitter highlighting, folding, and structural navigation are available for Zig. Other files remain fully navigable plain text.
5. Files over 2 MiB use plain-text fallback. Parsing occurs outside rendering and preserves the previous valid snapshot during reload.
6. Zig fold commands remain `z c`, `z o`, `z a`, `z M`, and `z R`. Structural commands remain `Alt-o`, `Alt-i`, `Alt-n`, and `Alt-p`.

### 6. Current-change VCS review

1. Git supports standard repositories and linked worktrees. Non-Git directories remain browsable with VCS disabled; bare repositories are unsupported.
2. VCS shows Staged (`HEAD` to index), Unstaged (index to working tree), and Untracked changes separately. Unborn repositories compare the index with Git's empty tree.
3. Added, modified, deleted, renamed, type-changed, mode-only, binary, and submodule entries are visible. Renames use 50% similarity; copies are excluded.
4. Text changes use unified diffs with three context lines and old/new line numbers. Unsupported textual forms show metadata rather than fabricated hunks.
5. `[ f`/`] f`, `[ h`/`] h`, and `[ c`/`] c` navigate files, hunks, and changed lines. `Enter` opens source context and `Ctrl-o` returns.
6. Git work runs outside the terminal event loop. Every command failure is explicit, repository-root identity is preserved, and only a complete internally consistent snapshot may replace the prior snapshot.
7. Debounced filesystem change or a manual VCS refresh requests a new snapshot. Failure retains and marks the previous snapshot stale; obsolete work cannot publish.
8. fiew never uses hooks, pagers, prompts, external diff drivers, text converters, or mutating Git operations.

### 7. Review threads

1. A review contains stable threads. A thread attaches to a changed file or to one contiguous old-side or new-side textual diff selection.
2. Anchors include repository identity, Git group, path, side, line range, available blob identifiers, and surrounding context sufficient for exact matching.
3. Each thread contains ordered, append-only comments. Every comment records the author role `reviewer` or `agent`; individual agent identity is not required.
4. Neither role edits or deletes a persisted comment. Only the reviewer creates threads, resolves or reopens them, or deletes a complete thread. Deletion requires confirmation.
5. Agents may read all prior comments and append replies. Agents may not create threads or change thread status.
6. Thread states are Open, Resolved, and Outdated. Open and Outdated threads block approval. A review is approved only when the reviewer explicitly resolves every thread.
7. Exact unique anchor matches preserve identity and lifecycle state across Git groups or refreshes. Missing or ambiguous matches become Outdated; fiew never guesses.
8. The reviewer composer accepts multiline UTF-8 plain text. Saving and cancellation protect modified text.
9. The Review sidebar supports independent keyboard and mouse selection, preview, scrolling, status visibility, and navigation.

### 8. Agent review interface

1. `fiew review start [--name <slug>] [--repo <path>]` creates a new review, atomically marks it current, and opens the interactive reviewer UI.
2. `fiew review open [<review-id>] [--repo <path>]` opens the current review when the ID is omitted. An explicit ID opens that historical review and atomically makes it current.
3. `fiew review show [<review-id>] [--repo <path>]` emits a stable machine-readable JSON projection of the current review by default, including every public thread, anchor, status, and ordered comment. `--format markdown` emits a human-readable projection of the same public review semantics. An explicit ID accesses history without changing current. Neither output is the canonical stored file, and storage-only metadata may be omitted.
4. `fiew review reply [<review-id>] <thread-id> --body-file <path> [--repo <path>]` appends one `agent` comment to current when the review ID is omitted, or to the explicit historical review otherwise, and performs no other mutation. Agent operations never change current.
5. Each repository has at most one explicit current-review pointer. Approval does not clear it; only reviewer `start` or `open` changes it. Missing, malformed, or dangling current state fails explicitly and is never inferred from content, timestamps, filenames, or directory order.
6. Repository selection defaults to the current working directory. The optional `--repo` overrides it.
7. Every newly created review ID begins with a local datetime prefix. An explicit name contributes a sanitized slug. Without a name, interactive start generates a bundled adjective-noun slug. Canonical reviews use `.json`; a numeric suffix resolves collisions.
8. Interactive start prints the canonical review ID after terminal restoration.
9. Invalid identifiers, roles, schemas, paths, or operations fail explicitly. Successful status and approval output must agree with durable state; persistence failure is never reported as approval.
10. Exit status is zero only when every thread is reviewer-resolved. Open, Outdated, malformed, or unsaved review state produces a non-success result.

### 9. Bookmarks

1. Bookmarks are private reviewer navigation state and never appear in review output available to agents.
2. They are stored as repository-local private state in `.bookmarks/bookmarks.json`. fiew does not inspect or modify ignore configuration and does not expose bookmarks through review commands.
3. A bookmark records a source location and may have a short optional label.
4. Creating a bookmark from a diff maps it to the corresponding source location; reopening never presents a historical diff as current source.
5. Bookmarks re-anchor only through an exact unique match. Missing or ambiguous locations become Outdated and never move heuristically.
6. `Space b Enter` shows the Bookmarks sidebar, `Space b n` creates a bookmark through an optional-label composer, and `Space b d` deletes the selected bookmark with confirmation. `[ b` and `] b` navigate previous and next bookmarks.

### 10. Persistence and diagnostics

1. Canonical reviews and bookmarks are private schema-versioned JSON using the common `{ "schema": "fiew.<artifact>/v<version>", "data": ... }` envelope with no separate version field. Reviews use `fiew.review/v1` in `.reviews/<review-id>.json`; bookmarks use `fiew.bookmark/v1` in `.bookmarks/bookmarks.json`.
2. Writes use same-directory temporary files, flush, atomic replacement, and one previous validated `.bak` backup. The current-review pointer is atomically replaced and validated before use.
3. Unknown future schemas are never overwritten. Existing `.reviews/*.md` and unreleased global bookmark data are not migrated or interpreted as current state. Arbitrary Markdown comment bodies remain ordinary JSON strings in canonical reviews.
4. Diagnostic history is bounded. File logging is opt-in and redacts source, comment bodies, environment values, and protocol payloads by default.
5. Recoverable failures disable only the affected capability and preserve the last valid snapshot. Fatal terminal failures restore terminal state before reporting.

## Constraints and decisions

- Zig 0.16.0 on Apple Silicon macOS and Ghostty.
- Low-level libvaxis; no `vxfw`.
- Direct Tree-sitter C adapter with the pinned Zig grammar.
- Installed Git CLI behind the VCS surface; no generic VCS abstraction or libgit2 in v0.1.
- Single-owner event-driven ports-and-adapters architecture with typed asynchronous effects.
- Pure fiew-owned ViewModel and RenderPlan pipeline.
- No source-writing feature, generic LSP framework, language server, Node, Chromium, SQLite, or application framework.

## Verification

- Pure command and reducer tests verify modes, context bindings, role permissions, thread lifecycle, bookmark behavior, stale-event rejection, and disabled reasons.
- Fixed-dimension RenderPlan snapshots verify Project, VCS, Review, Bookmarks, status, source, diff, binary, outdated, and error views.
- Document and anchor fixtures verify UTF-8 mapping, reload generations, multiline/file threads, diff-to-source bookmarks, exact-unique relocation, ambiguity, and Outdated transitions.
- Git adapter tests verify repository discovery, nested-directory roots, nonzero exits, snapshot consistency, cancellation, linked worktrees, and the mutation boundary.
- Artifact-format tests verify the common internal JSON envelope, arbitrary Markdown comment bodies, legacy rejection, schema refusal, backup recovery, atomic persistence, current-review pointer validation and authority, public JSON and Markdown projections, bookmark isolation from review output, and persistence-aware exit status.
- `zig build test` requires no network or optional executable. Git integration tests remain opt-in.
- Manual Ghostty checks cover startup/restoration, keyboard and mouse interaction, resize, all four sidebar contexts, review conversations, and representative source/diff rendering.

## Out of scope

- Source editing or Git mutation.
- Linux, Windows, Intel macOS, or non-Ghostty terminals.
- Markdown syntax/folding, Mermaid preview, or fuzzy file finding.
- ZLS, go-to-definition, references, hover documentation, or other language-server behavior.
- Additional grammars or language ecosystems.
- jj or any VCS backend other than Git.
- Commit history, branch comparison, staging, committing, merge, or conflict workflows.
- Remote review systems, GitHub synchronization, shared bookmarks, reactions, and attachments.
- Tabs, arbitrary splits, multiple selections, key remapping, or macros.
- Homebrew and other package managers.

## Open items

- Artifact naming, signing, notarization, and release automation remain non-blocking release follow-up.
- Replacement of the libvaxis commit pin when a compatible release exists.
- Empirical profiling of the accepted repository and parsing limits.

## References

- [Implement fiew v0.1](<.project/issues/ISSUE-0013-implement-fiew-v0-1.md>)
- [fiew v0.1 engineering baseline](<docs/engineering/fiew-v0-1-engineering-baseline.md>)
- [Adopt libvaxis’s low-level API for fiew v0.1](<docs/decisions/ARP-0001.md>)
- [Integrate Tree-sitter behind a direct C adapter](<docs/decisions/ARP-0002.md>)
- [Structure fiew as a single-owner event-driven application](<docs/decisions/ARP-0005.md>)
- [Store review notes as gitignored `.reviews/` Markdown for agent retrieval](<docs/decisions/ARP-0006.md>)
- [Use reviewer-owned local threads with command-mediated agent replies](<docs/decisions/ARP-0007.md>)
- [Store reviews and bookmarks as private repository-local JSON artifacts](<docs/decisions/ARP-0008.md>)
- [Use unified internal JSON artifacts for reviews and bookmarks](<docs/rfcs/RFC-0001.md>)
- [Use an explicit current review for routine agent handoff](<docs/decisions/ARP-0009.md>)
- [Use an explicit current-review pointer for routine agent handoff](<docs/rfcs/RFC-0002.md>)
