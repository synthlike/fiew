---
id: ISSUE-0010
title: "Define the initial LSP navigation contract"
kind: "research"
status: resolved
created: 2026-08-25
assignee: 
parent: "ISSUE-0001-plan-fiew-v0-1.md"
blocked_by:
  - "ISSUE-0003-define-the-v0-1-workflows-and-feature-boundary.md"
  - "ISSUE-0005-establish-the-zig-and-terminal-ui-technical-baseline.md"
labels: []
---
# Define the initial LSP navigation contract

## Question

Which LSP lifecycle and navigation operations belong in the first version, and what fallback behavior is required when a server is absent, slow, or returns stale locations?

## Comments
## Resolution

Accepted based on [ZLS definition-navigation constraints for fiew v0.1](<docs/research/zls-definition-navigation-constraints-for-fiew-v0-1.md>). The consequential integration and trust boundary is recorded in [Use trusted ZLS as an optional definition provider](<docs/decisions/ARP-0003.md>).

## Scope and compatibility

- Support user-installed ZLS for Zig files only and only `textDocument/definition`. Resolve `zls` from `PATH`; do not download, bundle, or manage it.
- Require ZLS 0.16.x for Zig 0.16.0. Check `zls --version` only after repository trust is granted. Record 0.16.0 at commit `494486203c3a48927f2383aa3d5ce5fca112186d` as researched, while treating other 0.16 patches as policy-compatible but unverified.
- Defer Markdown servers, declaration, type definition, implementation, references, hover, completion, diagnostics, symbols, rename, formatting, code actions, workspace commands, and generic configurable server definitions.

## Trust and process lifecycle

- Require an explicit prompt before first ZLS launch for a canonical repository identity. Explain that ZLS may evaluate repository-controlled Zig build logic. Persist trust in fiew-owned user data.
- Disable build-on-save explicitly but do not describe ZLS as sandboxed. `:lsp-revoke-trust` stops ZLS and removes trust. External definition files never become trusted workspaces.
- Use at most one lazy ZLS process per repository. A trusted repository starts it when the first Zig file opens; an untrusted repository prompts only when `g d` requests LSP.
- Initialize with the repository root as the sole workspace folder. Complete `initialize` and `initialized` before any document notification or request.
- Balance `didOpen` and `didClose`. On external reload, cancel old requests, send `didClose`, then `didOpen` with the complete accepted snapshot and a monotonically increasing version.
- On normal exit, send `shutdown`, then `exit`, with bounded cleanup. A crash is reported and requires explicit `:lsp-restart`; never enter an automatic restart loop.
- Expose `:lsp-status` and `:lsp-restart`.

## Positions and requests

- Advertise UTF-8 then UTF-16 position encodings. Honor the server selection and default to UTF-16 when omitted. Convert only against the immutable request snapshot and reject invalid boundaries.
- `g d` sends a definition request for the active Zig selection. A newer request cancels an older one.
- Tie a request to repository, document version, selection, and generation. Discard mismatched responses. Show pending status after 100 ms, send `$/cancelRequest` and stop waiting after two seconds, and validate the target immediately before navigation.
- Timeout, cancellation, stale response, malformed result, and unavailable server leave selection and history unchanged.

## Definition results

- No result reports “definition not found.” One valid result opens it and pushes the current location to history. Multiple results open a transient preview picker and pin with `Enter`.
- Accept only valid `file:` URIs. Reject unsupported schemes, nonexistent paths, directories, and invalid ranges.
- Permit read-only files outside the repository, including the Zig standard library. Label them External and exclude them from Project and Git contexts.
- `Ctrl-o` returns through fiew's location history.

## Read-only enforcement and fallback

- Advertise no workspace edits, code actions, command execution, rename, formatting, file operations, dynamic registration, or `showDocument` support.
- Reply to unsolicited `workspace/applyEdit` with `applied: false` and a read-only reason. Reject other unsupported server requests appropriately, ignore telemetry, and never execute server-provided commands.
- Show concise server messages. Protocol logs are opt-in and redact document text by default.
- When ZLS is absent, untrusted, incompatible, starting, crashed, slow, or invalid, `g d` performs no heuristic jump and reports the exact state. Text viewing, Tree-sitter structural navigation, folding, and existing location history remain fully usable.
