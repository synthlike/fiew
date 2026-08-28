---
name: publish-github-release
description: Safely publish a verified GitHub Release from an approved commit and artifacts. Use only when explicitly invoked to push a release tag and create a GitHub Release.
compatibility: Requires Git, GitHub CLI authentication, and permission to publish to the target repository.
disable-model-invocation: true
---

# Publish a GitHub Release

Publish only an already approved release. Treat pushes, tags, releases, and uploaded assets as production-facing external mutations.

## Establish the release contract

Read repository guidance, release checklists, version metadata, build and packaging commands, supported-platform documentation, and workspace status. Identify:

- repository owner and name;
- authenticated GitHub identity;
- release version and exact tag;
- exact source commit and branch;
- draft, prerelease, or public-release intent;
- required artifacts and checksums;
- release title and notes; and
- required pre-publication and post-publication verification.

Do not infer an ambiguous version, repository, identity, target commit, release visibility, or artifact set. Ask one focused question when any is unresolved.

## Perform non-mutating preflight

Before proposing publication:

1. Require a clean working tree and inspect the branch's relationship to its upstream.
2. Run `gh auth status`, query the active login, and inspect the target repository without changing it.
3. Confirm the authenticated login is the intended publisher.
4. Check local and remote tags and existing GitHub Releases. Refuse to replace an existing tag or release.
5. Confirm the target commit contains the reviewed release changes.
6. Run the repository's documented tests and release checks. Ask before expensive, destructive, production-facing, or externally visible commands not already approved.
7. Build artifacts from the exact target commit using the repository's documented release command.
8. Verify archive contents, executable version, target architecture, linked dependencies, and checksums as required by the release contract.
9. When reproducibility is required, build twice from a clean checkout or equivalent clean source tree and compare checksums.
10. Review release notes against the documented compatibility and support boundary. Do not add unsupported claims.

Stop on any failed check. Do not weaken a checklist or silently publish a partial artifact set.

## Confirm external mutations

Present one publication plan containing:

- authenticated publisher and target repository;
- branch and commits to push;
- tag and target commit;
- release visibility;
- release title and notes summary;
- artifact names, sizes, and checksums;
- exact external mutations; and
- known limitations such as unsigned or unnotarized binaries.

Obtain explicit approval immediately before creating a local release tag, pushing commits or tags, creating the GitHub Release, or uploading assets. Earlier implementation or configuration approval does not approve publication.

## Publish

After approval:

1. Regenerate artifacts from the exact approved commit if the commit changed after preflight.
2. Reverify checksums and artifact metadata.
3. Create an annotated local tag without replacing any existing reference.
4. Push the approved branch and tag atomically when the remote supports it. Never force-push.
5. Create the release with `gh release create --verify-tag`, explicit title, explicit notes, explicit draft/prerelease state, and the approved assets.
6. Do not use options that synthesize an unreviewed tag, overwrite assets, or generate release claims outside the approved notes.

If any external operation partially succeeds, stop. Report the exact remote state and safest forward action. Do not delete or rewrite a published tag or release as an automatic rollback.

## Verify publication

After publication:

1. Read the release through GitHub and confirm publisher, tag, target commit, visibility, title, notes, and uploaded assets.
2. Download the published assets into a temporary directory.
3. Verify published checksums and required archive or executable metadata again.
4. Confirm the local branch and tag match their remote references and the working tree remains clean.
5. Report the public or draft release URL, tag target, artifact digests, verification results, and any remaining limitations.

Follow the repository's configured workflow before updating or resolving release records. Do not mutate issue or documentation state merely because publication succeeded.
