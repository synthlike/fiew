<!-- agent-workflows-record
{"archived":false,"created":"2026-08-25T20:21:26Z","id":"fiew-v0-1-engineering-baseline","modified":"2026-08-31T11:56:00Z","record_type":"technical_baselines","title":"fiew v0.1 engineering baseline"}
-->
# fiew v0.1 engineering baseline

## Purpose and maturity

This baseline indexes the minimal production-compatible foundation for the approved review-first v0.1 workflows. The current repository contains a working Zig application and tests; remaining implementation is tracked by [Implement fiew v0.1](<.project/issues/ISSUE-0013-implement-fiew-v0-1.md>). Observable product behavior remains authoritative in [fiew v0.1](<docs/specs/fiew-v0-1.md>), and consequential integration and architecture choices remain authoritative in their ARPs.

## Fixed technology constraints

| Technology or platform | Supported version or boundary | Evidence |
| --- | --- | --- |
| Operating system and architecture | macOS on Apple Silicon only | [fiew v0.1](<docs/specs/fiew-v0-1.md>) |
| Terminal | Ghostty only | [Choose initial platform and terminal compatibility](<.project/issues/ISSUE-0004-choose-initial-platform-and-terminal-compatibility.md>) |
| Toolchain | Zig 0.16.0 exactly | Repository build files and verified local `zig version` |
| Terminal UI | Low-level libvaxis at immutable revision `c060d314930c5552b99a89278a6a695baf0352da` | [Adopt libvaxis’s low-level API for fiew v0.1](<docs/decisions/ARP-0001.md>) |
| Parsing | Tree-sitter 0.26.13 with the pinned Zig grammar | Repository `build.zig`, vendored sources, and [Integrate Tree-sitter behind a direct C adapter](<docs/decisions/ARP-0002.md>) |
| VCS | Installed Git CLI, surfaced as the only v0.1 VCS backend | [fiew v0.1](<docs/specs/fiew-v0-1.md>) |
| Local review | Private schema-versioned JSON under the repository-local `.reviews/` directory, with public command projections | [fiew v0.1](<docs/specs/fiew-v0-1.md>) |
| Bookmarks | Private schema-versioned JSON under the repository-local `.bookmarks/` directory | [fiew v0.1](<docs/specs/fiew-v0-1.md>) |
| Internal architecture | Single-owner event-driven ports and adapters | [Structure fiew as a single-owner event-driven application](<docs/decisions/ARP-0005.md>) |
| Repository scale | Up to 10,000 tracked files | [Choose initial platform and terminal compatibility](<.project/issues/ISSUE-0004-choose-initial-platform-and-terminal-compatibility.md>) |
| Distribution | Manually installed Apple Silicon binaries from GitHub Releases | [Choose initial platform and terminal compatibility](<.project/issues/ISSUE-0004-choose-initial-platform-and-terminal-compatibility.md>) |
| Product boundary | Immutable browsing, Git-backed VCS review, reviewer-agent threads, strict reviewer resolution, and private bookmarks | [fiew v0.1](<docs/specs/fiew-v0-1.md>) |

## Compatibility and prerequisites

- The development environment and repository build target Zig 0.16.0.
- The pinned libvaxis revision declares Zig 0.16.0 support; the low-level API remains the accepted terminal boundary.
- Development and release verification require Apple Silicon macOS and Ghostty.
- Git is required only for VCS and review workflows. Non-Git directories remain browsable with those capabilities disabled.
- Tree-sitter core and the selected Zig grammar use the accepted compatible ABI inputs.
- Markdown parsing, fuzzy file finding, ZLS, Linux, and additional terminals are not v0.1 prerequisites. They are planned under [Plan fiew v0.2](<.project/issues/ISSUE-0030-plan-fiew-v0-2.md>).
- `.reviews/` and `.bookmarks/` are the only repository-local write boundaries. fiew does not edit `.gitignore`; the user or invoking workflow must ensure both directories are ignored.
- Canonical reviews use `fiew.review/v1`; canonical bookmarks use `fiew.bookmark/v1`. Legacy Markdown reviews, unreleased bookmark data, and unknown future schemas are refused rather than migrated or overwritten.

## Approved conventions

### Repository and dependency boundaries

- Keep `model/`, `app/`, `view/`, `ports/`, and adapter-specific source boundaries, with `main.zig` as the composition root.
- Keep imports acyclic and prevent third-party types from entering core state.
- Resolve linked dependencies at accepted immutable revisions and commit Zig package integrity hashes. Do not float branches or version ranges.
- Use typed asynchronous effects for Git, filesystem, persistence, and other latency-bearing work; never run them on the terminal render/event path.
- The complete architecture and dependency boundary is [Structure fiew as a single-owner event-driven application](<docs/decisions/ARP-0005.md>).

### Toolchain and local development

- Require Zig 0.16.0 exactly for v0.1 development and release builds.
- Treat toolchain, linked-dependency, grammar, public review-schema, and external-protocol upgrades as explicit compatibility changes.

### Testing and verification

- Keep `zig build test --system zig-pkg` deterministic without network access or optional executables.
- Use pure model/reducer tests, fixed-size render-plan snapshots, fixture adapter contracts, ownership/leak tests, and fuzz/property checks.
- Keep real Git integration tests opt-in through `-Dgit-integration`.
- Maintain a manual Ghostty smoke checklist covering startup and restoration, keyboard input, resize, mouse input, all four sidebar contexts, representative source and diff rendering, threaded review, and bookmarks.
- Treat nested repository roots, command failure, concurrent Git change, review persistence failure, schema refusal, backup recovery, and role authority as required contract cases.

### Build and distribution

- Produce Apple Silicon macOS release artifacts with `-Doptimize=ReleaseSafe`.
- Publish manually installed binaries through GitHub Releases.
- Do not claim Markdown, Mermaid, fuzzy finding, ZLS, Linux, or non-Ghostty support in the v0.1 release artifact.

### Configuration, operations, and data

- Keep canonical reviews and bookmarks as private schema-versioned JSON in repository-local `.reviews/` and `.bookmarks/` directories.
- Expose review history to agents only through public `review show` projections. Permit agents to append replies only through `review reply`; retain reviewer authority over thread creation, lifecycle, deletion, and current-review selection.
- Use same-directory temporary files, flush, atomic replacement, future-version refusal, and one validated backup for durable state.
- Never clear dirty state or report approval after a persistence failure.
- Do not add telemetry, remote services, or secrets handling.
- Bound diagnostics and redact source contents, review comments, environment values, and protocol payloads by default.

### Supply chain

- Pin every linked Zig package with the package manager's integrity hash.
- Review every dependency revision intentionally; do not accept automated floating updates.
- Do not bundle or download Git or future optional tools at runtime.

## Recommendations awaiting approval

None.

## Open decisions

- Signing, notarization, package-manager distribution, and release automation.
- Replacing the libvaxis commit pin when a compatible tagged release exists.

## Deferred product questions

- Behavior above the 10,000-tracked-file guarantee remains outside v0.1.
- Markdown, fuzzy finding, expanded Zig navigation, Linux distribution compatibility, and additional terminal behavior are owned by [Plan fiew v0.2](<.project/issues/ISSUE-0030-plan-fiew-v0-2.md>).
- Go and TypeScript/React language behavior is owned by [Plan fiew v0.3](<.project/issues/ISSUE-0031-plan-fiew-v0-3.md>).
- GitHub pull-request review is owned by [Plan fiew v0.4](<.project/issues/ISSUE-0032-plan-fiew-v0-4.md>).

## Verification and operating commands

| Command | Status |
| --- | --- |
| `zig version` | Verified locally: `0.16.0` |
| `zig build` | Verified on the current workspace |
| `zig build test --system zig-pkg` with clean caches and Git absent from `PATH` | Verified; 136/144 passed with 8 expected opt-in skips |
| `zig build test --system zig-pkg -Dgit-integration --summary all` | Verified; 142/144 passed with 2 expected performance skips |
| `zig build test --system zig-pkg -Dgit-integration -Dperformance --summary all` | Verified; 144/144 passed |
| 10,000-file profile | Filesystem scan: 437 ms; clean Git snapshot: 189 ms on supported Apple Silicon macOS |
| Non-interactive review integration and mutation audit | Verified from a nested working directory; approval-sensitive exits, agent reply authority, malformed/dangling current pointers, and unchanged source/Git state passed |
| `zig fmt --check src build.zig` | Verified |
| `zig build -Doptimize=ReleaseSafe --system zig-pkg` | Verified as a Mach-O ARM64 executable |
| `python3 tools/package-release.py --version 0.1.0` from a clean checkout | Verified twice with identical SHA-256 output; archive contains one executable named `fiew` |
| Extracted archive inspection | Verified version and pinned dependency output, Mach-O ARM64 architecture, and only `/usr/lib/libSystem.B.dylib` as a dynamic dependency |
| Manual Ghostty smoke checklist | Passed all steps on 2026-08-28 with Ghostty 1.3.1 on Apple Silicon macOS 26.5.2; the extracted release archive also passed startup, Project, Review Diff, normal-quit restoration, and `Ctrl-C` restoration |

## References

- [fiew v0.1](<docs/specs/fiew-v0-1.md>)
- [Adopt libvaxis’s low-level API for fiew v0.1](<docs/decisions/ARP-0001.md>)
- [Integrate Tree-sitter behind a direct C adapter](<docs/decisions/ARP-0002.md>)
- [Structure fiew as a single-owner event-driven application](<docs/decisions/ARP-0005.md>)
- [Store review notes as gitignored `.reviews/` Markdown for agent retrieval](<docs/decisions/ARP-0006.md>)
- [Use reviewer-owned local threads with command-mediated agent replies](<docs/decisions/ARP-0007.md>)
- [Implement fiew v0.1](<.project/issues/ISSUE-0013-implement-fiew-v0-1.md>)
- [Choose initial platform and terminal compatibility](<.project/issues/ISSUE-0004-choose-initial-platform-and-terminal-compatibility.md>)
- [v0.1 release checklist](<docs/engineering/v0.1-release-checklist.md>)
