#!/usr/bin/env python3
"""Build the deterministic Skaut Apple Silicon release archive."""

import argparse
import gzip
import hashlib
import io
import os
from pathlib import Path
import subprocess
import tarfile


def run(command, *, cwd, capture=False):
    completed = subprocess.run(
        command,
        cwd=cwd,
        check=True,
        text=True,
        stdout=subprocess.PIPE if capture else None,
    )
    return completed.stdout if capture else None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", default="0.2.0")
    parser.add_argument("--output-dir", default="dist")
    args = parser.parse_args()

    root = Path(__file__).resolve().parent.parent
    output_dir = root / args.output_dir
    artifact_name = f"skaut-v{args.version}-darwin-arm64.tar.gz"
    artifact = output_dir / artifact_name
    checksum = output_dir / f"{artifact_name}.sha256"

    run(["zig", "build", "--fetch"], cwd=root)
    run(
        [
            "zig",
            "build",
            "-Dtarget=aarch64-macos",
            "-Doptimize=ReleaseSafe",
        ],
        cwd=root,
    )
    binary = root / "zig-out/bin/skaut"
    version_output = run([str(binary), "--version"], cwd=root, capture=True)
    if version_output.splitlines()[0] != f"skaut {args.version}":
        raise SystemExit("requested version does not match the built executable")
    architecture = run(["file", str(binary)], cwd=root, capture=True)
    if "Mach-O 64-bit executable arm64" not in architecture:
        raise SystemExit(f"unexpected release architecture: {architecture.strip()}")

    epoch_text = os.environ.get("SOURCE_DATE_EPOCH")
    if epoch_text is None:
        epoch_text = run(["git", "show", "-s", "--format=%ct", "HEAD"], cwd=root, capture=True).strip()
    epoch = int(epoch_text)
    binary_bytes = binary.read_bytes()

    output_dir.mkdir(parents=True, exist_ok=True)
    temporary = artifact.with_suffix(artifact.suffix + ".tmp")
    with temporary.open("wb") as raw:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, compresslevel=9, mtime=epoch) as compressed:
            with tarfile.open(fileobj=compressed, mode="w", format=tarfile.GNU_FORMAT) as archive:
                info = tarfile.TarInfo("skaut")
                info.size = len(binary_bytes)
                info.mode = 0o755
                info.uid = 0
                info.gid = 0
                info.uname = "root"
                info.gname = "root"
                info.mtime = epoch
                archive.addfile(info, fileobj=io.BytesIO(binary_bytes))
    temporary.replace(artifact)

    digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
    checksum.write_text(f"{digest}  {artifact.name}\n")
    print(artifact.relative_to(root))
    print(checksum.relative_to(root))


if __name__ == "__main__":
    main()
