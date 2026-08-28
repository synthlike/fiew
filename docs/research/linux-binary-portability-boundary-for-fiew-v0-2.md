<!-- agent-workflows-record
{"archived":false,"created":"2026-08-28T15:26:44Z","id":"linux-binary-portability-boundary-for-fiew-v0-2","modified":"2026-08-28T15:26:44Z","record_type":"research","title":"Linux binary portability boundary for fiew v0.2"}
-->
# Linux binary portability boundary for fiew v0.2

## Question

Which libc, minimum distribution or kernel, dynamic-linking, archive, and CI choices can produce a practical x86_64 Linux release while retaining a non-gating ARM64 Linux source build?

## Verified findings

- Zig exposes `x86_64-linux-musl`, `x86_64-linux-gnu`, and `aarch64-linux-musl` targets. A musl target permits a statically linked executable without a host glibc or dynamic-loader dependency.
- musl officially supports Linux 2.6 and later. This is a libc floor, not evidence that fiew, Zig 0.16.0 output, or libvaxis has been exercised on every such kernel.
- GitHub-hosted runners provide fixed Ubuntu 22.04 and 24.04 labels for x86_64 and ARM64.
- The XDG Base Directory Specification identifies `$HOME/.local/bin` as a location for user-specific executables.
- The current fiew source does not cross-compile to Linux unchanged. Vendored Tree-sitter C sources lack declarations for `fdopen`, `le16toh`, and `be16toh` under the current C flags.
- In a disposable repository copy, adding `_POSIX_C_SOURCE=200809L` and `_DEFAULT_SOURCE` to the vendored C compilation produced baseline-CPU, statically linked x86_64 and ARM64 Linux ELF executables with Zig 0.16.0. This experiment did not change production source and did not run either executable on Linux.

## Interpretation and recommendation

- Release one baseline-CPU, statically linked `x86_64-linux-musl` executable. This gives fiew one libc-independent Linux artifact instead of separate glibc and musl variants.
- Package it as a deterministic `tar.gz` with a SHA-256 checksum, matching the macOS release shape.
- Build and test the release artifact natively on an `ubuntu-22.04` x86_64 runner. Run deterministic tests, execute `fiew --version`, inspect ELF architecture and static linkage, and perform available startup and terminal-restoration checks before publication.
- Use Ubuntu 22.04 and Linux 5.15 as the verified compatibility floor. Treat other x86_64 distributions on Linux 5.15 or later as expected but best-effort until runtime-tested. Do not present musl's Linux 2.6 support as fiew's floor.
- Keep `aarch64-linux-musl` as a source-build compile check, preferably on an ARM64 runner. Do not require an ARM64 runtime smoke test or release archive for v0.2.
- Keep Git, ZLS, and `mermaid-ascii` as separately installed executables. Static linkage of fiew does not bundle or alter those tools.

## Remaining uncertainty

- Successful cross-compilation does not establish runtime compatibility.
- Ordinary CI process execution does not replace smoke tests in an actual TTY and the required Ghostty, Kitty, and WezTerm matrix.
- Older kernels and distributions may work, but fiew should not promise them without VM or hardware testing.

## Sources

- [Zig targets and cross-compilation](https://ziglang.org/documentation/0.15.2/#Targets)
- [musl FAQ](https://www.musl-libc.org/faq.html)
- [GitHub-hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)
- [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/latest/)
- [Linux stable userspace ABI](https://docs.kernel.org/admin-guide/abi-stable.html)
