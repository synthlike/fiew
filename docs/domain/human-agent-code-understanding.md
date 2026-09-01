<!-- agent-workflows-record
{"archived":false,"created":"2026-09-01T09:39:25Z","id":"human-agent-code-understanding","modified":"2026-09-01T16:03:04Z","record_type":"domain","title":"Human-agent code understanding"}
-->
# Human-agent code understanding

This context describes the durable artifacts through which a human examines repository code, exchanges anchored explanations with an agent, and evaluates changes without granting source-write authority.

## Language

**Discovery**:
A durable named container for understanding existing repository code through source-anchored conversations and explanatory Trails. A Discovery is knowledge-oriented and does not affect review approval.
_Avoid_: Investigation, discovery session

**Review**:
A durable named container for evaluating repository changes and deciding approval. A Review owns concerns whose lifecycle and anchor validity may block approval.
_Avoid_: Discovery, generic conversation

**Discovery Thread**:
A human-created conversation anchored to repository source within a Discovery. Its human-controlled lifecycle is Open, Answered, or Archived.
_Avoid_: Review thread, concern, note

**Review Concern**:
A human-created conversation anchored to a changed file or one side of a diff within a Review. Its lifecycle and anchor validity contribute to review approval.
_Avoid_: Discovery Thread, note

**Comment**:
An immutable ordered human or agent contribution to a Discovery Thread or Review Concern. An agent may append a Comment only through the command-mediated reply boundary.
_Avoid_: Editable note

**Anchor Validity**:
The independent Current or Outdated state describing whether fiew can validate an artifact's repository location without guessing. Anchor Validity does not answer, resolve, or archive its owning conversation.
_Avoid_: Thread status

**Trail**:
A human-curated or agent-proposed ordered explanatory path containing at least two Trail Points with source Anchors. Trail Points are not Spots unless saved independently. A Trail may attach to a Discovery or Review, but it never affects approval.
_Avoid_: Execution trace, call graph, concern

**Proposed Trail**:
A Trail submitted by an agent as a structured attachment while replying to a human-created thread or concern. It retains agent authorship and requires human acceptance or archival.
_Avoid_: Saved Trail, automatic Trail

**Bookmark**:
A private single repository location retained for human navigation. It is not agent-visible conversation context unless a human explicitly uses it in another artifact.
_Avoid_: Trail, thread
