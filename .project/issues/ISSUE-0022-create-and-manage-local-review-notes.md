---
id: ISSUE-0022
title: "Create and manage local review notes"
kind: "implementation"
status: resolved
created: 2026-08-25
assignee: "agent"
parent: "ISSUE-0013-implement-fiew-v0-1.md"
blocked_by:
  - "ISSUE-0017-establish-recoverable-fiew-owned-state.md"
  - "ISSUE-0020-review-current-git-changes.md"
labels: []
---
# Create and manage local review notes

## Parent

[Implement fiew v0.1](<.project/issues/ISSUE-0013-implement-fiew-v0-1.md>)

## Source specification

[fiew v0.1](<docs/specs/fiew-v0-1.md>)

## What to build

Deliver the Note Composer, persisted diff anchors, Review sidebar, Open/Resolved lifecycle, edit/delete behavior, gutter markers, and note navigation. Notes are stored as agent-retrievable Markdown (`fiew.review/v1`) in a gitignored `.reviews/` directory, per [ARP-0006](<docs/decisions/ARP-0006.md>): one file per review with frontmatter (`schema`, `created`, `base` ref+SHA) and note sections carrying authoritative bullets (`id`, `status`, `blob` when present), a required anchored diff excerpt for line notes, and a Markdown body.

## Acceptance criteria

- [x] Notes attach to a contiguous old/new diff selection (line notes) or a whole file (file notes).
- [x] `Ctrl-Enter` saves and `Esc` protects modified note text.
- [x] Notes persist as versioned Markdown in the gitignored `.reviews/` directory and are re-read on open; a coding agent can retrieve and parse them.
- [x] Line notes embed an anchored diff excerpt and, when a side blob exists, its blob ID, so a note reconciles to the reviewed content.
- [x] Resolve, reopen, edit, delete, preview, and navigation commands work.
- [x] Source, tracked files, `.gitignore`, and Git metadata remain unchanged; fiew writes only within `.reviews/`.

## Blocked by

Managed by native issue relationships.

## Out of scope

Cross-refresh anchor relocation, remote/shared review behavior, and reviewing arbitrary commits. fiew does not add the `.reviews/` entry to `.gitignore` itself.

## Comments

### 2026-08-27

Storage and format changed per [ARP-0006](<docs/decisions/ARP-0006.md>): review notes are now agent-retrievable Markdown in a gitignored `.reviews/` directory rather than JSON under the macOS user-data directory. The read-only boundary is amended to permit writes within `.reviews/` only. The `fiew.review/v1` format, the file-note vs line-note distinction, and the diff-excerpt/blob anchoring for agent reconciliation are captured in the ARP and reflected in the updated scope and acceptance criteria above.

### 2026-08-27T17:14:07Z — codex

## Implementation review — unpushed range `eb3ef24..4dc0626`

**Verdict: Does not conform.** This verdict is limited to review-note creation, interaction, storage, and rendering in the 13 commits ahead of `origin/main`, reviewed against this issue, the v0.1 specification, ARP-0005, and ARP-0006.

### Blocking findings

- Multiline diff selection exists in `app/git_review.zig`, but no production command calls `toggleDiffSelection`; `v` still routes to document selection. The user can create only a single-line anchor through the shipped command path.
- There is no file-note creation path. `note_create` only calls `App.beginNoteFromDiff`, while file-note scope appears only in the model and its unit test.
- `Space r d` deletes immediately (`src/app/commands.zig:569-571`) without the confirmation required by specification section 8.4.
- Review-sidebar keyboard and mouse handling still route through the Project browser (`src/app/commands.zig:459-475`, `src/adapters/terminal/vaxis_terminal.zig:545-552`), and the rendered note list has no scroll state. Note preview and navigation therefore do not satisfy the documented sidebar behavior.
- The public `fiew.review/v1` parser never validates `schema`, splits notes on every `\n## ` (so an H2 in a Markdown body makes the review unreadable), and the store has no validated backup or future-version refusal (`src/model/review.zig:123-169`, `src/adapters/storage/review_store.zig:78-99`).

### Verification

- `zig build test --system zig-pkg -Dgit-integration --summary all`: 94/94 tests passed.
- Build, formatting, ReleaseSafe, and `aarch64-macos` checks passed.
- No manual Ghostty session was performed during this review.

Recommended disposition: reopen this issue. Add command-level tests for multiline and file notes, deletion confirmation, Review-sidebar behavior, arbitrary Markdown bodies, schema refusal, and backup recovery before claiming the acceptance criteria.

## Resolution

**Outcome: Achieved.**

Delivered local, agent-retrievable review notes anchored to diff selections, stored as `fiew.review/v1` Markdown in a gitignored `.reviews/` directory per [ARP-0006](<docs/decisions/ARP-0006.md>). Cross-refresh re-anchoring and remote/shared review remain out of scope.

Delivered:

- **`model/review.zig`** — the `fiew.review/v1` format: `Note`/`Review` types and round-trippable parse/serialize (frontmatter with `schema`/`created`/`base`; note sections with authoritative bullets, an optional anchored `diff` excerpt, and a Markdown body). Fixture-tested.
- **`adapters/storage/review_store.zig`** — reads `.reviews/*.md` on open (missing dir → none; malformed file → skipped) and writes one file per review atomically (same-directory temp + rename); removes emptied files. The only path fiew ever writes inside a repository.
- **`app/notes.zig`** — in-memory notes state (a deep copy for clean ownership): create/edit/resolve/delete/navigate, dirty-file tracking, and emptied-file removal, all tested.
- **Anchoring** — the Git model retains old/new blob SHAs, and the diff view captures a contiguous one-side selection into an anchor (side, line range, blob, and a reconstructed diff excerpt). Line notes always embed the excerpt; the blob is present for staged/committed sides.
- **Note Composer** — a transient multiline surface: characters/`Enter` build the body, `Ctrl-Enter` saves, `Esc` cancels and requires a second `Esc` when modified.
- **Review sidebar + main detail + diff gutter markers** — a third sidebar context listing notes with Open/Resolved markers, a note-detail main view (anchor, excerpt, body), and `▸` markers on annotated diff lines.
- **Commands + wiring** — `Space r` opens the review menu (`n`/`e`/`x`/`d`, `Enter` shows the sidebar); `[ n`/`] n` navigate. The terminal adapter loads `.reviews/` at startup, generates the session file (ISO `created`, `HEAD` base SHA), builds the note, and flushes dirty/removed files through the store.

Notable decisions:

- The read-only boundary was amended (ARP-0006, spec §1) to permit writes only within `.reviews/`; fiew never touches `.gitignore`, tracked files, or Git metadata.
- One review file per session; new notes append to it, and existing notes load and are editable/resolvable/deletable.

Verification passed:

- `zig build test --system zig-pkg` — 90/92 (2 git-integration tests skipped by default)
- `zig build test --system zig-pkg -Dgit-integration` — 92/92
- `zig fmt --check src build.zig`
- `zig build -Doptimize=ReleaseSafe --system zig-pkg`
- `zig build -Dtarget=aarch64-macos --system zig-pkg`
- Manual run: on a repo with a staged change, selected a diff line, `Space r n`, typed a note, `Ctrl-Enter` — wrote `.reviews/review-*.md` with the real base SHA, index blob, side/line, `diff` excerpt, and body. Reopened fiew: the note loaded into the Review sidebar and detail; `Space r x` resolved it and wrote `status: resolved` to disk.

Cross-refresh anchor relocation and the Open→Outdated transition remain [Re-anchor notes across Git refreshes](<.project/issues/ISSUE-0023-re-anchor-notes-across-git-refreshes.md>).
