#!/usr/bin/env python3
"""Generate manifests and verify complete Agent Workflows installations."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import sys
from typing import Any

from consumer import dependency_closure, inspect_skills, verify_consumer


MANIFEST_FORMAT = 1
MANIFEST_RELATIVE_PATH = PurePosixPath(
    "configure-workflows/references/distribution-manifest.json"
)
IGNORED_NAMES = {".DS_Store", "__pycache__"}
INLINE_CODE = re.compile(r"`([a-z0-9]+(?:-[a-z0-9]+)+)`")
VERSION = re.compile(r"v(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)")


class LifecycleError(ValueError):
    """A manifest or installation violates the lifecycle contract."""


def canonical_json(value: Any) -> bytes:
    return (json.dumps(value, indent=2, sort_keys=True) + "\n").encode()


def _unique_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    value: dict[str, Any] = {}
    for key, item in pairs:
        if key in value:
            raise LifecycleError(f"duplicate JSON key: {key}")
        value[key] = item
    return value


def parse_json(data: bytes | str, label: str) -> dict[str, Any]:
    try:
        value = json.loads(data, object_pairs_hook=_unique_object)
    except (json.JSONDecodeError, UnicodeDecodeError) as error:
        raise LifecycleError(f"invalid {label}: {error}") from error
    if not isinstance(value, dict):
        raise LifecycleError(f"invalid {label}: expected a JSON object")
    return value


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _metadata(root: Path) -> dict[str, Any]:
    path = root / "release/metadata.json"
    try:
        metadata = parse_json(path.read_bytes(), f"release metadata {path}")
    except OSError as error:
        raise LifecycleError(f"invalid release metadata {path}: {error}") from error
    if set(metadata) != {"configuration", "skills", "source", "version"}:
        raise LifecycleError(
            "release metadata must contain configuration, skills, source, and version"
        )
    if not isinstance(metadata["source"], str) or not metadata["source"]:
        raise LifecycleError("release source must be a non-empty string")
    if not isinstance(metadata["version"], str) or not VERSION.fullmatch(metadata["version"]):
        raise LifecycleError("release version must be an exact vMAJOR.MINOR.PATCH identifier")
    declared_skills = metadata["skills"]
    if (
        not isinstance(declared_skills, list)
        or declared_skills != sorted(set(declared_skills))
        or any(
            not isinstance(name, str)
            or not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)+", name)
            for name in declared_skills
        )
        or "configure-workflows" not in declared_skills
    ):
        raise LifecycleError("release skills must be valid, unique, sorted, and include configure-workflows")
    configuration = metadata["configuration"]
    if not isinstance(configuration, dict) or set(configuration) != {
        "current_schema",
        "readable_schemas",
    }:
        raise LifecycleError("release configuration metadata is invalid")
    current = configuration["current_schema"]
    readable = configuration["readable_schemas"]
    if not isinstance(current, int) or not isinstance(readable, list):
        raise LifecycleError("configuration schemas must be integer values")
    if not readable or any(not isinstance(item, int) for item in readable) or current not in readable:
        raise LifecycleError("readable schemas must uniquely include the current schema")
    if len(readable) != len(set(readable)):
        raise LifecycleError("readable configuration schemas must be unique")
    return metadata


def _skill_names(root: Path, expected: set[str]) -> set[str]:
    skills = root / "skills"
    names = {path.parent.name for path in skills.glob("*/SKILL.md")}
    if not names:
        raise LifecycleError(f"no skills found under {skills}")
    incomplete = {
        path.name for path in skills.iterdir() if path.is_dir() and not (path / "SKILL.md").is_file()
    }
    missing = expected - names
    unknown = names - expected
    errors = []
    if incomplete:
        errors.append(f"skill directories missing SKILL.md: {', '.join(sorted(incomplete))}")
    if missing:
        errors.append(f"release skills missing from source: {', '.join(sorted(missing))}")
    if unknown:
        errors.append(f"source contains unknown release skills: {', '.join(sorted(unknown))}")
    if errors:
        raise LifecycleError("; ".join(errors))
    return names


def _declared_dependencies(root: Path, names: set[str]) -> dict[str, list[str]]:
    dependencies: dict[str, list[str]] = {}
    for name in sorted(names):
        text = (root / "skills" / name / "SKILL.md").read_text()
        targets = {
            target
            for target in INLINE_CODE.findall(text)
            if target in names and target not in {name, "configure-workflows"}
        }
        dependencies[name] = sorted(targets)
    return dependencies


def _is_ignored(path: Path) -> bool:
    return any(part in IGNORED_NAMES for part in path.parts) or path.suffix in {".pyc", ".pyo"}


def _skill_files(skill_dir: Path, skill_name: str) -> dict[str, str]:
    files: dict[str, str] = {}
    for path in sorted(skill_dir.rglob("*")):
        relative = path.relative_to(skill_dir)
        if _is_ignored(relative):
            continue
        if path.is_symlink():
            raise LifecycleError(f"distributed skill contains a symlink: {skill_name}/{relative}")
        if path.is_dir():
            continue
        if not path.is_file():
            raise LifecycleError(f"distributed skill contains a non-file: {skill_name}/{relative}")
        pure = PurePosixPath(relative.as_posix())
        if pure.is_absolute() or ".." in pure.parts:
            raise LifecycleError(f"distributed file escapes skill directory: {skill_name}/{relative}")
        if skill_name == "configure-workflows" and pure == MANIFEST_RELATIVE_PATH.relative_to(
            "configure-workflows"
        ):
            continue
        key = pure.as_posix()
        if key in files:
            raise LifecycleError(f"duplicate distributed path: {skill_name}/{key}")
        files[key] = sha256(path.read_bytes())
    return files


def generate_manifest(root: Path) -> dict[str, Any]:
    root = root.resolve()
    metadata = _metadata(root)
    names = _skill_names(root, set(metadata["skills"]))
    dependencies = _declared_dependencies(root, names)
    skills: dict[str, Any] = {}
    for name in sorted(names):
        skills[name] = {
            "dependencies": dependencies[name],
            "files": _skill_files(root / "skills" / name, name),
        }
    return {
        "configuration": metadata["configuration"],
        "distribution": {
            "source": metadata["source"],
            "version": metadata["version"],
        },
        "manifest_version": MANIFEST_FORMAT,
        "skills": skills,
    }


def validate_manifest(manifest: dict[str, Any], root: Path | None = None) -> list[str]:
    errors: list[str] = []
    if set(manifest) != {"configuration", "distribution", "manifest_version", "skills"}:
        errors.append("manifest has missing or unknown top-level fields")
    if manifest.get("manifest_version") != MANIFEST_FORMAT:
        errors.append(f"manifest_version must be {MANIFEST_FORMAT}")
    distribution = manifest.get("distribution")
    if not isinstance(distribution, dict) or set(distribution) != {"source", "version"}:
        errors.append("manifest distribution is invalid")
    elif not isinstance(distribution.get("source"), str) or not VERSION.fullmatch(
        str(distribution.get("version", ""))
    ):
        errors.append("manifest distribution identity is invalid")
    configuration = manifest.get("configuration")
    if not isinstance(configuration, dict) or set(configuration) != {
        "current_schema",
        "readable_schemas",
    }:
        errors.append("manifest configuration compatibility is invalid")
    else:
        current = configuration.get("current_schema")
        readable = configuration.get("readable_schemas")
        if (
            not isinstance(current, int)
            or not isinstance(readable, list)
            or not readable
            or any(not isinstance(item, int) for item in readable)
            or len(readable) != len(set(readable))
            or current not in readable
        ):
            errors.append("manifest configuration schemas are invalid")
    skills = manifest.get("skills")
    if not isinstance(skills, dict) or not skills:
        errors.append("manifest must contain skills")
        return errors
    names = set(skills)
    for name, entry in sorted(skills.items()):
        if not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)+", name):
            errors.append(f"invalid skill name: {name}")
            continue
        if not isinstance(entry, dict) or set(entry) != {"dependencies", "files"}:
            errors.append(f"{name} manifest entry is invalid")
            continue
        dependencies = entry["dependencies"]
        files = entry["files"]
        if (
            not isinstance(dependencies, list)
            or dependencies != sorted(set(dependencies))
            or any(not isinstance(item, str) for item in dependencies)
        ):
            errors.append(f"{name} dependencies must be unique and sorted")
        else:
            for dependency in dependencies:
                if dependency not in names:
                    errors.append(f"{name} depends on unknown skill {dependency}")
                if dependency == name:
                    errors.append(f"{name} cannot directly depend on itself")
        if not isinstance(files, dict) or "SKILL.md" not in files:
            errors.append(f"{name} files must contain SKILL.md")
            continue
        for relative, digest in sorted(files.items()):
            pure = PurePosixPath(relative)
            if (
                pure.is_absolute()
                or ".." in pure.parts
                or "\\" in relative
                or pure.as_posix() != relative
            ):
                errors.append(f"{name} has invalid file path {relative}")
            if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
                errors.append(f"{name}/{relative} has invalid SHA-256")
    if root is not None:
        try:
            expected = generate_manifest(root)
        except LifecycleError as error:
            errors.append(str(error))
        else:
            if manifest != expected:
                errors.append("manifest is stale or does not match distributed skills")
    return errors


def manifest_path(root: Path) -> Path:
    return root / "skills" / Path(MANIFEST_RELATIVE_PATH)


def write_manifest(root: Path) -> bytes:
    data = canonical_json(generate_manifest(root))
    path = manifest_path(root)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
    return data


def check_manifest(root: Path) -> list[str]:
    path = manifest_path(root)
    if not path.is_file():
        return [f"missing generated manifest: {path}"]
    try:
        manifest = parse_json(path.read_bytes(), "generated manifest")
    except LifecycleError as error:
        return [str(error)]
    errors = validate_manifest(manifest, root)
    expected = canonical_json(generate_manifest(root))
    if path.read_bytes() != expected and "manifest is stale or does not match distributed skills" not in errors:
        errors.append("generated manifest bytes are not canonical")
    return errors


def _default_root() -> Path:
    candidate = Path(__file__).resolve().parents[3]
    if (candidate / "skills").is_dir() and (candidate / "release/metadata.json").is_file():
        return candidate
    return Path.cwd()


def installed_manifest() -> dict[str, Any]:
    path = Path(__file__).resolve().parent / "distribution-manifest.json"
    try:
        manifest = parse_json(path.read_bytes(), f"installed manifest {path}")
    except OSError as error:
        raise LifecycleError(f"cannot read installed manifest {path}: {error}") from error
    errors = validate_manifest(manifest)
    if errors:
        raise LifecycleError("; ".join(errors))
    return manifest


def _add_consumer_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--consumer-root", required=True, type=Path)
    selection = parser.add_mutually_exclusive_group(required=True)
    selection.add_argument(
        "--skills-root",
        type=Path,
        help="directory whose immediate children are harness-discovered skills",
    )
    selection.add_argument(
        "--skill-dir",
        action="append",
        type=Path,
        help="one harness-discovered skill directory; repeat for each skill",
    )
    parser.add_argument("--json", action="store_true", help="emit canonical JSON")


def _consumer_skill_dirs(args: argparse.Namespace) -> list[Path]:
    if args.skills_root:
        if not args.skills_root.is_dir():
            raise LifecycleError(f"skills root not found: {args.skills_root}")
        return sorted(path for path in args.skills_root.iterdir() if path.is_dir())
    return args.skill_dir


def _print_result(result: dict[str, Any], as_json: bool, success: str) -> None:
    if as_json:
        sys.stdout.buffer.write(canonical_json(result))
        return
    if result.get("errors"):
        print("Verification failed:")
        for error in result["errors"]:
            print(f"- {error}")
    else:
        print(success)
    if "release" in result:
        print(f"Release: {result['release']}")
    if "selected" in result:
        print("Selected: " + ", ".join(result["selected"]))
    if "closure" in result:
        print("Closure: " + ", ".join(result["closure"]))
    if "installed" in result:
        print("Installed: " + ", ".join(result["installed"]))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    for command in ("generate-release", "check-release"):
        subparser = subparsers.add_parser(command)
        subparser.add_argument("--root", type=Path, default=_default_root())
    show_parser = subparsers.add_parser("show-manifest")
    show_parser.add_argument("--json", action="store_true", help="emit canonical JSON")
    closure_parser = subparsers.add_parser("closure")
    closure_parser.add_argument("skills", nargs="+", help="user-selected workflow names")
    closure_parser.add_argument("--json", action="store_true", help="emit canonical JSON")
    inspect_parser = subparsers.add_parser("inspect")
    _add_consumer_arguments(inspect_parser)
    verify_parser = subparsers.add_parser("verify-consumer")
    _add_consumer_arguments(verify_parser)
    args = parser.parse_args()
    try:
        if args.command == "generate-release":
            data = write_manifest(args.root)
            print(f"Wrote {manifest_path(args.root)} ({len(data)} bytes).")
        elif args.command == "check-release":
            errors = check_manifest(args.root)
            if errors:
                raise LifecycleError("; ".join(errors))
            print("Verified canonical distribution manifest.")
        elif args.command == "show-manifest":
            manifest = installed_manifest()
            if args.json:
                sys.stdout.buffer.write(canonical_json(manifest))
            else:
                print(
                    f"Manifest {manifest['manifest_version']}: "
                    f"{manifest['distribution']['source']}@"
                    f"{manifest['distribution']['version']} "
                    f"({len(manifest['skills'])} skills)"
                )
        elif args.command == "closure":
            manifest = installed_manifest()
            selected = sorted(set(args.skills))
            try:
                required = sorted(dependency_closure(set(selected), manifest))
            except ValueError as error:
                raise LifecycleError(str(error)) from error
            result = {
                "closure": required,
                "release": manifest["distribution"]["version"],
                "selected": selected,
            }
            _print_result(result, args.json, "Calculated dependency closure.")
        elif args.command == "inspect":
            manifest = installed_manifest()
            skill_dirs = _consumer_skill_dirs(args)
            inspection = inspect_skills(args.consumer_root, skill_dirs, manifest)
            result = {
                "errors": sorted(set(inspection.errors)),
                "installed": sorted(inspection.installed),
                "ok": not inspection.errors,
                "release": manifest["distribution"]["version"],
            }
            _print_result(result, args.json, "Installed skills match the distribution manifest.")
            if inspection.errors:
                return 1
        else:
            manifest = installed_manifest()
            skill_dirs = _consumer_skill_dirs(args)
            verification = verify_consumer(args.consumer_root, skill_dirs, manifest)
            _print_result(
                verification.as_dict(),
                args.json,
                "Verified consumer installation.",
            )
            if verification.errors:
                return 1
    except LifecycleError as error:
        print(f"Lifecycle error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
