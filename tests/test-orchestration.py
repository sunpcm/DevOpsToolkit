#!/usr/bin/env python3
"""Fast orchestration checks across wizard and playbook/role combinations."""

from __future__ import annotations

import json
import os
import runpy
import shutil
import stat
import subprocess
import tempfile
from pathlib import Path
from types import SimpleNamespace
from typing import Any

import yaml


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


def test_platform_guards_before_system_changes() -> None:
    playbook_dir = ROOT_DIR / "ansible/playbooks"
    cases = {
        "wsl-bootstrap.yml": ("24.04",),
        "ubuntu-bootstrap.yml": ("22.04", "24.04"),
        "ubuntu-ssh-finalize.yml": ("22.04", "24.04"),
        "user-only.yml": ("22.04", "24.04"),
    }
    with tempfile.TemporaryDirectory(prefix="devops-toolkit-platform-") as directory:
        temporary = Path(directory)
        environment = os.environ.copy()
        environment["ANSIBLE_CONFIG"] = str(ROOT_DIR / "ansible/ansible.cfg")
        environment["ANSIBLE_LOCAL_TEMP"] = str(temporary / "ansible-local")

        def check(task: dict[str, Any], facts: dict[str, str], succeeds: bool) -> None:
            isolated = dict(task)
            isolated.pop("when", None)
            payload = [{"hosts": "localhost", "gather_facts": False, "tasks": [isolated]}]
            path = temporary / "guard.yml"
            path.write_text(yaml.safe_dump(payload), encoding="utf-8")
            result = subprocess.run(
                [
                    "ansible-playbook",
                    "-i",
                    "localhost,",
                    "-c",
                    "local",
                    str(path),
                    "-e",
                    json.dumps({"ansible_facts": facts, "wsl_kernel_release": facts}),
                ],
                env=environment,
                check=False,
                capture_output=True,
                text=True,
            )
            assert (result.returncode == 0) is succeeds, result.stdout + result.stderr

        for playbook_name, supported_versions in cases.items():
            playbook = yaml.safe_load((playbook_dir / playbook_name).read_text(encoding="utf-8"))
            pre_tasks = playbook[0]["pre_tasks"]
            guard_index = next(
                index for index, task in enumerate(pre_tasks)
                if "supported" in task["name"].lower()
            )
            assert guard_index <= 1, playbook_name
            guard = pre_tasks[guard_index]
            assert "ansible.builtin.assert" in guard, playbook_name
            if playbook_name == "user-only.yml":
                assert guard["when"] == "user_only_allow_system_dependencies | bool"
            for version in supported_versions:
                for architecture in ("x86_64", "aarch64"):
                    check(
                        guard,
                        {
                            "distribution": "Ubuntu",
                            "distribution_version": version,
                            "architecture": architecture,
                        },
                        True,
                    )
            for facts in (
                {"distribution": "Debian", "distribution_version": "24.04", "architecture": "x86_64"},
                {"distribution": "Ubuntu", "distribution_version": "20.04", "architecture": "x86_64"},
                {"distribution": "Ubuntu", "distribution_version": "24.04", "architecture": "ppc64le"},
            ):
                check(guard, facts, False)

        wsl = yaml.safe_load((playbook_dir / "wsl-bootstrap.yml").read_text(encoding="utf-8"))
        pre_tasks = wsl[0]["pre_tasks"]
        assert pre_tasks[2]["ansible.builtin.command"] == "cat /proc/sys/kernel/osrelease"
        assert pre_tasks[2]["changed_when"] is False
        marker_guard = pre_tasks[3]
        for marker, succeeds in (
            ("5.15.167.4-microsoft-standard-WSL2", True),
            ("4.4.0-19041-Microsoft", False),
            ("6.8.0-generic", False),
        ):
            check(marker_guard, {"stdout": marker}, succeeds)


def test_user_only_rechecks_after_reported_dependency_install() -> None:
    """A successful apt result must not mask a still-missing command."""
    playbook = yaml.safe_load(
        (ROOT_DIR / "ansible/playbooks/user-only.yml").read_text(encoding="utf-8")
    )[0]
    pre_tasks = playbook["pre_tasks"]
    first = next(
        index for index, task in enumerate(pre_tasks)
        if task["name"] == "Check required user-profile commands"
    )
    assert pre_tasks[-1]["name"] == "Stop strict user-only mode when dependencies are missing"
    assert playbook["roles"][0]["role"] == "user_profile"

    missing_command = "devops_toolkit_missing_recheck_fixture"
    assert shutil.which(missing_command) is None
    isolated_tasks = []
    for task in pre_tasks[first:]:
        if task["name"] == "Install only whitelisted user-profile dependencies":
            simulated = {key: value for key, value in task.items() if key != "become"}
            simulated.pop("ansible.builtin.apt")
            simulated["ansible.builtin.debug"] = {"msg": "simulated apt success"}
            isolated_tasks.append(simulated)
        else:
            isolated_tasks.append(task)

    with tempfile.TemporaryDirectory(prefix="devops-toolkit-recheck-") as directory:
        temporary = Path(directory)
        test_playbook = temporary / "recheck.yml"
        test_playbook.write_text(
            yaml.safe_dump(
                [{
                    "hosts": "localhost",
                    "gather_facts": False,
                    "vars": {
                        "user_only_required_commands": [missing_command],
                        "user_only_dependency_allowlist": ["simulated-package"],
                        "user_only_allow_system_dependencies": True,
                    },
                    "tasks": isolated_tasks,
                }],
                sort_keys=False,
            ),
            encoding="utf-8",
        )
        environment = os.environ.copy()
        environment["ANSIBLE_CONFIG"] = str(ROOT_DIR / "ansible/ansible.cfg")
        environment["ANSIBLE_LOCAL_TEMP"] = str(temporary / "ansible-local")
        result = subprocess.run(
            ["ansible-playbook", "-i", "localhost,", "-c", "local", str(test_playbook)],
            env=environment,
            check=False,
            capture_output=True,
            text=True,
        )
        output = result.stdout + result.stderr
        assert result.returncode != 0, output
        assert "simulated apt success" in output, output
        assert "Missing commands after dependency convergence" in output, output
        assert missing_command in output, output
        assert "user_profile" not in output, output


def test_finalize_rejects_unverified_connection_before_guard_write() -> None:
    playbook = yaml.safe_load(
        (ROOT_DIR / "ansible/playbooks/ubuntu-ssh-finalize.yml").read_text(encoding="utf-8")
    )[0]
    preflight = next(
        task for task in playbook["pre_tasks"]
        if task["name"] == "Require the verified ordinary-user connection before firewall writes"
    )
    conditions = preflight["ansible.builtin.assert"]["that"]
    assert "ansible_facts['user_id'] == target_user" in conditions
    assert "(ansible_port | default(22) | int) == (ssh_port | int)" in conditions
    assert "not (disable_password_auth | bool) or (ssh_finalize_key_verified | bool)" in conditions
    guard = playbook["tasks"][0]["ansible.builtin.include_role"]
    assert guard == {"name": "firewall", "tasks_from": "ssh-finalize-guard-present"}


test_wizard_executes_prepare_and_finalize()
test_playbook_role_matrix()
test_platform_guards_before_system_changes()
test_user_only_rechecks_after_reported_dependency_install()
test_finalize_rejects_unverified_connection_before_guard_write()
print("向导编排与 Playbook/role 组合测试通过。")
