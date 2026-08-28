---
name: fiew
description: Use for tasks that may modify repository files, when finishing reviewable repository changes, or when the user explicitly hands back a completed fiew review (for example, "Review done"). Guides the agent-reviewer handoff without taking reviewer authority.
---

# Cooperate through fiew

Keep the reviewer in control of review state. Never launch fiew yourself.

## Finish a repository-changing task

After completing and verifying a reviewable unit of work:

1. Determine whether the task changed repository files.
2. If files changed and the work is at a reviewable stopping point, finish the task normally and suggest that the user run `fiew .` to review it.
3. If no repository files changed, or there is no reviewable stopping point yet, do not suggest fiew.

The suggestion is optional for the user. Do not launch fiew, wait for a review, poll `.reviews/`, or make review a condition of task completion.

## Respond to an explicit completed-review handoff

When the user explicitly says the fiew review is ready, such as "Review done":

1. Run `fiew review show` from the repository and capture its JSON output and exit status.
2. Treat exit status `0` as an approved review and status `1` as a successfully read review that still has an Open or Outdated thread. Treat any other status as a command failure and stop with the error.
3. Read every thread and its complete ordered comment history. Process every thread whose `status` is `open` or `outdated`.
4. Address each actionable concern in the repository. If a concern should not cause a change, determine the concise evidence-based explanation to return. Do not edit `.reviews/` directly.
5. Verify each resulting change with the narrowest relevant checks.
6. For each handled thread, create a temporary body file containing only the intended concise response. Run `fiew review reply <thread-id> --body-file <temporary-path>`, then remove the temporary file even when the command fails. The response should state what changed or explain why no change was made and include relevant verification evidence.
7. For `review reply`, exit status `0` means the reply was saved and the review is approved; status `1` means the reply was saved but the review still has an Open or Outdated thread. Treat any other status as failure.
8. Re-run `fiew review show`, accepting status `0` or `1`, and re-read the complete current review before reporting completion. If new or still-unanswered Open or Outdated threads remain, process them before finishing.

Agents may append replies only. Never create, resolve, reopen, or delete threads; never change which review is current; and never infer approval from your own changes. The reviewer alone owns those lifecycle decisions.
