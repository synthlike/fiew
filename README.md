# fiew

`fiew` is a read-first terminal code and Git-diff viewer for agentic workflows, written in Zig.

It focuses on:

- fast repository and file browsing;
- Helix/Kakoune-inspired modal navigation;
- unified Git diff review with local review notes;
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

### Review notes

Private, local review comments anchored to a diff selection, stored as Markdown
in a gitignored `.reviews/` directory so a coding agent can read them (see
[ARP-0006](docs/decisions/ARP-0006.md)). fiew writes only inside `.reviews/`.

For an agent-driven "review before commit" loop, run `fiew --review <name> <repo>`:
the session's notes go to `.reviews/<name>`, and fiew exits `1` when that file
has open notes (changes requested) or `0` when it has none (approved). The agent
picks the name, branches on the exit code, and reads `<repo>/.reviews/<name>`.

| Key | Action |
| --- | --- |
| `Space r n` | Create a note on the current diff selection |
| `Space r e` | Edit the selected note |
| `Space r x` | Resolve or reopen the selected note |
| `Space r d` | Delete the selected note |
| `Space r` `Enter` | Show the Review sidebar |
| `] n` / `[ n` | Next / previous note |
| `Ctrl-Enter` / `Esc` | In the composer: save / cancel (Esc confirms if modified) |

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
