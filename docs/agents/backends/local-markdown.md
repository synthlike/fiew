# Record store: Local Markdown

The local adapter persists every configured semantic record type and implements the complete issue extension. Invoke `local-markdown.py` with the consumer root, named backend instance, and configured destination.

## Records

Non-issue destinations use `--destination PATH`. ARP and RFC destinations also pass `--prefix` before the operation.

```bash
helper=backends/record-store/local-markdown.py
python3 "$helper" --root . --backend local --destination docs/research \
  create --record-type research --title "Question" --content-file findings.md
python3 "$helper" --root . --backend local --destination docs/decisions --prefix ARP \
  create --record-type arps --title "Decision" --content-file decision.md
```

Create, read, list/search, revision-gated update, and retained archive are available for:

- `domain`;
- `arps`;
- `rfcs`;
- `specs`;
- `meetings`;
- `research`;
- `questionnaires`;
- `technical_baselines`;
- `problem_framing`;
- `prototypes`; and
- `handoffs`.

Use the returned semantic `id` for later operations and pass the exact returned `revision` to update or archive:

```bash
python3 "$helper" --root . --backend local --destination docs/research \
  read question --record-type research
python3 "$helper" --root . --backend local --destination docs/research \
  list --record-type research --query compatibility
python3 "$helper" --root . --backend local --destination docs/research \
  update question --record-type research --expected-revision 'sha256:...' \
  --content-file revised.md
python3 "$helper" --root . --backend local --destination docs/research \
  archive question --record-type research --expected-revision 'sha256:...'
```

To render a structured reference inside local Markdown, save the complete returned reference object as JSON and pass it unchanged to the destination adapter:

```bash
python3 "$helper" --root . --backend local --destination docs/specs \
  render-reference --reference-file reference.json
```

The operation accepts references from other backend instances and returns destination-owned Markdown. Workflows must not construct the link themselves.

Create uses exclusive file creation. ARPs and RFCs allocate the next prefixed number inside create. Other records allocate a title slug and numeric suffix. An explicitly imported semantic ID fails on collision. Archive retains the record and excludes it from normal listing.

## Issues

Issue commands use the configured issue root as `--destination`:

```bash
python3 "$helper" --root . --backend local --destination .project \
  issue-create --title "Deliver behavior" --body-file issue.md --kind implementation
python3 "$helper" --root . --backend local --destination .project issue-read ISSUE-0001
python3 "$helper" --root . --backend local --destination .project issue-list --state open
```

Every issue mutation requires the revision returned by the latest read:

```bash
python3 "$helper" --root . --backend local --destination .project \
  issue-comment ISSUE-0001 --expected-revision 'sha256:...' --body-file comment.md
python3 "$helper" --root . --backend local --destination .project \
  issue-claim ISSUE-0001 --expected-revision 'sha256:...' --assignee agent
python3 "$helper" --root . --backend local --destination .project \
  issue-resolve ISSUE-0001 --expected-revision 'sha256:...' --body-file resolution.md
python3 "$helper" --root . --backend local --destination .project \
  issue-cancel ISSUE-0001 --expected-revision 'sha256:...' --body-file reason.md
```

`issue-update`, `issue-parent`, and `issue-block` provide guarded metadata and relationship writes. `issue-frontier PARENT_ID` returns direct children that are open, unassigned, and have only resolved blockers. Repeating a parent or blocker addition is safe. Cancelled blockers do not satisfy dependencies.

The adapter reads the established local issue frontmatter, appends chronological comments under `## Comments`, records outcomes under `## Resolution`, and preserves `open`, `claimed`, `resolved`, and `cancelled` semantics. Claims and identifier allocation are not atomic across unsynchronized working trees.

## Safety

All destinations must remain inside the consumer root. Directories are created only with the first write. Exact persisted bytes produce opaque revisions. Updates write a temporary file and replace the target only after repeated revision checks. Malformed records, duplicate identities, stale revisions, broken relationship targets, and unsupported destination fields fail without an approved record mutation.

Schema 3 routes are authoritative. The adapter does not read schema-2 configuration or migrate existing records.
