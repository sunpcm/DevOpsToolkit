#!/usr/bin/env python3
"""Read-only machine-readable entrypoint contract tests."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
EXPECTED_PLAYBOOKS = {
    "wsl-bootstrap": ("wsl", "wsl-bootstrap.yml"),
    "ubuntu-bootstrap": ("ubuntu", "ubuntu-bootstrap.yml"),
    "ubuntu-ssh-finalize": ("ubuntu", "ubuntu-ssh-finalize.yml"),
    "user-only": ("user-only", "user-only.yml"),
    "user-only-remove": ("user-only", "user-only-remove.yml"),
}


def read_json(*command: str) -> dict:
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, check=True)
    assert not result.stderr, result.stderr
    return json.loads(result.stdout)


installer = read_json("bash", str(ROOT / "install.sh"), "--capabilities-json")
wizard = read_json(str(ROOT / "bin/devops-toolkit"), "--capabilities-json")
lock = json.loads((ROOT / "ansible/collections.lock.json").read_text(encoding="utf-8"))

assert installer["schema"] == wizard["schema"] == 1
assert installer["component"] == "installer"
assert installer["version"] is None  # Standalone script is not an installed Release.
assert installer["installation_modes"] == ["user", "system"]
assert installer["verification"] == ["sha256", "sigstore-identity"]
assert installer["ansible_core"] == wizard["ansible_core"] == "2.21.4"
assert installer["controller"] == wizard["controller"]
assert wizard["component"] == "wizard"
assert wizard["version"] == "development"
assert wizard["entrypoint"] is None
assert wizard["collections"] == {
    item["name"]: item["version"] for item in lock["collections"]
}
assert set(wizard["playbooks"]) == set(EXPECTED_PLAYBOOKS)
assert wizard["targets"]["wsl"]["ubuntu_versions"] == ["24.04"]
assert wizard["targets"]["ubuntu"]["versions"] == ["22.04", "24.04"]

for name, (mode, filename) in EXPECTED_PLAYBOOKS.items():
    assert (ROOT / "ansible/playbooks" / filename).is_file()
    document = read_json(str(ROOT / "bin" / name), "--capabilities-json")
    assert document == {
        **wizard,
        "component": "playbook",
        "entrypoint": name,
    }
    assert document["playbooks"][name] == {"mode": mode, "playbook": filename}

for command in (
    ("bash", str(ROOT / "install.sh"), "--capabilities-json", "--no-run"),
    ("bash", str(ROOT / "install.sh"), "--user", "--capabilities-json"),
    (str(ROOT / "bin/devops-toolkit"), "--capabilities-json", "--entrypoint", "bad"),
    (str(ROOT / "bin/user-only"), "--capabilities-json", "extra"),
):
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
    assert result.returncode != 0, (command, result.stdout, result.stderr)

print("机器可读能力输出测试通过。")
