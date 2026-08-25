# fiew

`fiew` is a read-first terminal code and Git-diff viewer for agentic workflows, written in Zig.

The planned v0.1 targets Apple Silicon macOS and Ghostty. It focuses on:

- fast repository and file browsing;
- Helix/Kakoune-inspired modal navigation;
- unified Git diff review with local review notes;
- Zig and Markdown highlighting, structure, and folding;
- optional Zig definition navigation through ZLS; and
- terminal-text previews of supported Mermaid diagrams.

`fiew` does not modify source files or Git state. v0.1 planning is complete; implementation has not started.

## Project documentation

- [v0.1 specification](docs/specs/fiew-v0-1.md)
- [engineering baseline](docs/engineering/fiew-v0-1-engineering-baseline.md)
- [architecture decisions](docs/decisions/)
- [implementation issues](.project/issues/ISSUE-0013-implement-fiew-v0-1.md)

## License

MIT. See [LICENSE](LICENSE).
