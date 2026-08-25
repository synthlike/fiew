# Record store: GitHub

The GitHub adapter persists every semantic record type as a managed GitHub Cloud issue and implements the complete issue extension. It requires an explicit `OWNER/REPO`, configured login, enabled Issues, repository write permission, native sub-issues, and native issue dependencies.

Pass the named backend instance and complete route label to every portable command:

```bash
helper=docs/agents/backends/github.py
python3 "$helper" --repo OWNER/REPO --login LOGIN --backend github-main \
  --destination-label workflow:record:research record-list --record-type research
```

The helper verifies that `LOGIN` is authenticated, active, and the actual API identity. It never switches global authentication.

## Managed labels

Every managed object has exactly one record label:

- `workflow:record:issues`
- `workflow:record:domain`
- `workflow:record:arps`
- `workflow:record:rfcs`
- `workflow:record:specs`
- `workflow:record:meetings`
- `workflow:record:research`
- `workflow:record:questionnaires`
- `workflow:record:technical_baselines`
- `workflow:record:problem_framing`
- `workflow:record:prototypes`
- `workflow:record:handoffs`

Objects routed as `issues` additionally have exactly one kind label: `workflow:issue:initiative`, `workflow:issue:bug`, `workflow:issue:implementation`, `workflow:issue:clarification`, `workflow:issue:research`, `workflow:issue:prototype`, or `workflow:issue:prerequisite`.

Generate a deterministic label plan and apply only the exact reviewed plan:

```bash
python3 "$helper" --repo OWNER/REPO --login LOGIN labels-plan --output /tmp/labels.json
python3 "$helper" --repo OWNER/REPO --login LOGIN labels-apply \
  --plan-file /tmp/labels.json --yes
```

Planning includes every record and issue-kind label. Application fails if label state changed after review. Ordinary labels cannot use the managed `workflow:*` namespace.

## Non-issue records

Create, read, list/search, revision-gated update, retained archive, and reference rendering are available for all non-issue record keys:

```bash
python3 "$helper" --repo OWNER/REPO --login LOGIN --backend github-main \
  --destination-label workflow:record:specs record-create --record-type specs \
  --title "Accepted behavior" --content-file /tmp/spec.md
python3 "$helper" --repo OWNER/REPO --login LOGIN --backend github-main \
  --destination-label workflow:record:specs record-read --record-type specs accepted-behavior
python3 "$helper" --repo OWNER/REPO --login LOGIN --backend github-main \
  --destination-label workflow:record:specs record-update --record-type specs accepted-behavior \
  --expected-revision 'sha256:...' --content-file /tmp/revised.md
```

Publication closes every non-issue record immediately with reason `completed`. Semantic identifier allocation searches open and closed records and rechecks immediately before create. GitHub has no atomic semantic-ID allocator, so simultaneous clients can still race and must re-read before dependent work. Semantic identity, record type, archive state, and canonical content remain in managed body metadata. Updates preserve the closed lifecycle state and require the exact latest revision. List and search inspect open and closed issues, exclude pull requests, and reject duplicate semantic IDs.

Pass a complete structured reference unchanged to `render-reference`; do not construct a URL or Markdown link in a workflow.

## Issues

Issue commands use portable IDs such as `ISSUE-0042` and require the latest revision for every mutation:

```bash
python3 "$helper" --repo OWNER/REPO --login LOGIN --backend github-main \
  --destination-label workflow:record:issues issue-create --kind implementation \
  --title "Deliver behavior" --body-file /tmp/issue.md
python3 "$helper" --repo OWNER/REPO --login LOGIN --backend github-main \
  --destination-label workflow:record:issues issue-read ISSUE-0042
python3 "$helper" --repo OWNER/REPO --login LOGIN --backend github-main \
  --destination-label workflow:record:issues issue-comment ISSUE-0042 \
  --expected-revision 'sha256:...' --body-file /tmp/comment.md
```

`issue-update`, `issue-claim`, `issue-resolve`, and `issue-cancel` preserve existing semantics. Resolve closes as `completed`; cancel closes as `not planned`. Claims reject an observed assignee conflict but remain non-atomic across simultaneous clients.

`issue-parent` and `issue-block` use native GitHub relationships and are idempotent. `issue-frontier` returns direct children that are open, unassigned, and blocked only by issues closed as `completed`. A cancelled blocker does not satisfy a dependency. Relationship operations resolve portable IDs to GitHub numeric database IDs and never fall back to body text or task lists.

## Safety

Every mutation remains approval-gated. Bodies are supplied through files or standard input, never interpolated into shell commands. Reads return opaque exact-state revisions. The adapter rechecks the complete current state immediately before mutation, and stale revisions fail before writes. Search paginates complete collections and never treats pull requests as records.
