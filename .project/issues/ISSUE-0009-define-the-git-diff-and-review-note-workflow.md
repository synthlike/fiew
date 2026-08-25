---
id: ISSUE-0009
title: "Define the Git diff and review-note workflow"
kind: "clarification"
status: resolved
created: 2026-08-25
assignee: 
parent: "ISSUE-0001-plan-fiew-v0-1.md"
blocked_by:
  - "ISSUE-0003-define-the-v0-1-workflows-and-feature-boundary.md"
  - "ISSUE-0007-prototype-the-workspace-and-left-pane-interaction.md"
labels: []
---
# Define the Git diff and review-note workflow

## Question

What Git states, diff presentations, navigation actions, and review-note lifecycle belong in v0.1, and how should they interact with the left pane and code view?

## Comments
## Resolution

Accepted: v0.1 provides a read-only current-working-tree review workflow with local fiew-owned notes.

## Git scope

- Show Staged (`HEAD` to index), Unstaged (index to working tree), and Untracked (entire file added) groups separately. A file may appear in both Staged and Unstaged.
- In an unborn repository, compare the index against Git's empty tree.
- Support standard repositories and linked worktrees. Non-Git directories remain browsable with Git and Review contexts disabled. Bare repositories are unsupported.
- Nested repositories remain ordinary project entries; do not combine their Git states.
- Exclude commit history, arbitrary branch or revision comparisons, merge/conflict workflows, ignored files, and copy detection.
- Explicitly detect renames at 50% similarity. List added, modified, deleted, renamed, type-changed, mode-only, binary, and submodule entries. Binary, submodule, and mode-only entries show metadata but no textual diff.
- Never invoke hooks, external diff drivers, text converters, pagers, or mutating Git commands.

## Diff presentation and navigation

- Use a unified diff with three context lines, old/new line numbers, and color plus distinct gutter symbols for additions, deletions, and hunk headers.
- A command expands a hunk to show the full file. Side-by-side, word-level, moved-line, image, and binary diffs are deferred.
- For supported Zig and Markdown files within the parsing limit, layer old/new blob syntax styles beneath diff styles. Diff colors and gutter marks take precedence, and diff viewing never waits for parsing.
- `] f`/`[ f`, `] h`/`[ h`, and `] c`/`[ c` move among changed files, hunks, and changed lines. Navigation stays in the active Git-state group and requires a repeated command to wrap at a boundary.
- `Enter` opens the corresponding source context; `Ctrl-o` returns to the diff location.

## Refresh behavior

- Debounce repository and index filesystem notifications and refresh automatically; `Space g r` refreshes manually.
- Keep the previous complete snapshot visible during refresh. Preserve the selected file or hunk when possible.
- On failure, retain and mark the previous snapshot stale and report the error.
- Re-evaluate review-note anchors only after publishing a complete new snapshot.

## Review-note anchors and storage

- A note attaches to the current contiguous textual selection on the old or new side of a diff.
- Persist its Git-state group, repository-relative path, side, line range, available base/target blob IDs, surrounding-context fingerprint, plain-text body, and creation/update timestamps.
- Store notes outside the repository and `.git` under fiew's macOS user-data directory. Identify each repository with a generated ID associated with its canonical root path.
- If a repository moves or disappears, retain its notes as detached. Reassociation must be explicit; never infer identity from a remote URL.
- On refresh, relocate an anchor only for one exact context match. Search all three Git-state groups so notes follow unchanged diffs moved externally between Untracked, Unstaged, and Staged. Zero or multiple matches mark the note outdated.
- Repository-local files, sharing, synchronization, import/export, rich Markdown, and attachments are deferred.

## Review-note lifecycle and interaction

- Notes begin Open, can be explicitly Resolved and reopened, and become Outdated when no safe anchor exists. Editing and deletion require explicit actions; deletion requires confirmation.
- Do not provide replies, threads, reactions, authors, remote publication, or Git-integrated comments.
- `Space r n` creates a note on a textual diff selection; `Space r e`, `Space r x`, and `Space r d` edit, resolve/reopen, and delete the selected note. Creating a note elsewhere is disabled with a reason.
- `] n` and `[ n` move among notes in the current Git-state group. `Enter` in Review context previews the anchor. Anchored notes have a gutter symbol and status marker; outdated notes appear in a dedicated group and open with stored context.
- The transient Note Composer accepts multiline UTF-8 plain text. `Ctrl-Enter` saves; `Esc` cancels and confirms only when modified. This is fiew-owned text entry and does not enable source editing.
