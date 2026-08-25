# Record store: Bear MCP

The Bear backend scopes one `bearcli mcp-server` process to a project workspace tag. It is intended for the eleven non-issue semantic record types; it never implements the `issues` extension.

## Configuration

A backend instance requires an explicit absolute executable and one project workspace tag:

```yaml
backends:
  notes:
    type: bear
    command: /Applications/Bear.app/Contents/MacOS/bearcli
    workspace: agent-workflows/project-key
```

Each routed non-issue record uses one workspace-relative nested tag:

```yaml
records:
  specs:
    enabled: true
    backend: notes
    destination: {tag: specs}
```

The adapter composes `agent-workflows/project-key/specs`. Tags must be trimmed relative names without a leading `#` or `/`, empty or dot segments, commas, backslashes, or repetition of the workspace.

## Read-only preflight

Run preflight before recommending or approving any Bear route:

```bash
python3 docs/agents/backends/bear.py \
  --command /Applications/Bear.app/Contents/MacOS/bearcli \
  --workspace agent-workflows/project-key preflight
```

The helper launches exactly `COMMAND mcp-server --only-tags WORKSPACE`, initializes MCP protocol `2025-06-18`, verifies the `bearcli` identity and echoed single-tag scope, and inspects `tools/list`. It requires scoped create, metadata read, whole-note hash read, paginated list/search, `baseHash` overwrite, and add/remove tag schemas with appropriate read-only annotations.

Preflight calls no Bear tools and creates or changes no note or tag. Route approval additionally requires the immutable Bear adapter declaration to contain the routed type and every common record operation.

## Records

The adapter supports create, read, paginated list/search, revision-gated update, metadata-only archive, and reference rendering for all eleven non-issue record types. Pass the named backend and route tag explicitly:

```bash
python3 docs/agents/backends/bear.py \
  --command /Applications/Bear.app/Contents/MacOS/bearcli \
  --workspace agent-workflows/project-key \
  --backend notes --destination-tag research \
  record-create --record-type research --title "Finding" --content-file finding.md
```

Use the returned semantic ID and opaque `bear-base-hash:*` revision for later operations:

```bash
python3 docs/agents/backends/bear.py --command /Applications/Bear.app/Contents/MacOS/bearcli \
  --workspace agent-workflows/project-key --backend notes --destination-tag research \
  record-read --record-type research finding
python3 docs/agents/backends/bear.py --command /Applications/Bear.app/Contents/MacOS/bearcli \
  --workspace agent-workflows/project-key --backend notes --destination-tag research \
  record-update --record-type research finding --expected-revision 'bear-base-hash:...' \
  --content-file revised.md
```

Managed notes retain semantic ID, type, and archive state in the canonical metadata envelope. Provider-owned framing preserves a first-level title and both workspace hashtags through whole-note overwrite. The adapter paginates every note under the nested route tag, parses managed metadata, rechecks semantic IDs immediately before create, and re-reads after every mutation to obtain the next Bear hash. Archive changes managed metadata rather than moving the note into Bear's native Archive.

Returned references retain the native note ID and use Bear's documented `bear://x-callback-url/open-note?id=...` deep link. `render-reference` accepts complete structured references from any backend without launching MCP.

## Safety and limitations

Configuration and every mutation remain approval-gated. The helper does not add a harness MCP registration and does not discover a command from `PATH`. Bear is optional and normal repository verification does not launch it. Encrypted note content is unavailable through Bear MCP. Managed records with attachments reject whole-note update or archive to prevent undeclared attachment removal. Stale `baseHash` writes and malformed provider content fail without an adapter write. Semantic-ID allocation rechecks before create but remains non-atomic across simultaneous clients.
