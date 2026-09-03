<!-- agent-workflows-record
{"archived":false,"created":"2026-09-03T10:24:16Z","id":"skaut-v0-2-release-checklist","modified":"2026-09-03T10:27:21Z","record_type":"technical_baselines","title":"Skaut v0.2 release checklist"}
-->
# Skaut v0.2 release checklist

## Purpose and maturity

Use this baseline to produce and verify the first Skaut release from a clean, reviewed commit. It defines the v0.2 release gate; it does not publish a release automatically or expand supported platforms.

## Fixed technology constraints

| Technology or platform | Supported version or boundary | Evidence |
| --- | --- | --- |
| Zig | 0.16.0 with locked dependencies | Build manifest and verified release builds |
| Apple Silicon macOS | `aarch64-macos` ReleaseSafe archive | Verified package build, checksum, architecture, and execution |
| x86_64 Linux | Baseline CPU, static `x86_64-linux-musl` ReleaseSafe archive | Verified package build, static ELF inspection, and Ubuntu 22.04 execution |
| ARM64 Linux | Source-build compile check only; no archive or runtime claim | Verified baseline `aarch64-linux-musl` build |
| Terminals | Ghostty, Kitty, and WezTerm on supported macOS and Linux targets | Recorded v0.2 portable terminal smoke results |

## Compatibility and prerequisites

- Build from a clean checkout with Zig 0.16.0 and the locked dependency set. The packaging host also requires Git and the `file` utility.
- Ubuntu 22.04 with Linux 5.15 is the verified x86_64 Linux compatibility floor. Other x86_64 distributions meeting that kernel floor are best-effort unless separately tested.
- Git is required for Review Diff but not repository browsing. ZLS 0.16.x is optional and requires explicit repository trust.
- The macOS executable is unsigned and unnotarized. Signing, notarization, package managers, automatic updates, Windows, Intel macOS, and ARM64 Linux release artifacts are outside v0.2.
- Preserve the historical fiew v0.1.0 tag, release, executable, and asset names unchanged.

## Approved conventions

1. Build release archives only from the reviewed release commit with a clean working tree.
2. Run deterministic tests without optional executables, then run opt-in Git and live ZLS integrations separately.
3. Produce both archives with `tools/package-release.py`. The script derives archive timestamps from `SOURCE_DATE_EPOCH` or the release commit, normalizes tar metadata, and emits one SHA-256 file per archive.
4. Run packaging twice from the same commit and require identical checksum files.
5. Verify each checksum before extraction. Require exactly one executable named `skaut` in each archive.
6. Verify the macOS artifact is a Mach-O ARM64 executable and reports `skaut 0.2.0`.
7. Verify the Linux artifact is a statically linked x86-64 ELF. Extract and execute it in a clean Ubuntu 22.04 x86_64 environment and require `skaut 0.2.0`.
8. Compile the locked source for baseline `aarch64-linux-musl` without publishing that output.
9. Complete and retain the portable terminal smoke evidence before tagging.
10. Create the `v0.2.0` tag and GitHub release manually only after the release commit and evidence are reviewed. Upload the four generated files without renaming them.

## Recommendations awaiting approval

None.

## Open decisions

None for the v0.2 release boundary.

## Deferred product questions

Future signing, notarization, package-manager distribution, automatic updates, and additional platform support require separate planning and evidence.

## Verification and operating commands

Run from a clean Apple Silicon macOS checkout:

```sh
git status --short
zig version
zig build test --summary all
zig build test -Dgit-integration -Dzls-integration --summary all
zig build -Dtarget=aarch64-linux-musl -Dcpu=baseline
rm -rf dist
python3 tools/package-release.py --version 0.2.0
cp dist/skaut-v0.2.0-darwin-arm64.tar.gz.sha256 /tmp/skaut-darwin-first.sha256
cp dist/skaut-v0.2.0-linux-x86_64.tar.gz.sha256 /tmp/skaut-linux-first.sha256
python3 tools/package-release.py --version 0.2.0
diff -u /tmp/skaut-darwin-first.sha256 dist/skaut-v0.2.0-darwin-arm64.tar.gz.sha256
diff -u /tmp/skaut-linux-first.sha256 dist/skaut-v0.2.0-linux-x86_64.tar.gz.sha256
(cd dist && shasum -a 256 -c skaut-v0.2.0-darwin-arm64.tar.gz.sha256)
(cd dist && shasum -a 256 -c skaut-v0.2.0-linux-x86_64.tar.gz.sha256)
tar -tzf dist/skaut-v0.2.0-darwin-arm64.tar.gz
tar -tzf dist/skaut-v0.2.0-linux-x86_64.tar.gz
```

Extract the macOS archive into a clean temporary directory, then run:

```sh
file skaut
./skaut --version
otool -L skaut
```

On a clean Ubuntu 22.04 x86_64 environment, copy or download the Linux archive and checksum, then run:

```sh
sha256sum -c skaut-v0.2.0-linux-x86_64.tar.gz.sha256
tar -tzf skaut-v0.2.0-linux-x86_64.tar.gz
mkdir extracted
tar -xzf skaut-v0.2.0-linux-x86_64.tar.gz -C extracted
file extracted/skaut
ldd extracted/skaut 2>&1 | grep -E 'not a dynamic executable|statically linked'
./extracted/skaut --version
```

Require the exact archive names:

- `skaut-v0.2.0-darwin-arm64.tar.gz`
- `skaut-v0.2.0-darwin-arm64.tar.gz.sha256`
- `skaut-v0.2.0-linux-x86_64.tar.gz`
- `skaut-v0.2.0-linux-x86_64.tar.gz.sha256`

## References

- [Skaut v0.2](<docs/specs/fiew-v0-2.md>)
- [Adopt Skaut as the complete product identity](<docs/decisions/ARP-0015.md>)
- [Produce and verify the Skaut v0.2 release artifacts](<.project/issues/ISSUE-0068-produce-and-verify-the-fiew-v0-2-release-artifacts.md>)
