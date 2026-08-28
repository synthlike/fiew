# fiew

`fiew` is a read-first terminal code and Git-diff viewer for agentic workflows, written in Zig.

It focuses on:

- fast repository and file browsing;
- Helix/Kakoune-inspired modal navigation;
- unified Git diff review with reviewer-owned local threads;
- Zig and Markdown highlighting, structure, and folding;
- optional Zig definition navigation through ZLS; and
- terminal-text previews of supported Mermaid diagrams.

Currently `fiew` is not able to not modify source files or Git state. 
The planned v0.1 targets Apple Silicon macOS and Ghostty and is under development.

## Development

Install Zig 0.16.0, then fetch dependencies and build:

```sh
zig build --fetch
zig build
```

Browse the current directory in Ghostty with `zig build run`, or pass another directory after `--`:

```sh
zig build run -- /path/to/repository
```

Run deterministic tests and formatting checks with:

```sh
zig build test
zig fmt --check src build.zig
```

## Keybindings

`fiew` is modal and selection-first. These are the current bindings; the same
command registry generates the in-app help (`Space ?`) and named-command search
(`:`), so they always match the build.

### Global

| Key | Action |
| --- | --- |
| `Space` | Leader menu |
| `Space f` | File commands |
| `Space ?` | Key help |
| `:` | Search named commands |
| `Tab` / `Shift-Tab` | Focus next / previous region |
| `Esc` | Cancel pending input, or restore the last pinned view |
| `q` | Close a transient view |
| `Space q` / `:quit` | Quit |
| `Ctrl-C` | Interrupt / quit |

### Project sidebar

| Key | Action |
| --- | --- |
| `j` / `k` | Next / previous item |
| `h` / `l` | Collapse / expand (or move to parent / child) |
| `Enter` | Toggle directory |
| `Space p` | Open or collapse the Project sidebar |

### Document movement (main view)

| Key | Action |
| --- | --- |
| `h` `j` `k` `l` | Left / down / up / right |
| `w` / `b` / `e` | Next word / previous word / word end |
| `g g` / `g e` | Document start / end |
| `Ctrl-u` / `Ctrl-d` | Half page up / down |
| `PageUp` / `PageDown` | Page up / down |
| `Enter` | Pin the preview and focus the main view |
| `Ctrl-o` / `Ctrl-i` | Back / forward through location history |

### Selection

| Key | Action |
| --- | --- |
| `v` | Toggle Extend mode |
| `x` | Select line |
| `;` | Collapse to the active end |
| `Alt-;` | Reverse the selection ends |

### Folding

| Key | Action |
| --- | --- |
| `z c` / `z o` / `z a` | Close / open / toggle the fold at the cursor |
| `z M` / `z R` | Close all / open all folds |

### Structural navigation

| Key | Action |
| --- | --- |
| `Alt-o` | Select the enclosing node |
| `Alt-i` | Select the first child node |
| `Alt-n` / `Alt-p` | Select the next / previous sibling node |

### Git review

Read-only review of the current working tree — Staged, Unstaged, and Untracked
changes with unified diffs. It never modifies the repository.

| Key | Action |
| --- | --- |
| `Space v` | Open the VCS context (Git) |
| `Space v r` | Refresh the current Git snapshot |
| `Space p` | Return to the Project sidebar |
| `j` / `k` | Select the next / previous change |
| `Enter` | Focus the diff; on a diff line, open the source in context |
| `Ctrl-o` | Return from the source view to the diff |
| `] f` / `[ f` | Next / previous changed file |
| `] h` / `[ h` | Next / previous hunk |
| `] c` / `[ c` | Next / previous changed line |

### Review threads

Reviewer-owned file or diff threads contain ordered, append-only reviewer and
agent comments. Canonical reviews are private `fiew.review/v1` JSON under
`.reviews/`; `review show` projects them as public JSON or Markdown. Only the
reviewer creates, resolves, reopens, or deletes a complete thread; deletion
requires confirmation. Open and Outdated threads block approval.

Earlier Markdown and pre-context review files are intentionally unsupported;
unknown future schemas are refused rather than overwritten. A malformed primary
recovers from one validated backup. Exact raw-byte anchors validate their stored
location first, then relocate only on one match within the same or Git-renamed
path. Outdated validity remains independent from reviewer resolution. fiew does
not manage ignore rules.

The reviewer and agent interface is:

```sh
fiew review start [--name <slug>] [--repo <path>]
fiew review open [<review-id>] [--repo <path>]
fiew review show [<review-id>] [--format json|markdown] [--repo <path>]
fiew review reply [<review-id>] <thread-id> --body-file <path> [--repo <path>]
```

Repository selection defaults to the current directory. New IDs include a
datetime prefix and automatic name; `.json` is never part of the command-line ID.
`start` and reviewer `open <review-id>` select one current review per repository,
so routine `open`, `show`, and `reply <thread-id>` need no exchanged ID. Explicit
IDs still access history. `show` emits complete JSON by default, and `reply` can
only append one `agent` comment. Review commands return zero only when every thread is durably resolved;
Open, Outdated, malformed, or unsaved state is non-success. The legacy
`--review` flag is not supported.

| Key | Action |
| --- | --- |
| `Space r n` | Create a thread from the current one-side diff selection |
| `Space r f` | Create a thread for the selected changed file |
| `Space r a` | Append a reviewer comment to the selected thread |
| `Space r x` | Resolve or reopen the selected thread |
| `Space r d` | Request deletion of the selected complete thread |
| `Space r` `Enter` | Show the Review sidebar |
| `] n` / `[ n` | Next / previous thread |
| `Ctrl-Enter` / `Esc` | In the composer: save / cancel (Esc confirms if modified) |

### Private bookmarks

Bookmarks save source locations in repository-local, schema-versioned private
state at `.bookmarks/bookmarks.json`. They do not appear in `.reviews/`,
`review show`, or any other agent-facing output. fiew does not manage ignore rules.
Creating from a diff maps to the corresponding current source location. Labels
are optional and limited to 48 UTF-8 bytes. Exact context is checked after Git
refresh and before opening; missing or ambiguous entries are shown as Outdated.

| Key | Action |
| --- | --- |
| `Space b Enter` | Show the Bookmarks sidebar |
| `Space b n` | Create a bookmark with an optional label |
| `Space b d` | Delete the selected bookmark with confirmation |
| `] b` / `[ b` | Next / previous bookmark |

### Planned

Visible in the command list with a disabled reason until implemented:

| Key | Action |
| --- | --- |
| `g d` | Go to definition |

## Language support

Syntax highlighting, folding, and structural navigation are powered by
Tree-sitter and require a supported language in the focused main view. Every
other file remains fully navigable as plain text.

| Language | Highlighting | Folding | Structural navigation |
| --- | --- | --- | --- |
| Zig | ✅ | ✅ | ✅ |
| Markdown | Planned | Planned | Planned |

## Project documentation

- [v0.1 specification](docs/specs/fiew-v0-1.md)
- [engineering baseline](docs/engineering/fiew-v0-1-engineering-baseline.md)
- [architecture decisions](docs/decisions/)
- [implementation issues](.project/issues/ISSUE-0013-implement-fiew-v0-1.md)

## License

MIT. See [LICENSE](LICENSE).
