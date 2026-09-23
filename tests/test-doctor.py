#!/usr/bin/env python3
"""Doctor remains read-only and refuses untrusted SSH targets."""

from __future__ import annotations

import argparse
import json
import runpy
import stat
import subprocess
import tempfile
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parent.parent
doctor = runpy.run_path(str(ROOT / "bin/devops-toolkit-doctor"))
compile(doctor["REMOTE_SCRIPT"], "<doctor-remote-preflight>", "exec")

ssh_config = doctor["ssh_config_check"]()
assert ssh_config["status"] == "pass", ssh_config

with tempfile.TemporaryDirectory() as temporary:
    empty_root = Path(temporary) / "empty"
    valid_root = Path(temporary) / "valid"
    lock = json.loads((ROOT / "ansible/collections.lock.json").read_text())
    for item in lock["collections"]:
        namespace, name = item["name"].split(".", 1)
        manifest = (
            valid_root / "ansible_collections" / namespace / name / "MANIFEST.json"
        )
        manifest.parent.mkdir(parents=True, exist_ok=True)
        manifest.write_text(
            json.dumps({"collection_info": {"version": item["version"]}}),
            encoding="utf-8",
        )
    with mock.patch.dict(
        "os.environ",
        {"ANSIBLE_COLLECTIONS_PATH": f"{empty_root}:{valid_root}"},
    ):
        assert doctor["collections_check"]()["status"] == "pass"
    with mock.patch.dict("os.environ", {"ANSIBLE_COLLECTIONS_PATH": str(empty_root)}):
        assert doctor["collections_check"]()["status"] == "fail"

command = doctor["ssh_command"](
    "host.example", "operator", 2222, Path("/tmp/private-key"), Path("/tmp/known_hosts")
)
assert "-F" in command and "/dev/null" in command
assert "StrictHostKeyChecking=yes" in command
assert "BatchMode=yes" in command
assert "ControlMaster=no" in command
assert "UpdateHostKeys=no" in command
assert "IdentitiesOnly=yes" in command
assert "StrictHostKeyChecking=no" not in command
assert command[-2:] == ["host.example", "python3 -"]

with tempfile.TemporaryDirectory() as temporary:
    known_hosts = Path(temporary) / "known_hosts"
    known_hosts.write_text(
        "host.example ssh-ed25519 test-placeholder\n", encoding="utf-8"
    )
    known_hosts.chmod(0o600)
    identity = Path(temporary) / "identity"
    identity.write_text("not-a-real-key\n", encoding="utf-8")
    identity.chmod(0o600)
    args = argparse.Namespace(
        host="host.example",
        user="operator",
        port=2222,
        identity=identity,
        known_hosts=known_hosts,
        mode="ubuntu",
        no_network=True,
    )
    report = {
        "checks": [
            {"name": "target_os", "status": "pass", "detail": "ubuntu 24.04 x86_64"}
        ]
    }
    completed = subprocess.CompletedProcess(command, 0, json.dumps(report), "")
    with mock.patch.object(doctor["subprocess"], "run", return_value=completed) as run:
        checks = doctor["remote_checks"](args)
    assert checks[0]["status"] == "pass"
    assert checks[1:] == report["checks"]
    assert run.call_count == 1
    assert run.call_args.kwargs["input"] == doctor["REMOTE_SCRIPT"]
    assert run.call_args.args[0] == doctor["ssh_command"](
        "host.example", "operator", 2222, identity, known_hosts
    )

    known_hosts.chmod(0o666)
    with mock.patch.object(doctor["subprocess"], "run") as run:
        checks = doctor["remote_checks"](args)
    assert checks[0]["status"] == "fail"
    run.assert_not_called()
    assert stat.S_IMODE(known_hosts.stat().st_mode) & 0o022

    known_hosts.chmod(0o600)
    args.host = "-oProxyCommand=bad"
    with mock.patch.object(doctor["subprocess"], "run") as run:
        checks = doctor["remote_checks"](args)
    assert checks[0]["status"] == "fail"
    run.assert_not_called()

help_result = subprocess.run(
    [str(ROOT / "bin/devops-toolkit"), "doctor", "--help"],
    capture_output=True,
    text=True,
    check=True,
)
assert "--known-hosts" in help_result.stdout
assert "--no-network" in help_result.stdout

local_result = subprocess.run(
    [str(ROOT / "bin/devops-toolkit"), "doctor", "--no-network", "--json"],
    capture_output=True,
    text=True,
)
local_report = json.loads(local_result.stdout)
assert local_report["schema"] == 1
assert local_report["result"] in {"pass", "warn", "fail"}
assert {item["name"] for item in local_report["checks"]} >= {
    "controller_platform",
    "controller_python",
    "ansible_runtime",
    "collections",
    "ssh_config",
    "controller_disk",
    "controller_network",
}
assert not any(item["name"].startswith("target_") for item in local_report["checks"])
assert local_result.returncode == (1 if local_report["result"] == "fail" else 0)

missing_user = subprocess.run(
    [str(ROOT / "bin/devops-toolkit"), "doctor", "--host", "host.example"],
    capture_output=True,
    text=True,
)
assert missing_user.returncode == 2

print("只读 doctor 与严格 SSH 边界测试通过。")
