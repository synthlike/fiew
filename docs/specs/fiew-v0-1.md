<!-- agent-workflows-record
{"archived":false,"created":"2026-08-25T21:48:04Z","id":"fiew-v0-1","modified":"2026-08-26T14:38:11Z","record_type":"specs","title":"fiew v0.1"}
-->
# fiew v0.1

## Problem

Developers need a fast terminal tool for inspecting repositories, reading code, reviewing current Git changes, recording private review notes, and following Zig definitions without risking accidental source or Git modification. General editors expose broad editing and IDE behavior that is unnecessary for this read-first workflow.

## Desired behavior

On Apple Silicon macOS in Ghostty, a user can open a repository, browse and inspect files, navigate and fold Zig or Markdown structure, review current staged/unstaged/untracked changes, record local review notes, follow Zig definitions through optional trusted ZLS, and preview supported Mermaid fences as terminal text. Optional-integration failures preserve text viewing and the read-only boundary.

## Requirements

### 1. Read-only boundary

1. fiew must never modify source files or Git state.
2. fiew must not invoke mutating Git commands, apply LSP workspace edits, execute server commands, or write inside repositories or Git metadata, except that it may create and write review files within a gitignored `.reviews/` directory at the repository root ([ARP-0006](<docs/decisions/ARP-0006.md>)).
3. fiew may write only fiew-owned configuration, trust, explicitly enabled bounded diagnostics, disposable caches, and review notes in the repository's gitignored `.reviews/` directory. It never modifies `.gitignore`, tracked files, or any other repository path.
4. Integration failures and cancellation must preserve this boundary.

### 2. Platform and workspace

1. v0.1 supports Apple Silicon macOS in Ghostty.
2. The supported repository target is up to 10,000 tracked files.
3. At 100 columns or wider, the sidebar appears beside the main view at 30% width, clamped to 24–40 columns.
4. Below 100 columns, the sidebar becomes a full-height overlay.
5. Below 60×20, fiew shows an unsupported-size message.
6. v0.1 displays one main view at a time. Tabs, arbitrary splits, and simultaneous main views are excluded.
7. Location history supports backward and forward navigation.

### 3. Sidebar and previews

1. The collapsible sidebar shows one of Project, Git, or Review at a time.
2. Each context preserves selection and scroll position.
3. Project uses a directory tree; Git groups changed files by Git state; Review groups notes by file and source location.
4. Moving over a file, diff, or note previews it without moving focus or altering history.
5. `Enter` pins the preview, adds a history location, and focuses the main view.
6. `Esc` or sidebar collapse restores the last pinned view.
7. `Tab`, `Shift-Tab`, and mouse clicks move focus.
8. The focused region is visually explicit.

### 4. Modal interaction

1. v0.1 uses one contiguous, selection-first selection.
2. Persistent modes are Normal, Extend, and Command. Command may host the transient Note Composer for fiew-owned text.
3. Insert and Replace modes, multiple selections, macros, remapping, and search-result selections are excluded.
4. Character movement operates on displayed grapheme clusters and never selects inside an invalid encoding boundary. Vertical movement preserves the preferred visual column.
5. Required movement bindings are `h j k l`, `w b e`, `g g`, `g e`, `Ctrl-u`, `Ctrl-d`, PageUp, and PageDown.
6. Required selection bindings are `v` for Extend, `x` for line selection, `;` to collapse to the active end, and `Alt-;` to reverse ends.
7. `Space` opens the leader menu; `:` opens named-command search. Both use one command registry and show disabled reasons.
8. The status line shows mode, pending keys, the active line and visual column, and concise feedback. Focus remains visually explicit through the active region header. `Esc` safely cancels transient interaction.
9. `Space ?` shows generated key help. Quitting requires an explicit named or leader command.

### 5. Documents

1. Every displayed document is an immutable, versioned snapshot.
2. Selections, history, parsing, diffs, folds, and LSP operations refer to snapshot identity and byte ranges.
3. NUL-containing files appear as binary metadata views.
4. Non-NUL files with invalid UTF-8 render replacement characters while preserving byte mapping.
5. Invalid UTF-8 disables Tree-sitter, LSP, and Mermaid processing without changing source bytes.
6. External reloads publish a new snapshot and stale asynchronous results cannot alter the current view.

### 6. Syntax, folding, and structural navigation

1. Tree-sitter behavior is available for Zig and Markdown only; other files remain fully navigable plain text.
2. Files over 2 MiB use plain-text fallback.
3. Parsing occurs outside rendering, shows pending status after 100 ms, cancels after one second, and preserves the previous valid snapshot during reload.
4. Highlighting covers the viewport plus one viewport above and below.
5. Zig uses its pinned fold query. Markdown supports section and fenced-block folds. Indentation folding is excluded.
6. Fold commands are `z c`, `z o`, `z a`, `z M`, and `z R`.
7. Structural commands are `Alt-o` for a named parent, `Alt-i` for prior expansion, and `Alt-n`/`Alt-p` for named siblings.
8. Markdown may inject Zig parsing into explicitly labeled `zig` fences to one nesting level.

### 7. Git review

1. Git behavior supports standard repositories and linked worktrees. Non-Git directories remain browsable with Git disabled; bare repositories are unsupported.
2. Git shows Staged (`HEAD` to index), Unstaged (index to working tree), and Untracked (full contents added) separately. Unborn repositories compare the index with Git's empty tree. Nested repositories are not combined.
3. fiew detects renames at 50% similarity but not copies.
4. Added, modified, deleted, renamed, type-changed, mode-only, binary, and submodule entries are visible.
5. Text changes use unified diffs with three context lines and old/new line numbers. Binary, mode-only, and submodule changes show metadata without textual hunks.
6. Zig and Markdown diffs may layer syntax styles beneath diff styling without delaying display.
7. `[ f`/`] f`, `[ h`/`] h`, and `[ c`/`] c` navigate files, hunks, and changed lines. `Enter` opens source context and `Ctrl-o` returns.
8. Git refreshes after debounced repository changes and through `Space g r`, retaining the previous complete snapshot until replacement succeeds.
9. fiew never uses hooks, pagers, prompts, external diff drivers, text converters, or mutating Git operations.

### 8. Review notes

1. A note attaches to a contiguous old-side or new-side textual diff selection.
2. Anchors include repository identity, Git group, path, side, line range, available blob IDs, and surrounding context.
3. Notes are stored as versioned Markdown (`fiew.review/v1`) in a gitignored `.reviews/` directory at the repository root so a coding agent can retrieve them, never elsewhere in the repository or in `.git`. Each line note embeds an anchored diff excerpt and, when a side blob exists, its blob ID, so the note can be reconciled to the reviewed content ([ARP-0006](<docs/decisions/ARP-0006.md>)).
4. Note states are Open, Resolved, and Outdated. Resolved notes can reopen; editing and deletion are explicit, and deletion requires confirmation.
5. A note follows an unchanged diff moved between Git groups only when exactly one anchor match exists. Missing or ambiguous matches become Outdated.
6. Commands are `Space r n` create, `Space r e` edit, `Space r x` resolve/reopen, `Space r d` delete, and `[ n`/`] n` navigate.
7. The Note Composer accepts multiline UTF-8 plain text. `Ctrl-Enter` saves; `Esc` cancels and confirms only when modified.
8. Threads, authors, reactions, attachments, synchronization, publishing, and repository-local note files are excluded.

### 9. Zig definition navigation

1. ZLS 0.16.x is optional, user-installed, resolved from `PATH`, and used only for Zig `textDocument/definition`.
2. fiew requires explicit repository trust before launch and explains that ZLS may evaluate repository-controlled Zig build logic. Build-on-save is disabled, but ZLS is not represented as sandboxed.
3. One lazy ZLS process serves each trusted repository with orderly initialization, balanced document open/close, cancellation, shutdown, and explicit restart.
4. UTF-8 and UTF-16 positions are supported.
5. A definition request shows pending status after 100 ms, times out after two seconds, and is bound to repository, snapshot, selection, and generation.
6. Stale or invalid responses do not change selection or history.
7. One valid result opens directly; multiple results open a transient preview picker.
8. Valid external `file:` targets may open read-only as External views.
9. Workspace edits, commands, formatting, rename, code actions, file operations, dynamic registration, and non-file URIs are rejected.
10. Without ZLS, `g d` performs no heuristic jump and reports the exact unavailable state while Tree-sitter navigation, text viewing, and history remain usable.

### 10. Mermaid preview

1. Only Markdown fences explicitly labeled `mermaid` are recognized.
2. Supported types are `graph`/`flowchart`, `sequenceDiagram`, and `erDiagram`.
3. Preview uses optional user-installed `mermaid-ascii` 1.5.x.
4. `Space m p` shows Unicode box drawing; `Space m a` shows strict ASCII.
5. Preview is transient; `q` or `Esc` returns to the exact source location without changing history.
6. Oversized output uses normal vertical and horizontal scrolling.
7. Renderer input is limited to 256 KiB, output to 2 MiB, and runtime to one second.
8. Captured output and stderr are bounded and sanitized before normal cell rendering.
9. Missing tools, unsupported types, timeout, crash, or invalid output preserve source and show an error.
10. Standalone Mermaid files, automatic rendering, full Mermaid compatibility, SVG, PNG, Kitty graphics, hyperlinks, and interaction are excluded.

### 11. Persistence and diagnostics

1. Global state uses schema-versioned JSON. Review notes use versioned Markdown files (`fiew.review/v1`) in the repository's gitignored `.reviews/` directory ([ARP-0006](<docs/decisions/ARP-0006.md>)).
2. Writes use same-directory temporary files, flush, atomic replacement, and one previous validated backup.
3. Unknown future schemas are not overwritten.
4. Diagnostic history is bounded. File logging is opt-in and redacts source, note bodies, environment values, and protocol payloads by default.
5. Recoverable failures disable only the affected capability and preserve the last valid snapshot.
6. Fatal terminal failures restore terminal state before reporting.

## Constraints and decisions

- Zig 0.16.0 on Apple Silicon macOS and Ghostty.
- Low-level libvaxis; no `vxfw`.
- Direct Tree-sitter C adapter with pinned Zig and Markdown grammars.
- Installed Git CLI; no libgit2.
- Optional trusted ZLS 0.16.x.
- Optional `mermaid-ascii` 1.5.x.
- Single-owner event-driven ports-and-adapters architecture.
- Pure fiew-owned ViewModel and RenderPlan pipeline.
- Zig standard library for JSON, JSON-RPC, subprocesses, queues, persistence, hashing, diagnostics, and tests.
- No SQLite, generic LSP framework, Node, Chromium, or application framework.

## Verification

- Pure command/reducer tests verify modal transitions, preview behavior, stale-event rejection, and disabled reasons.
- Fixed-dimension RenderPlan snapshots verify workspace, sidebar, status, code, diff, binary, and error views.
- Document tests verify UTF-8/grapheme mapping, invalid-byte behavior, reload generations, and byte-range stability.
- Fixture/transcript tests verify Git parsing, LSP framing/lifecycle, Tree-sitter mappings, Mermaid sanitization, and JSON recovery.
- Cancellation and leak tests verify Tree-sitter ownership, worker shutdown, ZLS cleanup, and subprocess limits.
- Fuzz/property tests cover UTF-8 mapping, Git/LSP framing, persisted-state decoding, and untrusted subprocess output.
- `zig build test` requires no network or optional executable. Installed-tool integration tests are opt-in.
- Manual Ghostty checks cover startup/restoration, keyboard protocol, mouse input, resize, and representative rendering.

## Out of scope

- Source editing or Git mutation.
- Linux, Windows, Intel macOS, or non-Ghostty terminals.
- General IDE functionality or project-wide content search.
- Multiple selections, key remapping, macros, tabs, or arbitrary splits.
- Additional grammars or language servers.
- Commit history, branch comparison, staging, committing, merge, or conflict workflows.
- Remote review systems or shared notes.
- Full-fidelity Mermaid graphics.
- Homebrew and other package managers.
- Guaranteed responsiveness above 10,000 tracked files.

## Open items

- Artifact naming, signing, notarization, and release automation.
- Replacement of the libvaxis commit pin when a compatible release exists.
- Empirical profiling of accepted parse and subprocess limits.

## References

- [Plan fiew v0.1](<.project/issues/ISSUE-0001-plan-fiew-v0-1.md>)
- [fiew v0.1 engineering baseline](<docs/engineering/fiew-v0-1-engineering-baseline.md>)
- [Adopt libvaxis’s low-level API for fiew v0.1](<docs/decisions/ARP-0001.md>)
- [Integrate Tree-sitter behind a direct C adapter](<docs/decisions/ARP-0002.md>)
- [Use trusted ZLS as an optional definition provider](<docs/decisions/ARP-0003.md>)
- [Render a Mermaid subset as terminal text](<docs/decisions/ARP-0004.md>)
- [Structure fiew as a single-owner event-driven application](<docs/decisions/ARP-0005.md>)
- [Store review notes as gitignored `.reviews/` Markdown for agent retrieval](<docs/decisions/ARP-0006.md>)
- [Tree-sitter integration constraints for fiew v0.1](<docs/research/tree-sitter-integration-constraints-for-fiew-v0-1.md>)
- [ZLS definition-navigation constraints for fiew v0.1](<docs/research/zls-definition-navigation-constraints-for-fiew-v0-1.md>)
- [Mermaid ASCII rendering constraints for fiew v0.1](<docs/research/mermaid-ascii-rendering-constraints-for-fiew-v0-1.md>)
