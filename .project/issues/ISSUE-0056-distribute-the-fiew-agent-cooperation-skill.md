---
id: ISSUE-0056
title: "Distribute the fiew agent cooperation skill"
kind: "implementation"
status: resolved
created: 2026-08-28
assignee: "agent"
parent: "ISSUE-0013-implement-fiew-v0-1.md"
blocked_by:
labels: []
---
# Distribute the fiew agent cooperation skill

## Source authority

- [fiew v0.1](<docs/specs/fiew-v0-1.md>)
- [Distributing and activating a fiew Agent Skill](<docs/research/distributing-and-activating-a-fiew-agent-skill.md>)
- Confirmed product intent in the planning discussion.

## What to build

Add one portable Agent Skill at `skills/fiew/SKILL.md` that guides coding agents through the reviewer-owned fiew handoff. Document project-local and global installation through the Vercel Labs Skills CLI.

The skill activates for tasks that may modify repository files and for explicit fiew-review handoffs. After a reviewable task changes repository files, it suggests `fiew .`, never launches fiew, and does not block task completion. It omits the suggestion when no files changed or no reviewable stopping point exists.

After an explicit handoff such as "Review done," the skill reads the current review, addresses each Open or Outdated thread, verifies resulting changes, appends concise evidence-based agent replies, and re-reads the review before reporting completion. It preserves reviewer ownership of review lifecycle operations.

## Acceptance criteria

- [ ] `skills/fiew/SKILL.md` conforms to the Agent Skills specification and uses a description that matches repository-changing tasks, completed changes, and explicit fiew-review handoffs.
- [ ] After any reviewable completed task that changed repository files, the skill instructs the agent to suggest `fiew .` without launching it or blocking completion; it does not suggest fiew when no files changed.
- [ ] An explicit completed-review handoff instructs the agent to run `fiew review show`, process every Open or Outdated thread, verify changes, append one concise reply per handled thread through `fiew review reply`, and re-read current review state.
- [ ] The skill distinguishes approval-sensitive exit status `1` from command failure: Open or Outdated review state and successful replies may return `1`, while command errors remain failures.
- [ ] The skill never grants agents authority to create, resolve, reopen, or delete threads, change current review selection, or edit `.reviews/` directly.
- [ ] Reply body files are temporary, contain only the intended response, and are removed after use.
- [ ] `README.md` documents project-local and global installation with `npx skills add synthlike/fiew --skill fiew`, the explicit handoff, the best-effort activation limitation, and the requirement for the fiew executable.
- [ ] Skills CLI discovery identifies the distributable `fiew` skill without requiring a custom npm package; validation and temporary-directory installation checks pass.

## Verification

- Validate the skill with the Agent Skills reference validator.
- Confirm Skills CLI list/discovery from this repository selects `fiew` explicitly.
- Exercise project-local installation in a temporary directory and verify the installed `SKILL.md` and any linked/copied files.
- Review scenarios for changed files, no changes, explicit handoff, Open review, approved review, successful reply with exit `1`, and actual CLI failure.

## Out of scope

- A custom npm installer.
- Agent-specific hooks or guaranteed cross-agent activation.
- Installing or launching fiew.
- Polling `.reviews/` or inferring review completion.
- Direct canonical review-file access.
- Reviewer lifecycle authority for agents.

## Comments
## Resolution

Implemented the distributable `fiew` Agent Skill and documented its installation and handoff.

- Added `skills/fiew/SKILL.md` with best-effort post-change review suggestions, explicit completed-review handling, approval-sensitive exit-status handling, temporary reply-body hygiene, and reviewer-only lifecycle authority.
- Documented project-local and global Skills CLI installation, the `Review done` handoff, the executable prerequisite, and portable activation limitations in `README.md`.
- Verified the skill with `skills-ref` 0.1.5.
- Verified Skills CLI 1.5.23 discovers only the selected `fiew` skill from the repository and installs an identical copy into a temporary project's Pi skill directory.
- Verified scenario requirements by inspection/assertions and ran `zig fmt --check src build.zig`, `zig build test`, and `git diff --check` successfully.
