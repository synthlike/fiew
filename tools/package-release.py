#!/usr/bin/env python3
"""Build deterministic Skaut release archives for supported platforms."""

import argparse
import gzip
import hashlib
import io
import os
from pathlib import Path
import subprocess
import tarfile


PLATFORMS = {
    "darwin-arm64": {
        "target": "aarch64-macos",
        "cpu": None,
        "file_markers": ("Mach-O 64-bit executable arm64",),
    },
    "linux-x86_64": {
        "target": "x86_64-linux-musl",
        "cpu": "baseline",
        "file_markers": ("ELF 64-bit", "x86-64", "statically linked"),
    },
}


def run(command, *, cwd, capture=False):
    completed = subprocess.run(
        command,
        cwd=cwd,
        check=True,
        text=True,
        stdout=subprocess.PIPE if capture else None,
    )
    return completed.stdout if capture else None


def archive_binary(binary_bytes, artifact, epoch):
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


def display_path(path, root):
    try:
        return path.relative_to(root)
    except ValueError:
        return path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", default="0.2.0")
    parser.add_argument("--output-dir", default="dist")
    parser.add_argument("--platform", choices=("all", *PLATFORMS), default="all")
    args = parser.parse_args()

    root = Path(__file__).resolve().parent.parent
    requested_output = Path(args.output_dir)
    output_dir = requested_output if requested_output.is_absolute() else root / requested_output
    selected = PLATFORMS if args.platform == "all" else {args.platform: PLATFORMS[args.platform]}

    run(["zig", "build", "--fetch"], cwd=root)
    run(["zig", "build", "-Doptimize=ReleaseSafe"], cwd=root)
    native_binary = root / "zig-out/bin/skaut"
    version_output = run([str(native_binary), "--version"], cwd=root, capture=True)
    if version_output.splitlines()[0] != f"skaut {args.version}":
        raise SystemExit("requested version does not match the built executable")

    epoch_text = os.environ.get("SOURCE_DATE_EPOCH")
    if epoch_text is None:
        epoch_text = run(["git", "show", "-s", "--format=%ct", "HEAD"], cwd=root, capture=True).strip()
    epoch = int(epoch_text)
    output_dir.mkdir(parents=True, exist_ok=True)

    for platform, config in selected.items():
        command = [
            "zig",
            "build",
            f"-Dtarget={config['target']}",
            "-Doptimize=ReleaseSafe",
        ]
        if config["cpu"] is not None:
            command.append(f"-Dcpu={config['cpu']}")
        run(command, cwd=root)

        binary = root / "zig-out/bin/skaut"
        architecture = run(["file", str(binary)], cwd=root, capture=True)
        if not all(marker in architecture for marker in config["file_markers"]):
            raise SystemExit(f"unexpected {platform} release architecture: {architecture.strip()}")

        artifact_name = f"skaut-v{args.version}-{platform}.tar.gz"
        artifact = output_dir / artifact_name
        checksum = output_dir / f"{artifact_name}.sha256"
        archive_binary(binary.read_bytes(), artifact, epoch)
        digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
        checksum.write_text(f"{digest}  {artifact.name}\n")
        print(display_path(artifact, root))
        print(display_path(checksum, root))


if __name__ == "__main__":
    main()
