#!/usr/bin/env python3
"""Validate the single-source Ansible collection lock and its artifacts."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import tarfile
from pathlib import Path
from typing import Any

NAME_RE = re.compile(r"^[a-z0-9_]+\.[a-z0-9_]+$")
VERSION_RE = re.compile(r"^[0-9]+(?:\.[0-9]+)+(?:[-+._a-zA-Z0-9]*)?$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


def load_lock(path: Path) -> list[dict[str, str]]:
    raw_data: Any = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(raw_data, dict):
        raise TypeError("collection lock must be an object")
    data: dict[str, Any] = raw_data
    if data.get("schema") != 1 or not isinstance(data.get("collections"), list):
        raise ValueError("unsupported collection lock schema")
    result: list[dict[str, str]] = []
    seen: set[str] = set()
    for raw in data["collections"]:
        if not isinstance(raw, dict):
            raise TypeError("collection lock entry must be an object")
        required_keys = {"name", "version", "artifact", "sha256"}
        if set(raw) != required_keys or not all(isinstance(raw[key], str) for key in required_keys):
            raise TypeError("collection lock entry must contain only string lock fields")
        entry = {key: raw[key] for key in required_keys}
        namespace, separator, collection = entry["name"].partition(".")
        expected_artifact = f"{namespace}-{collection}-{entry['version']}.tar.gz"
        if (
            not separator
            or not NAME_RE.fullmatch(entry["name"])
            or not VERSION_RE.fullmatch(entry["version"])
            or entry["artifact"] != expected_artifact
            or not SHA256_RE.fullmatch(entry["sha256"])
            or entry["name"] in seen
        ):
            raise ValueError(f"invalid collection lock entry: {entry}")
        seen.add(entry["name"])
        result.append(entry)
    if not result:
        raise ValueError("collection lock is empty")
    return sorted(result, key=lambda item: item["name"])


def requirements_text(entries: list[dict[str, str]]) -> str:
    lines = ["---", "collections:"]
    for entry in entries:
        lines.extend(
            [
                f"  - name: {entry['name']}",
                f"    version: \"{entry['version']}\"",
            ]
        )
    return "\n".join(lines) + "\n"


def marker_text(lock_path: Path, entries: list[dict[str, str]]) -> str:
    digest = hashlib.sha256(lock_path.read_bytes()).hexdigest()
    lines = [f"lock-sha256={digest}"]
    lines.extend(f"{entry['name']}={entry['version']}" for entry in entries)
    return "\n".join(lines) + "\n"


def artifact_manifest(archive: Path) -> dict[str, Any]:
    with tarfile.open(archive, "r:gz") as bundle:
        members = [member for member in bundle.getmembers() if member.name == "MANIFEST.json"]
        if len(members) != 1 or not members[0].isfile():
            raise ValueError(f"{archive.name}: missing unique MANIFEST.json")
        handle = bundle.extractfile(members[0])
        if handle is None:
            raise ValueError(f"{archive.name}: cannot read MANIFEST.json")
        manifest: Any = json.loads(handle.read().decode("utf-8"))
        if not isinstance(manifest, dict) or not isinstance(manifest.get("collection_info"), dict):
            raise TypeError(f"{archive.name}: invalid MANIFEST.json")
        return manifest


def validate_artifacts(directory: Path, entries: list[dict[str, str]]) -> None:
    expected_files = {entry["artifact"] for entry in entries}
    actual_files = {path.name for path in directory.glob("*.tar.gz")}
    if actual_files != expected_files:
        raise ValueError(
            f"collection artifact set mismatch: expected {sorted(expected_files)}, got {sorted(actual_files)}"
        )
    for entry in entries:
        archive = directory / entry["artifact"]
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        if digest != entry["sha256"]:
            raise ValueError(f"{archive.name}: sha256 mismatch")
        info = artifact_manifest(archive)["collection_info"]
        actual_name = f"{info['namespace']}.{info['name']}"
        if actual_name != entry["name"] or str(info["version"]) != entry["version"]:
            raise ValueError(f"{archive.name}: manifest identity mismatch")


def validate_installed(directory: Path, entries: list[dict[str, str]]) -> None:
    expected = {entry["name"]: entry["version"] for entry in entries}
    actual: dict[str, str] = {}
    root = directory / "ansible_collections"
    if not root.is_dir():
        raise ValueError(f"installed collection root is missing: {root}")
    for manifest in root.glob("*/*/MANIFEST.json"):
        info = json.loads(manifest.read_text(encoding="utf-8"))["collection_info"]
        name = f"{info['namespace']}.{info['name']}"
        if name in actual:
            raise ValueError(f"duplicate installed collection: {name}")
        actual[name] = str(info["version"])
    if actual != expected:
        raise ValueError(f"installed collection mismatch: expected {expected}, got {actual}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--lock", type=Path, required=True)
    parser.add_argument("--requirements", type=Path)
    parser.add_argument("--artifacts", type=Path)
    parser.add_argument("--installed", type=Path)
    parser.add_argument("--write-marker", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        entries = load_lock(args.lock)
        if args.requirements and args.requirements.read_text(encoding="utf-8") != requirements_text(entries):
            raise ValueError("requirements.yml is not generated from the collection lock")
        if args.artifacts:
            validate_artifacts(args.artifacts, entries)
        if args.installed:
            validate_installed(args.installed, entries)
        if args.write_marker:
            args.write_marker.write_text(marker_text(args.lock, entries), encoding="utf-8")
    except (KeyError, OSError, TypeError, ValueError, json.JSONDecodeError, tarfile.TarError) as exc:
        print(f"collection lock verification failed: {exc}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
