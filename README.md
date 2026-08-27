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
| `Space b` | Open the Project sidebar |

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

### Planned

Visible in the command list with a disabled reason until implemented:

| Key | Action |
| --- | --- |
| `Space g` | Git sidebar |
| `Space r` | Review sidebar |
| `g d` | Go to definition |
| `Ctrl-Enter` / `Esc` | Save / discard a review note |

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
