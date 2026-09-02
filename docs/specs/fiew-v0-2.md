<!-- agent-workflows-record
{"archived":false,"created":"2026-08-28T15:46:11Z","id":"fiew-v0-2","modified":"2026-09-02T22:24:38Z","record_type":"specs","title":"Skaut v0.2"}
-->
# Skaut v0.2

## Problem

fiew v0.1 gives reviewers a safe read-first workspace for repository browsing and current-change review, but it leaves common supporting context expensive to inspect. Markdown remains plain text, large project trees require manual traversal, Zig navigation is structural rather than semantic, and the distributed binary supports only Apple Silicon macOS in Ghostty.

Reviewers need richer read-only navigation without turning Skaut into a source editor, general IDE or platform-specific terminal application. They also need a fast way to preserve an ordered reading path without manually copying source locations into an external note application.

## Desired behavior

A reviewer on Apple Silicon macOS or x86_64 Linux can retain every v0.1 review workflow while fuzzy-finding repository files, reading structured Markdown, using an optional trusted ZLS process for Zig definitions, references, and hover information, and manually preserving ordered review-local Trails. Core behavior remains useful when parsers or optional executables are absent or fail. Ghostty, Kitty, and WezTerm provide the required terminal compatibility matrix.

Unless this specification explicitly supersedes a v0.1 requirement, Skaut v0.2 retains the observable workflow of the historical fiew v0.1 specification. The Skaut product identity, command names, global paths, and private schema identifiers supersede their fiew v0.1 counterparts without compatibility behavior.

## Requirements

### 1. Read-only and compatibility boundary

1. Skaut must retain the v0.1 prohibition on source, tracked-file, `.gitignore`, Git metadata, index, branch, commit, and other Git mutation.
2. Markdown, fuzzy finding, ZLS, and Trails must not modify source or Git state.
3. Skaut must refuse language-server workspace edits, formatting, rename, code actions, file operations, server commands, and other source-writing requests.
4. Failures, cancellation, malformed external output, unavailable global persistence, and stale asynchronous work must preserve the read-only boundary and the last valid view.
5. v0.2 must use the canonical `skaut.review/v1` and `skaut.bookmark/v1` contracts and preserve the reviewer/agent authority boundary unless separately superseded by an accepted specification. The repository-local write boundary adds `.trails/` only for private Trail artifacts; Trail persistence must not alter Review or Bookmark contracts or appear in agent review projections.

### 2. Supported platforms and terminals

1. v0.2 must release for Apple Silicon macOS and x86_64 Linux.
2. The x86_64 Linux release artifact must be a baseline-CPU, statically linked musl executable named `skaut` inside `skaut-v0.2.0-linux-x86_64.tar.gz`, accompanied by a matching `.sha256` file.
3. Ubuntu 22.04 with Linux 5.15 or later is the verified Linux compatibility floor. Other x86_64 Linux distributions meeting that kernel floor are best-effort unless explicitly tested.
4. v0.2 must remain buildable from source for ARM64 Linux with Zig 0.16.0 and the locked dependencies. ARM64 Linux has no required archive, runtime guarantee, or terminal smoke-test gate.
5. Ghostty, Kitty, and WezTerm must pass the required behavioral smoke suite on the supported operating-system targets. Other xterm-compatible terminals are best-effort.
6. Windows, Intel macOS, package-manager distribution, signing, notarization, and automatic updates are not v0.2 requirements.

### 3. Portable operating-system behavior

1. Global state must use `$HOME/Library/Application Support/skaut` on macOS.
2. Global state must use `$XDG_STATE_HOME/skaut` on Linux, falling back to `$HOME/.local/state/skaut` when `XDG_STATE_HOME` is unset or empty.
3. Reviews must remain repository-local under `.reviews/`; private Trails must remain repository-local under `.trails/`; bookmarks must remain repository-local under `.bookmarks/`.
4. If no valid global state directory is available, Skaut must continue with repository browsing and review behavior, report a diagnostic, and disable capabilities that require persisted global state rather than inventing another location.
5. v0.2 must not depend on FSEvents, inotify, polling, or terminal-focus events. Git refresh remains explicit. Source changes are detected when opening or explicitly reloading a document.
6. A reload must retain the immutable current snapshot until a complete replacement succeeds. Deleted, replaced, or unreadable files must be reported without crashing.
7. Skaut must restore terminal state on normal exit and handled `SIGINT` and `SIGTERM`. Forced termination such as `SIGKILL` is outside the recoverable contract.
8. Git and ZLS subprocesses must launch directly without a shell and must be bounded, cancellable, terminated, and reaped. ZLS must stop during shutdown or trust revocation.
9. Shell job control, background operation, and `Ctrl-Z` suspend/resume guarantees are excluded.
10. Skaut must not use native clipboard APIs, clipboard helper executables, or OSC 52. Users copy through terminal selection.

### 4. Terminal capability fallback

1. Skaut must use libvaxis runtime capability detection instead of terminal-name branches.
2. It must prefer the Kitty keyboard protocol and synchronized output when available and fall back to conventional VT keyboard input and unsynchronized drawing.
3. Every core workflow must remain keyboard-accessible. Mouse input is an optional enhancement.
4. Rendering must fall back to the available terminal color model.
5. The normal interface may use Unicode.
6. The existing unsupported-size behavior remains in force.
7. v0.2 must not add graphics-protocol, multiplexer, or terminal-specific application paths.

### 5. Fuzzy project file finding

1. Skaut must provide a transient command-registry action that finds repository files by typed path query without expanding into project-wide content search.
2. Matching must use subsequence matching and favor path-component boundaries and contiguous runs.
3. Results must remain bounded and the matcher must remain responsive at the supported 10,000-file repository target.
4. The result surface must show the current query, ordered matching paths, and an explicit empty state.
5. Keyboard movement changes the selected result and its preview without changing location history.
6. `Enter` must open and pin the selected file, focus the main view, and add one origin entry to location history.
7. `Esc` must dismiss the finder and restore the prior pinned view, selection, and history.
8. Fuzzy finding must not support source-content search, regular expressions, multi-select, or source and Git mutation.

### 6. Markdown structure

1. Markdown documents must receive Tree-sitter block and inline parsing, viewport highlighting, section folding, fenced-block folding, and structural navigation while remaining immutable.
2. Explicitly labeled `zig` fences must receive one level of Zig syntax injection. Other grammar injections and nested injection beyond one level are excluded.
3. Markdown section and fence folds must come from Skaut-owned Tree-sitter queries rather than indentation heuristics.
4. Block/inline included ranges and byte mappings must remain correct for valid representative Markdown.
5. Malformed, unsupported, oversized, invalid-UTF-8, cancelled, or failed Markdown parsing must leave the complete document navigable as plain text.
6. Markdown parsing must retain the existing 2 MiB structural-processing limit, asynchronous cancellation, stale-result rejection, and immutable parse-snapshot boundary.
7. Markdown presentation is assistance and must not be treated as correctness-critical interpretation of document meaning.

### 7. Trusted Zig navigation through ZLS

1. Skaut must support a user-installed ZLS 0.16.x executable for Zig 0.16.0. ZLS is Zig-specific, optional, read-only, and resolved from `PATH`; Skaut must not download or bundle it or expose a generic language-server configuration framework.
2. Skaut must require explicit persisted trust for the canonical repository identity before launching ZLS and must explain that ZLS may evaluate repository-controlled Zig build logic. Trust revocation must stop ZLS and remove persisted trust.
3. Skaut must run at most one lazy ZLS process per open repository, initialize it with that repository as the sole workspace, balance document open/close notifications, and provide status, explicit restart, orderly shutdown, and bounded crash handling without automatic restart loops.
4. Skaut must negotiate UTF-8 or UTF-16 positions, convert only against the immutable request snapshot, and bind every request to repository, document version, selection, operation, and generation identities.
5. Only validated `file:` locations may become navigation targets. Nonexistent paths, directories, unsupported schemes, invalid ranges, and invalid position boundaries must be rejected.
6. Valid files outside the repository, including Zig standard-library files, may open read-only and must be labeled **External**. They must not become Project or Git workspace members.
7. Missing, untrusted, incompatible, starting, crashed, slow, malformed, stale, and invalid ZLS behavior must leave text viewing, Tree-sitter structure, selection, and location history usable.

### 8. Definitions and references

1. `g d` must request the definition for the active Zig selection. One valid result opens immediately; multiple valid results open a transient result list.
2. `g r` must request references and open the transient result list. Results must be grouped by file and ordered by repository path then source position. A declaration appears only when ZLS returns it.
3. Result rows must show path, one-based line, source preview, and an **External** label where applicable.
4. `j`/`k` and arrow movement must update only the transient preview and must not add history.
5. `Enter` must close the list, pin the selected location, and add exactly one origin entry. `Esc` must close or cancel without changing the pinned view or history.
6. `Ctrl-o` and `Ctrl-i` must navigate backward and forward after a pinned semantic jump.
7. Invalid results must be omitted. If no valid results remain, Skaut must report that no valid definition or references were returned.
8. At most 5,000 results may be displayed. Truncation must be explicit.
9. Skaut must never substitute heuristic definition or reference navigation.

### 9. Hover information

1. `K` must request hover documentation and type information for the active Zig selection.
2. Hover must appear as sanitized terminal text in a bounded, scrollable overlay without changing selection or location history.
3. Supported Markdown presentation may be rendered; unsupported markup must remain readable as plain text.
4. `j`/`k` must scroll long hover content. `Esc` or `q` must dismiss it.
5. A new hover replaces the previous hover. Document navigation or snapshot replacement dismisses visible hover information.
6. No result must report that hover information is unavailable without impairing other navigation.

### 10. ZLS request state and failure behavior

1. A semantic request must show non-blocking pending status after 100 milliseconds.
2. `Esc` must request cancellation. A newer request or changed document must cancel the older request.
3. Definition and hover requests must time out after two seconds. Reference requests must time out after five seconds.
4. Late, stale, malformed, mismatched, cancelled, timed-out, and invalid responses must never navigate or replace visible information.
5. Skaut must report concise exact states including untrusted, not installed, incompatible, starting, timed out, crashed, and discarded because the document changed.
6. Every failure must preserve selection, pinned view, location history, Markdown/Tree-sitter behavior, and plain-text fallback.
7. Skaut must advertise only implemented capabilities and defensively refuse all unsolicited source-writing or command-execution requests.

### 11. Review-local Trails

1. Trails must be available only when an active named review exists. A Trail is a reviewer-curated ordered reading path, not an inferred execution flow or call graph.
2. `Space t` must open the Trails surface. `Space t r` must toggle recording, and starting must record the current valid repository source location as the first point.
3. `Space t a` must manually append the current valid repository source location. External, binary, metadata-only, and otherwise invalid locations must be refused without stopping recording.
4. Each point must preserve its order, repository path, one-based line, trimmed captured line content, and conservative contextual anchor.
5. A Trail must contain at least two points. Attempting to stop earlier must keep recording active and report an exact reason.
6. Stopping must open a composer for a required bounded title and an optional bounded multiline note. Cancelling the composer must resume recording with every point intact; saving must persist the completed Trail.
7. Each saved Trail must use one private schema-versioned `skaut.trail/v1` JSON artifact under `.trails/`, with an opaque stable Trail identity and explicit immutable ownership by the active review. Adapter-controlled filenames are not relationship identity. Trail artifacts must not alter `skaut.review/v1`, `skaut.bookmark/v1`, or agent review projections.
8. Saved Trails must be listed for the active review. Opening one must expose its ordered points; `j`/`k` must change preview without changing history, and `Enter` must pin the selected point and add exactly one navigation entry.
9. `Space t d` must delete the selected saved Trail only after confirmation.
10. Re-anchoring must follow the conservative bookmark boundary. A uniquely matched point may update; an unresolved point must become **Outdated** while preserving its originally captured path, line, and content.
11. Recording and composition drafts must remain memory-only. Quit must warn while either is unfinished.
12. Missing storage, malformed or future schema, stale anchors, deleted files, persistence failure, and invalid points must preserve source viewing and existing review state. A malformed or future individual Trail must not disable unrelated valid Trails.
13. Automatic ZLS capture, External points, one-point Trails, metadata editing, point reordering or deletion, and printing Trails into comments are excluded from v0.2.

### 12. Release and installation

1. Linux installation instructions must verify the SHA-256 checksum, extract the archive, and install `skaut` at `$HOME/.local/bin/skaut` without root access.
2. The Linux release gate must run deterministic tests on Ubuntu 22.04 x86_64, verify exact `skaut --version` output, inspect x86_64 ELF architecture and static linkage, extract and execute the archive from a clean temporary directory, and verify its checksum.
3. CI must compile `aarch64-linux-musl` with the locked Zig 0.16.0 dependencies as a non-gating runtime target.
4. Required manual terminal checks must cover startup and restoration, keyboard input, mouse fallback, resize, Unicode and color fallback, Markdown, fuzzy finding, and Zig semantic navigation where optional tools are installed.

## Constraints and decisions

- Zig 0.16.0 and the locked dependency set remain the build baseline.
- Continue the low-level libvaxis, direct Tree-sitter C adapter, single-owner event-driven architecture, immutable document snapshots, typed asynchronous effects, ports-and-adapters boundaries, pure render-plan seam, and read-only Git CLI adapter.
- Keep pinned Tree-sitter core, Zig grammar, and Markdown grammar revisions behind Skaut-owned immutable syntax values.
- ZLS 0.16.x is an optional user-installed runtime tool.
- No generic LSP library or framework, libgit2, SQLite, Node, Chromium, application framework, or terminal-specific graphics dependency is admitted.
- The explicit no-watcher v0.2 requirement supersedes the v0.1 requirement that a debounced filesystem change refresh Review Diff. Manual Review Diff refresh remains required.

## Verification

- Pure matcher tests must cover subsequence ordering, path boundaries, contiguous runs, empty queries/results, deterministic ties, bounded output, and the 10,000-file target.
- Tree-sitter adapter fixtures must cover Markdown block/inline included ranges, highlights, section and fence folds, one-level Zig injection, malformed input, cancellation, ABI/query failure, and plain-text fallback.
- ZLS transcript tests must cover trust and revocation, version validation, initialize/open/close/shutdown order, UTF-8/UTF-16 mapping, definition/reference/hover variants, External targets, cancellation, timeout, crash, malformed messages, stale generations, result bounds, and read-only request refusal without requiring ZLS.
- Pure reducer and command tests must verify finder, result-list, hover, pending, cancellation, preview, pin, dismissal, history, disabled-reason, capability-fallback, and Trail start/add/stop/composer/save/cancel transitions.
- Trail tests must verify active-review and valid-location guards, minimum point count, one-file-per-Trail `skaut.trail/v1` serialization, opaque identity, immutable Review ownership, artifact isolation, future-schema refusal, backup recovery, conservative re-anchoring, Outdated preservation, list/open/preview/pin/delete behavior, unfinished quit warning, and unchanged agent review projections.
- Fixed-dimension ViewModel and RenderPlan snapshots must verify fuzzy finder, Markdown, definition/reference lists, hover, Trails, External labels, exact failure states, terminal fallback, and unsupported-size behavior.
- `zig build test` must remain deterministic, offline, and independent of Git and ZLS. External-tool integration tests remain opt-in.
- Linux CI must verify native deterministic tests, release ELF properties, clean archive execution, checksum behavior, and non-gating ARM64 compilation.
- Manual smoke evidence must cover Ghostty, Kitty, and WezTerm on the required operating-system targets and record unavailable optional-tool behavior separately from successful integration behavior.

## Out of scope

- Source editing, formatting, rename, code actions, completion, workspace edits, server commands, or Git mutation.
- Go, JavaScript, JSX, TypeScript, TSX, React, additional grammars, arbitrary language servers, or generic language capability infrastructure.
- Project-wide content search, regular expressions, fuzzy multi-select, or replace.
- Mermaid-specific recognition, rendering, preview commands, runtime integrations, and compatibility claims. Mermaid fences remain ordinary Markdown source.
- Automatic filesystem watching, clipboard integration, shell job control, guaranteed suspend/resume, multiplexers, and terminal-specific branches.
- Windows, Intel macOS, ARM64 Linux release artifacts or runtime guarantees, package managers, signing, notarization, and automatic updates.
- GitHub or other remote review providers, generic VCS abstraction, commit history, branch comparison, staging, committing, merging, and conflict workflows.
- Tabs, arbitrary splits, multiple selections, key remapping, and macros.
- Automatic Trail capture, Trail points outside the repository, global Trails without an active review, Trail metadata editing, point reordering or deletion, and printing Trails into review comments.

## Open items

- The exact command binding for opening the fuzzy finder may be assigned through the existing command registry during implementation planning; it must appear in generated help and named-command search.
- Empirical profiling may lower limits or improve timeouts only through a later accepted specification change; it must not silently weaken the stated v0.2 contract.

## References

- [fiew v0.1](<docs/specs/fiew-v0-1.md>)
- [Plan fiew v0.2](<.project/issues/ISSUE-0030-plan-fiew-v0-2.md>)
- [Research the v0.2 Linux binary portability boundary](<.project/issues/ISSUE-0036-research-the-v0-2-linux-binary-portability-boundary.md>)
- [Choose the v0.2 Linux artifact contract](<.project/issues/ISSUE-0037-choose-the-v0-2-linux-artifact-contract.md>)
- [Define portable terminal and operating-system behavior](<.project/issues/ISSUE-0038-define-portable-terminal-and-operating-system-behavior.md>)
- [Specify expanded Zig navigation interaction](<.project/issues/ISSUE-0039-specify-expanded-zig-navigation-interaction.md>)
- [Integrate Tree-sitter behind a direct C adapter](<docs/decisions/ARP-0002.md>)
- [Use trusted ZLS as an optional definition provider](<docs/decisions/ARP-0003.md>)
- [Keep Mermaid rendering outside fiew](<docs/decisions/ARP-0012.md>)
- [Structure fiew as a single-owner event-driven application](<docs/decisions/ARP-0005.md>)
- [Linux binary portability boundary for fiew v0.2](<docs/research/linux-binary-portability-boundary-for-fiew-v0-2.md>)
- [Terminal compatibility boundary for fiew v0.2](<docs/research/terminal-compatibility-boundary-for-fiew-v0-2.md>)
- [Trails for review-local reading paths](<docs/product/trails-for-review-local-reading-paths.md>)
- [Store containers, Trails, and Spots as independent repository artifacts](<docs/decisions/ARP-0014.md>)
- [Adopt Skaut as the complete product identity](<docs/decisions/ARP-0015.md>)
