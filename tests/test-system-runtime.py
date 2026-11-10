#!/usr/bin/env python3
"""Source-bound regression tests for system runtime path validation."""

import os
import stat
import sys
import tempfile
from pathlib import Path
from types import SimpleNamespace


source = Path(sys.argv[1]).read_text(encoding="utf-8")
function = source.index("validate_system_install_paths() {")
start = source.index("\n", source.index("<<'PY'", function)) + 1
end = source.index("\nPY\n", start)
validator = compile(source[start:end], "<validate_system_install_paths>", "exec")

path_type = type(Path())
real_lstat = path_type.lstat


def current_umask():
    mask = os.umask(0)
    os.umask(mask)
    return mask


def fixture_lstat(fixture_root, bad_owner_paths):
    def lstat(path):
        entry = real_lstat(path)
        if path in fixture_root.parents:
            return SimpleNamespace(st_mode=stat.S_IFDIR | 0o755, st_uid=0)
        mode = 0o120777 if stat.S_ISLNK(entry.st_mode) else entry.st_mode
        uid = 1000 if path in bad_owner_paths else 0
        return SimpleNamespace(st_mode=mode, st_uid=uid)

    return lstat


def run(name, setup, expected, directory):
    previous_umask = os.umask(0o077)
    try:
        with tempfile.TemporaryDirectory(
            prefix="devops-runtime-paths-", dir=directory
        ) as fixture_root:
            base = Path(fixture_root).resolve()
            bad_owner_paths = set(setup(base) or ())
            previous_argv = sys.argv
            path_type.lstat = fixture_lstat(base, bad_owner_paths)
            sys.argv = ["validator", str(base)]
            try:
                try:
                    exec(validator, {"__name__": "__main__"})
                    outcome = "accept"
                except SystemExit:
                    outcome = "reject"
                assert outcome == expected, f"{name}: expected {expected}, got {outcome}"
            finally:
                path_type.lstat = real_lstat
                sys.argv = previous_argv
    finally:
        os.umask(previous_umask)
        assert current_umask() == previous_umask, f"{name}: umask was not restored"


def run_suite(directory, context):
    run(f"{context}: Linux 0777 lib64 symlink", normal_link, "accept", directory)
    run(f"{context}: non-root symlink", nonroot_link, "reject", directory)
    run(f"{context}: non-root target", nonroot_target, "reject", directory)
    run(f"{context}: writable target", writable_target, "reject", directory)
    run(f"{context}: writable target parent", writable_parent, "reject", directory)
    run(f"{context}: external directory", external_directory, "reject", directory)


def run_umask_matrix(outer_umask):
    previous_umask = os.umask(outer_umask)
    try:
        context = f"umask {outer_umask:04o}"
        run_suite(Path("/tmp"), f"{context} /tmp")
        with tempfile.TemporaryDirectory(
            prefix="devops-nonroot-parent-", dir="/tmp"
        ) as parent:
            run_suite(Path(parent), f"{context} nonroot parent")
        assert current_umask() == outer_umask, f"{context}: outer umask changed"
    finally:
        os.umask(previous_umask)
        assert current_umask() == previous_umask, f"{outer_umask:04o}: umask was not restored"


def normal_link(base):
    (base / "runtime/lib").mkdir(parents=True)
    (base / "runtime/lib64").symlink_to("lib")


def nonroot_link(base):
    (base / "runtime/lib").mkdir(parents=True)
    link = base / "runtime/nonroot-link"
    link.symlink_to("lib")
    return {link}


def nonroot_target(base):
    target = base / "runtime/nonroot-target"
    target.mkdir(parents=True)
    (base / "runtime/lib64").symlink_to(target.name)
    return {target}


def writable_target(base):
    target = base / "runtime/lib"
    target.mkdir(parents=True)
    target.chmod(0o777)
    (base / "runtime/lib64").symlink_to(target.name)


def writable_parent(base):
    parent = base / "runtime/writable-parent"
    target = parent / "lib"
    target.mkdir(parents=True)
    parent.chmod(0o777)
    (base / "runtime/lib64").symlink_to(target.relative_to(base / "runtime"))


def external_directory(base):
    (base / "runtime").mkdir()
    (base / "external").mkdir()
    (base / "runtime/lib64").symlink_to(base / "external")


initial_umask = current_umask()
run_umask_matrix(0o002)
run_umask_matrix(0o022)
assert current_umask() == initial_umask, "test process umask was not restored"

print("system runtime path regression passed")
