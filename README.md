# fiew

`fiew` is a read-first terminal code and Git-diff viewer for agentic workflows, written in Zig.

The planned v0.1 targets Apple Silicon macOS and Ghostty. It focuses on:

- fast repository and file browsing;
- Helix/Kakoune-inspired modal navigation;
- unified Git diff review with local review notes;
- Zig and Markdown highlighting, structure, and folding;
- optional Zig definition navigation through ZLS; and
- terminal-text previews of supported Mermaid diagrams.

`fiew` does not modify source files or Git state. v0.1 is under development.

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

Use `j`/`k` to move through Project, `h`/`l` to collapse or expand directories, and `Enter` to pin a file preview. `Tab` changes focus, `b` toggles the sidebar, and `q` or `Ctrl-C` exits.

Run deterministic tests and formatting checks with:

```sh
zig build test
zig fmt --check src build.zig
```

## Project documentation

- [v0.1 specification](docs/specs/fiew-v0-1.md)
- [engineering baseline](docs/engineering/fiew-v0-1-engineering-baseline.md)
- [architecture decisions](docs/decisions/)
- [implementation issues](.project/issues/ISSUE-0013-implement-fiew-v0-1.md)

## License

MIT. See [LICENSE](LICENSE).
