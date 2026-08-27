<!-- agent-workflows-record
{"archived":false,"created":"2026-08-27T19:05:34Z","id":"github-pull-request-review-api-feasibility-for-fiew-v0-4","modified":"2026-08-27T19:05:34Z","record_type":"research","title":"GitHub pull-request review API feasibility for fiew v0.4"}
-->
# GitHub pull-request review API feasibility for fiew v0.4

## Question

Can fiew map its local anchored review-thread model to GitHub pull-request reviews while keeping publication explicit and preserving its source-read-only boundary?

## Findings

- GitHub's pull-request review-comment REST API supports file comments, single-line and multiline diff comments, side and line coordinates, commit identifiers, diff hunks, and replies to existing review comments.
- GitHub's GraphQL API exposes review-thread resolution through `resolveReviewThread`.
- GitHub's pull-request review REST API supports pending reviews and explicit `COMMENT`, `REQUEST_CHANGES`, and `APPROVE` submission events.
- The GitHub CLI can supply authenticated API access through `gh api`; its authentication flow can retain credentials outside fiew. This could avoid a new fiew-owned token store, but choosing it is a product and distribution decision rather than an API requirement.
- The APIs make the proposed workflow feasible, but they do not settle local/remote identity mapping, concurrent-update conflicts, offline behavior, or whether agent-authored local replies may be published.

## Recommendation

Treat GitHub pull-request review as feasible for v0.4. Keep local review state authoritative while offline, import remote threads explicitly, and require an explicit publish or submit action for every GitHub mutation. Resolve authentication, conflict handling, and agent publication rights before writing a v0.4 specification.

## Sources

- [GitHub REST API: pull-request review comments](https://docs.github.com/en/rest/pulls/comments?apiVersion=2022-11-28)
- [GitHub REST API: pull-request reviews](https://docs.github.com/en/rest/pulls/reviews)
- [GitHub GraphQL pull-request mutations](https://docs.github.com/en/graphql/reference/pulls)
- [GitHub CLI `gh api`](https://cli.github.com/manual/gh_api)
- [GitHub CLI authentication](https://cli.github.com/manual/gh_auth_login)
