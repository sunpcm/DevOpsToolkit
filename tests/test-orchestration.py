#!/usr/bin/env python3
"""Fast orchestration checks across wizard and playbook/role combinations."""

from __future__ import annotations

import json
import os
import runpy
import stat
import subprocess
import tempfile
from pathlib import Path
from types import SimpleNamespace
from typing import Any


ROOT_DIR = Path(__file__).resolve().parent.parent
wizard = runpy.run_path(str(ROOT_DIR / "bin" / "devops-toolkit"))


def test_wizard_executes_prepare_and_finalize() -> None:
    globals_ = wizard["run_wizard"].__globals__
    originals = {
        name: globals_[name]
        for name in (
            "choose",
            "confirm",
            "collect_ubuntu",
            "load_wizard_state",
            "save_wizard_state",
            "subprocess",
        )
    }
    calls: list[dict[str, Any]] = []
    saved_states: list[dict[str, Any]] = []

    def collect_ubuntu(_defaults: dict[str, Any]) -> tuple[Any, ...]:
        variables = {
            "target_user": "developer",
            "target_password_hash": "$6$must-not-persist",
            "target_authorized_keys": ["ssh-ed25519 AAAATEST"],
            "configure_node": False,
            "configure_go": False,
            "configure_ssh": True,
            "ssh_wizard_auto_finalize": True,
            "ssh_transition_host": "192.0.2.10",
            "ssh_port": 2222,
        }
        inventory = (
            "[ubuntu_servers]\n"
            "wizard_target ansible_host=192.0.2.10 ansible_user=root\n"
        )
        return (
            ROOT_DIR / "ansible/playbooks/ubuntu-bootstrap.yml",
            inventory,
            variables,
            ["--private-key", "/tmp/test-key"],
            {"模式": "test"},
        )

    def fake_run(command: list[str], *, env: dict[str, str], check: bool) -> SimpleNamespace:
        assert check is False
        vars_path = Path(command[command.index("-e") + 1].removeprefix("@"))
        inventory_path = Path(command[command.index("-i") + 1])
        assert stat.S_IMODE(vars_path.stat().st_mode) == 0o600
        assert stat.S_IMODE(inventory_path.stat().st_mode) == 0o600
        calls.append(
            {
                "command": list(command),
                "variables": json.loads(vars_path.read_text(encoding="utf-8")),
                "inventory": inventory_path.read_text(encoding="utf-8"),
                "environment": env,
            }
        )
        return SimpleNamespace(returncode=0)

    fake_subprocess = SimpleNamespace(run=fake_run)
    try:
        globals_["choose"] = lambda *_args, **_kwargs: "ubuntu"
        globals_["confirm"] = lambda *_args, **_kwargs: True
        globals_["collect_ubuntu"] = collect_ubuntu
        globals_["load_wizard_state"] = lambda: {"schema": 1, "modes": {}}
        globals_["save_wizard_state"] = lambda state: (
            saved_states.append(json.loads(json.dumps(state)))
            or Path("/tmp/test-wizard-state.json")
        )
        globals_["subprocess"] = fake_subprocess
        assert wizard["run_wizard"]() == 0
    finally:
        globals_.update(originals)

    assert len(calls) == 2
    assert calls[0]["command"][0] == str(ROOT_DIR / "bin/ansible-playbook")
    assert any(item.endswith("ubuntu-bootstrap.yml") for item in calls[0]["command"])
    assert any(item.endswith("ubuntu-ssh-finalize.yml") for item in calls[1]["command"])
    assert calls[1]["variables"]["ssh_finalize_key_verified"] is True
    assert "ansible_user=developer" in calls[1]["inventory"]
    assert "ansible_port=2222" in calls[1]["inventory"]
    assert calls[0]["environment"]["ANSIBLE_CONFIG"].endswith("ansible/ansible.cfg")
    saved = json.dumps(saved_states)
    assert "must-not-persist" not in saved
    assert "target_password_hash" not in saved
    assert "target_authorized_keys" not in saved


def test_playbook_role_matrix() -> None:
    cases = [
        (
            "wsl-bootstrap.yml",
            {
                "target_user": "developer",
                "install_linuxbrew": False,
                "configure_shell": False,
                "configure_node": True,
                "configure_go": True,
            },
            "user_profile : Validate user-profile identity and path",
        ),
        (
            "ubuntu-bootstrap.yml",
            {
                "target_user": "developer",
                "install_docker": False,
                "install_nginx": False,
                "enable_firewall": False,
                "configure_ssh": False,
            },
            "account_create : Require a login method for a new target account",
        ),
        (
            "ubuntu-bootstrap.yml",
            {
                "target_user": "developer",
                "install_docker": True,
                "install_nginx": True,
                "enable_firewall": True,
                "configure_ssh": True,
            },
            "ssh_security : Prepare SSH with both trusted and desired listener ports",
        ),
        (
            "user-only.yml",
            {
                "configure_shell": False,
                "install_oh_my_zsh": False,
                "configure_uv": True,
                "configure_node": True,
                "configure_go": True,
                "configure_homebrew_environment": False,
            },
            "Resolve dependencies required by enabled user modules",
        ),
    ]
    with tempfile.TemporaryDirectory(prefix="devops-toolkit-role-matrix-") as directory:
        temporary = Path(directory)
        inventory = temporary / "inventory.ini"
        inventory.write_text(
            "[ubuntu_servers]\n"
            "ubuntu-test ansible_connection=local\n"
            "[user_only]\n"
            "user-test ansible_connection=local\n",
            encoding="utf-8",
        )
        environment = os.environ.copy()
        environment["ANSIBLE_CONFIG"] = str(ROOT_DIR / "ansible/ansible.cfg")
        environment["ANSIBLE_LOCAL_TEMP"] = str(temporary / "ansible-local")
        for playbook_name, variables, expected_task in cases:
            result = subprocess.run(
                [
                    "ansible-playbook",
                    "-i",
                    str(inventory),
                    str(ROOT_DIR / "ansible/playbooks" / playbook_name),
                    "--list-tasks",
                    "-e",
                    json.dumps(variables),
                ],
                env=environment,
                check=False,
                capture_output=True,
                text=True,
            )
            assert result.returncode == 0, result.stdout + result.stderr
            assert expected_task in result.stdout, result.stdout


test_wizard_executes_prepare_and_finalize()
test_playbook_role_matrix()
print("向导编排与 Playbook/role 组合测试通过。")
