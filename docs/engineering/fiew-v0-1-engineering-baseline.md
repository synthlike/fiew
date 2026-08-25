<!-- agent-workflows-record
{"archived":false,"created":"2026-08-25T20:21:26Z","id":"fiew-v0-1-engineering-baseline","modified":"2026-08-25T21:42:02Z","record_type":"technical_baselines","title":"fiew v0.1 engineering baseline"}
-->
# fiew v0.1 engineering baseline

## Purpose and maturity

This baseline indexes the minimal production-compatible foundation for the approved read-first v0.1 workflows. Accepted consequential integration and architecture choices remain authoritative in their ARPs.

## Fixed technology constraints

| Technology or platform | Supported version or boundary | Evidence |
| --- | --- | --- |
| Operating system and architecture | macOS on Apple Silicon only | [Choose initial platform and terminal compatibility](<.project/issues/ISSUE-0004-choose-initial-platform-and-terminal-compatibility.md>) |
| Terminal | Ghostty only | [Choose initial platform and terminal compatibility](<.project/issues/ISSUE-0004-choose-initial-platform-and-terminal-compatibility.md>) |
| Toolchain | Zig 0.16.0 exactly | User approval; verified by local `zig version` |
| Terminal UI | Low-level libvaxis at immutable revision `c060d314930c5552b99a89278a6a695baf0352da` | [Adopt libvaxis’s low-level API for fiew v0.1](<docs/decisions/ARP-0001.md>) |
| Parsing | Tree-sitter 0.26.13 with pinned Zig and Markdown grammars | [Integrate Tree-sitter behind a direct C adapter](<docs/decisions/ARP-0002.md>) |
| Semantic navigation | Optional trusted ZLS 0.16.x for Zig definition navigation | [Use trusted ZLS as an optional definition provider](<docs/decisions/ARP-0003.md>) |
| Mermaid preview | Optional `mermaid-ascii` 1.5.x terminal-text rendering | [Render a Mermaid subset as terminal text](<docs/decisions/ARP-0004.md>) |
| Internal architecture | Single-owner event-driven ports and adapters | [Structure fiew as a single-owner event-driven application](<docs/decisions/ARP-0005.md>) |
| Repository scale | Up to 10,000 tracked files | [Choose initial platform and terminal compatibility](<.project/issues/ISSUE-0004-choose-initial-platform-and-terminal-compatibility.md>) |
| Distribution | Manually installed Apple Silicon binaries from GitHub Releases | [Choose initial platform and terminal compatibility](<.project/issues/ISSUE-0004-choose-initial-platform-and-terminal-compatibility.md>) |
| Product boundary | Read-first browsing, diff review, and definition navigation | [Define the v0.1 workflows and feature boundary](<.project/issues/ISSUE-0003-define-the-v0-1-workflows-and-feature-boundary.md>) |

## Compatibility and prerequisites

- The local development environment has Zig 0.16.0 installed.
- The inspected libvaxis revision declares Zig 0.16.0 support; libvaxis v0.5.1 declares Zig 0.13.0 and is incompatible.
- Development and release verification require Apple Silicon macOS and Ghostty.
- Git is required only for Git workflows. ZLS and `mermaid-ascii` are optional and were not installed during research.
- Tree-sitter core and selected grammars use compatible ABI 15 inputs at their accepted revisions.
- No source tree or build definition exists yet, so project build, test, adapter, and performance commands remain unverified.

## Approved conventions

### Repository and dependency boundaries

- Start with a standard Zig executable using `build.zig`, `build.zig.zon`, and `src/`.
- Use `model/`, `app/`, `view/`, `ports/`, and adapter-specific source boundaries, with `main.zig` as the composition root.
- Keep imports acyclic and prevent third-party types from entering core state.
- Resolve linked dependencies at accepted immutable revisions and commit Zig package integrity hashes. Do not float branches or version ranges.
- The complete accepted architecture and dependency boundary is [Structure fiew as a single-owner event-driven application](<docs/decisions/ARP-0005.md>).

### Toolchain and local development

- Require Zig 0.16.0 exactly for v0.1 development and release builds.
- Treat toolchain, linked-dependency, grammar, and external-protocol upgrades as explicit compatibility changes.

### Testing and verification

- Keep `zig build test` deterministic without network access or optional executables.
- Use pure model/reducer tests, fixed-size render-plan snapshots, fixture/transcript adapter contracts, ownership/leak tests, and fuzz/property checks.
- Keep installed-tool integration tests opt-in.
- Maintain a documented manual Ghostty smoke check covering startup and restoration, keyboard input, resize, mouse input, and representative code and diff rendering.
- Intended stable verification commands are `zig build`, `zig build test`, and `zig fmt --check src build.zig`. They remain unverified until the project exists.

### Build and distribution

- Produce Apple Silicon macOS release artifacts with `-Doptimize=ReleaseSafe`.
- Publish manually installed binaries through GitHub Releases.

### Configuration, operations, and data

- Keep configuration, trust, and review-note state local and fiew-owned, outside repositories and Git metadata.
- Use schema-versioned JSON, atomic replacement, future-version refusal, and one validated backup as established by [Structure fiew as a single-owner event-driven application](<docs/decisions/ARP-0005.md>).
- Do not add telemetry, remote services, or secrets handling.
- Diagnostics are bounded and redact source contents, review-note bodies, environment values, and protocol payloads by default.

### Supply chain

- Pin every linked Zig package with the package manager's integrity hash.
- Review every dependency revision intentionally; do not accept automated floating updates.
- Do not bundle or download Git, ZLS, or `mermaid-ascii` at runtime.

## Recommendations awaiting approval

None.

## Open decisions

- Artifact naming, signing, notarization, and release automation.
- Replacing the libvaxis commit pin when a Zig-0.16-compatible tagged release exists.

## Deferred product questions

- Behavior above the 10,000-tracked-file guarantee remains outside v0.1.
- Additional parsers, LSP features, Git comparisons, note synchronization, and full Mermaid rendering require later product evidence and decisions.

## Verification and operating commands

| Command | Status |
| --- | --- |
| `zig version` | Verified locally: `0.16.0` |
| `zig build` | Unverified: no `build.zig` exists |
| `zig build test` | Unverified: no project exists |
| `zig fmt --check src build.zig` | Unverified: no project exists |
| `zls --version` | Unavailable locally during research |
| `mermaid-ascii --version` | Unavailable locally during research |

## References

- [Adopt libvaxis’s low-level API for fiew v0.1](<docs/decisions/ARP-0001.md>)
- [Integrate Tree-sitter behind a direct C adapter](<docs/decisions/ARP-0002.md>)
- [Use trusted ZLS as an optional definition provider](<docs/decisions/ARP-0003.md>)
- [Render a Mermaid subset as terminal text](<docs/decisions/ARP-0004.md>)
- [Structure fiew as a single-owner event-driven application](<docs/decisions/ARP-0005.md>)
- [Define the v0.1 workflows and feature boundary](<.project/issues/ISSUE-0003-define-the-v0-1-workflows-and-feature-boundary.md>)
- [Choose initial platform and terminal compatibility](<.project/issues/ISSUE-0004-choose-initial-platform-and-terminal-compatibility.md>)
- [Zig 0.16.0 Apple Silicon macOS distribution](https://ziglang.org/download/0.16.0/zig-aarch64-macos-0.16.0.tar.xz)
