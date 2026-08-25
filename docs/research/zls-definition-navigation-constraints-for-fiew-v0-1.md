<!-- agent-workflows-record
{"archived":false,"created":"2026-08-25T21:11:37Z","id":"zls-definition-navigation-constraints-for-fiew-v0-1","modified":"2026-08-25T21:11:37Z","record_type":"research","title":"ZLS definition-navigation constraints for fiew v0.1"}
-->
# ZLS definition-navigation constraints for fiew v0.1

## Question

Which ZLS and Language Server Protocol boundary can provide safe, responsive go-to-definition navigation for a read-only Zig viewer?

This research informs ISSUE-0010.

## Verified findings

- The official ZLS installation guidance says tagged Zig and ZLS releases should use the same minor release line; patch versions need not match exactly. ZLS 0.16.0 is therefore the matching release line for Zig 0.16.0.
- ZLS release 0.16.0 resolves to commit `494486203c3a48927f2383aa3d5ce5fca112186d` and uses the MIT license.
- The local environment does not currently have a `zls` executable on `PATH`.
- LSP 3.17 requires `initialize` to be the first client request and prohibits other requests or notifications until initialization completes.
- LSP document-open and document-close notifications must be balanced. The server treats content sent in `didOpen` as client-managed until `didClose`.
- `textDocument/definition` returns `Location`, `Location[]`, `LocationLink[]`, or `null`.
- LSP 3.17 lets a client offer position encodings. The server selects one; omission defaults to UTF-16.
- `$/cancelRequest` requests cancellation, but the protocol notes that a server may be unable to stop immediately and must still return a response.
- `workspace/applyEdit` asks a client to modify resources. A read-only client can omit the capability and defensively return `applied: false` if the request is still received.
- ZLS configuration includes build-system and build-on-save behavior. Its official guide says a detected `check` build step can automatically enable build-on-save and may run `zig build check --watch`. ZLS also uses build-runner behavior to resolve project information.

## Interpretation

- ZLS must be treated as execution of a local external tool with potential exposure to repository-controlled Zig build logic, not as passive file parsing.
- Explicit repository trust is required before launch. Disabling build-on-save narrows behavior but does not prove that all build-system evaluation is disabled.
- A definition-only client can advertise a very small capability set and reject all edit or command requests while still conforming to the required initialization and document lifecycle.
- Request generation and immutable document versions are necessary to prevent late responses from navigating against stale content.
- Supporting UTF-8 and UTF-16 position conversion is required for robust negotiation.

## Remaining uncertainty

- ZLS startup time, definition latency, shutdown behavior, and external-file results have not been tested because ZLS is not installed locally and no fiew client exists.
- The two-second request timeout is a conservative product policy, not a verified ZLS performance threshold.
- The exact initialization option required to force build-on-save off must be verified against ZLS 0.16.0 during implementation.
- ZLS patch releases other than 0.16.0 are compatible by official version policy but remain unverified by this research.

## Sources

- [ZLS installation and version compatibility](https://zigtools.org/zls/install/)
- [ZLS 0.16.0 release](https://github.com/zigtools/zls/releases/tag/0.16.0)
- [ZLS 0.16.0 configuration schema](https://github.com/zigtools/zls/blob/0.16.0/schema.json)
- [ZLS build-on-save guide](https://zigtools.org/zls/guides/build-on-save/)
- [LSP 3.17 specification](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/)
- [LSP 3.17 initialize request source](https://github.com/microsoft/language-server-protocol/blob/gh-pages/_specifications/lsp/3.17/general/initialize.md)
- [LSP 3.17 definition request source](https://github.com/microsoft/language-server-protocol/blob/gh-pages/_specifications/lsp/3.17/language/definition.md)
- [LSP 3.17 didOpen source](https://github.com/microsoft/language-server-protocol/blob/gh-pages/_specifications/lsp/3.17/textDocument/didOpen.md)
- [LSP 3.17 didClose source](https://github.com/microsoft/language-server-protocol/blob/gh-pages/_specifications/lsp/3.17/textDocument/didClose.md)
- [LSP 3.17 applyEdit source](https://github.com/microsoft/language-server-protocol/blob/gh-pages/_specifications/lsp/3.17/workspace/applyEdit.md)
