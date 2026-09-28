#!/usr/bin/env python3
"""Unit tests for scripts/verify-collection-lock.py."""

from __future__ import annotations

import importlib.util
import json
import sys
import tarfile
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT_PATH = ROOT / "scripts" / "verify-collection-lock.py"

spec = importlib.util.spec_from_file_location("verify_collection_lock", SCRIPT_PATH)
assert spec is not None and spec.loader is not None
vcl = importlib.util.module_from_spec(spec)
sys.modules["verify_collection_lock"] = vcl
spec.loader.exec_module(vcl)

load_lock = vcl.load_lock
requirements_text = vcl.requirements_text
marker_text = vcl.marker_text
artifact_manifest = vcl.artifact_manifest
validate_artifacts = vcl.validate_artifacts
validate_installed = vcl.validate_installed
main = vcl.main


def test_load_lock_success() -> None:
    valid_data = {
        "schema": 1,
        "collections": [
            {
                "name": "community.general",
                "version": "8.3.0",
                "artifact": "community-general-8.3.0.tar.gz",
                "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
            },
            {
                "name": "ansible.posix",
                "version": "1.5.4",
                "artifact": "ansible-posix-1.5.4.tar.gz",
                "sha256": "abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789",
            },
        ],
    }
    with tempfile.TemporaryDirectory() as tmpdir:
        lock_path = Path(tmpdir) / "collections.lock.json"
        lock_path.write_text(json.dumps(valid_data), encoding="utf-8")
        entries = load_lock(lock_path)
        assert len(entries) == 2
        assert entries[0]["name"] == "ansible.posix"
        assert entries[1]["name"] == "community.general"


def test_load_lock_type_error_not_dict() -> None:
    with tempfile.TemporaryDirectory() as tmpdir:
        lock_path = Path(tmpdir) / "lock.json"
        lock_path.write_text("[1, 2, 3]", encoding="utf-8")
        try:
            load_lock(lock_path)
            assert False, "Should have raised TypeError"
        except TypeError as exc:
            assert "collection lock must be an object" in str(exc)


def test_load_lock_invalid_schema() -> None:
    invalid_schemas = [
        {"schema": 2, "collections": []},
        {"collections": []},
        {"schema": 1, "collections": "not-a-list"},
    ]
    for data in invalid_schemas:
        with tempfile.TemporaryDirectory() as tmpdir:
            lock_path = Path(tmpdir) / "lock.json"
            lock_path.write_text(json.dumps(data), encoding="utf-8")
            try:
                load_lock(lock_path)
                assert False, f"Should have raised ValueError for {data}"
            except ValueError as exc:
                assert "unsupported collection lock schema" in str(exc)


def test_load_lock_entry_not_dict() -> None:
    data = {"schema": 1, "collections": ["not-a-dict"]}
    with tempfile.TemporaryDirectory() as tmpdir:
        lock_path = Path(tmpdir) / "lock.json"
        lock_path.write_text(json.dumps(data), encoding="utf-8")
        try:
            load_lock(lock_path)
            assert False, "Should have raised TypeError"
        except TypeError as exc:
            assert "collection lock entry must be an object" in str(exc)


def test_load_lock_entry_invalid_keys_or_types() -> None:
    invalid_entries = [
        {"name": "ansible.posix", "version": "1.5.4", "artifact": "ansible-posix-1.5.4.tar.gz"},  # missing sha256
        {
            "name": "ansible.posix",
            "version": "1.5.4",
            "artifact": "ansible-posix-1.5.4.tar.gz",
            "sha256": "a" * 64,
            "extra": "key",
        },  # extra key
        {
            "name": "ansible.posix",
            "version": 123,
            "artifact": "ansible-posix-1.5.4.tar.gz",
            "sha256": "a" * 64,
        },  # non-string version
    ]
    for entry in invalid_entries:
        data = {"schema": 1, "collections": [entry]}
        with tempfile.TemporaryDirectory() as tmpdir:
            lock_path = Path(tmpdir) / "lock.json"
            lock_path.write_text(json.dumps(data), encoding="utf-8")
            try:
                load_lock(lock_path)
                assert False, f"Should have raised TypeError for {entry}"
            except TypeError as exc:
                assert "collection lock entry must contain only string lock fields" in str(exc)


def test_load_lock_invalid_entry_values() -> None:
    sha = "a" * 64
    invalid_entries = [
        # Invalid collection name format (no namespace dot)
        {"name": "invalidname", "version": "1.0.0", "artifact": "invalidname-1.0.0.tar.gz", "sha256": sha},
        # Invalid version format
        {"name": "ns.coll", "version": "invalid_ver!", "artifact": "ns-coll-invalid_ver!.tar.gz", "sha256": sha},
        # Artifact filename mismatch
        {"name": "ns.coll", "version": "1.0.0", "artifact": "wrong-filename.tar.gz", "sha256": sha},
        # Invalid sha256 (wrong length)
        {"name": "ns.coll", "version": "1.0.0", "artifact": "ns-coll-1.0.0.tar.gz", "sha256": "short"},
    ]
    for entry in invalid_entries:
        data = {"schema": 1, "collections": [entry]}
        with tempfile.TemporaryDirectory() as tmpdir:
            lock_path = Path(tmpdir) / "lock.json"
            lock_path.write_text(json.dumps(data), encoding="utf-8")
            try:
                load_lock(lock_path)
                assert False, f"Should have raised ValueError for {entry}"
            except ValueError as exc:
                assert "invalid collection lock entry" in str(exc)


def test_load_lock_duplicate_entry() -> None:
    sha = "a" * 64
    entry = {"name": "ns.coll", "version": "1.0.0", "artifact": "ns-coll-1.0.0.tar.gz", "sha256": sha}
    data = {"schema": 1, "collections": [entry, entry]}
    with tempfile.TemporaryDirectory() as tmpdir:
        lock_path = Path(tmpdir) / "lock.json"
        lock_path.write_text(json.dumps(data), encoding="utf-8")
        try:
            load_lock(lock_path)
            assert False, "Should have raised ValueError for duplicate entry"
        except ValueError as exc:
            assert "invalid collection lock entry" in str(exc)


def test_load_lock_empty_collections() -> None:
    data = {"schema": 1, "collections": []}
    with tempfile.TemporaryDirectory() as tmpdir:
        lock_path = Path(tmpdir) / "lock.json"
        lock_path.write_text(json.dumps(data), encoding="utf-8")
        try:
            load_lock(lock_path)
            assert False, "Should have raised ValueError for empty collections"
        except ValueError as exc:
            assert "collection lock is empty" in str(exc)


def test_real_collection_lock_loads_successfully() -> None:
    real_lock_path = ROOT / "ansible" / "collections.lock.json"
    entries = load_lock(real_lock_path)
    assert len(entries) > 0
    req_text = requirements_text(entries)
    assert "collections:" in req_text
    mark_text = marker_text(real_lock_path, entries)
    assert "lock-sha256=" in mark_text


def test_artifact_manifest_errors_and_success() -> None:
    with tempfile.TemporaryDirectory() as tmpdir:
        dir_path = Path(tmpdir)
        archive_path = dir_path / "test-collection-1.0.0.tar.gz"

        # Missing MANIFEST.json
        with tarfile.open(archive_path, "w:gz") as tar:
            info = tarfile.TarInfo(name="other.txt")
            info.size = 0
            tar.addfile(info)
        try:
            artifact_manifest(archive_path)
            assert False, "Should have raised ValueError"
        except ValueError as exc:
            assert "missing unique MANIFEST.json" in str(exc)

        # Invalid MANIFEST.json format
        manifest_data = json.dumps({"invalid": "manifest"}).encode("utf-8")
        with tarfile.open(archive_path, "w:gz") as tar:
            info = tarfile.TarInfo(name="MANIFEST.json")
            info.size = len(manifest_data)
            tar.addfile(info, fileobj=import_bytes_io(manifest_data))
        try:
            artifact_manifest(archive_path)
            assert False, "Should have raised TypeError"
        except TypeError as exc:
            assert "invalid MANIFEST.json" in str(exc)

        # Valid MANIFEST.json
        valid_manifest = json.dumps(
            {"collection_info": {"namespace": "ns", "name": "coll", "version": "1.0.0"}}
        ).encode("utf-8")
        with tarfile.open(archive_path, "w:gz") as tar:
            info = tarfile.TarInfo(name="MANIFEST.json")
            info.size = len(valid_manifest)
            tar.addfile(info, fileobj=import_bytes_io(valid_manifest))

        manifest = artifact_manifest(archive_path)
        assert manifest["collection_info"]["name"] == "coll"


def import_bytes_io(data: bytes):
    import io

    return io.BytesIO(data)


def test_main_cli() -> None:
    real_lock = str(ROOT / "ansible" / "collections.lock.json")
    real_req = str(ROOT / "ansible" / "requirements.yml")
    sys_argv_backup = sys.argv
    try:
        sys.argv = ["verify-collection-lock.py", "--lock", real_lock, "--requirements", real_req]
        ret = main()
        assert ret == 0, f"main() returned {ret}"
    finally:
        sys.argv = sys_argv_backup


if __name__ == "__main__":
    test_load_lock_success()
    test_load_lock_type_error_not_dict()
    test_load_lock_invalid_schema()
    test_load_lock_entry_not_dict()
    test_load_lock_entry_invalid_keys_or_types()
    test_load_lock_invalid_entry_values()
    test_load_lock_duplicate_entry()
    test_load_lock_empty_collections()
    test_real_collection_lock_loads_successfully()
    test_artifact_manifest_errors_and_success()
    test_main_cli()
    print("Collection lock unit tests passed.")
