#!/usr/bin/env python3
"""Focused tests for the interactive launcher without invoking Ansible."""

from __future__ import annotations

import builtins
import runpy
import stat
import tempfile
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator


ROOT_DIR = Path(__file__).resolve().parent.parent
wizard = runpy.run_path(str(ROOT_DIR / "bin" / "devops-toolkit"))


@contextmanager
def answers(*values: str) -> Iterator[None]:
    pending = iter(values)
    original = builtins.input
    builtins.input = lambda _prompt="": next(pending)
    try:
        yield
    finally:
        builtins.input = original


with answers(""):
    assert wizard["prompt"]("可留空", "") == ""

with answers(""):
    assert wizard["choose"]("模式", [("a", "A"), ("b", "B")], "b") == "b"

with answers("2,3", ""):
    selected = wizard["multi_select"](
        "组件",
        [("one", "一", True), ("two", "二", True), ("three", "三", False)],
    )
assert selected == {"one": True, "two": False, "three": True}

filtered = wizard["persisted_variables"](
    {
        "target_user": "developer",
        "configure_node": True,
        "node_version": "24.11.1",
        "target_password_hash": "$6$secret",
        "target_authorized_keys": ["ssh-ed25519 secret"],
        "ssh_port": 2222,
        "user_only_allow_system_dependencies": True,
    }
)
assert filtered == {
    "target_user": "developer",
    "configure_node": True,
    "node_version": "24.11.1",
}

with tempfile.TemporaryDirectory() as directory:
    state_path = Path(directory) / "config" / "wizard-state.json"
    state = {
        "schema": wizard["STATE_SCHEMA"],
        "last_mode": "wsl",
        "modes": {"wsl": filtered},
    }
    wizard["save_wizard_state"](state, state_path)
    assert wizard["load_wizard_state"](state_path) == state
    saved_text = state_path.read_text(encoding="utf-8")
    assert "secret" not in saved_text
    assert "target_password_hash" not in saved_text
    assert stat.S_IMODE(state_path.stat().st_mode) == 0o600
    assert stat.S_IMODE(state_path.parent.stat().st_mode) == 0o700

assert wizard["project_default_version"]("node_version")
assert wizard["project_default_version"]("go_version")

assert (
    wizard["public_key_identity"]("ssh-ed25519 AAAATEST first-comment")
    == wizard["public_key_identity"]("ssh-ed25519 AAAATEST changed-comment")
)
assert wizard["public_key_identity"]("invalid") == ""

assert wizard["normalize_user_module_selection"](
    {"configure_shell": False, "install_oh_my_zsh": True}
) == {"configure_shell": False, "install_oh_my_zsh": False}
assert wizard["normalize_user_module_selection"](
    {"configure_shell": True, "install_oh_my_zsh": False}
) == {"configure_shell": True, "install_oh_my_zsh": False}
assert wizard["target_account_is_known"]("remote", "developer", "developer")
assert not wizard["target_account_is_known"]("remote", "root", "developer")
assert wizard["target_account_is_known"](
    "local", "root", "developer", local_exists=True
)

module_globals = wizard["collect_user_modules"].__globals__
original_multi_select = module_globals["multi_select"]
original_prompt_version = module_globals["prompt_version"]
original_prompt = module_globals["prompt"]
try:
    chosen_modules = {
        "configure_shell": False,
        "install_oh_my_zsh": True,
        "configure_git": False,
        "configure_uv": True,
        "configure_node": True,
        "configure_go": True,
        "configure_homebrew_environment": True,
    }
    version_prompts: list[tuple[str, str]] = []
    module_globals["multi_select"] = lambda *_args, **_kwargs: chosen_modules.copy()

    def record_version(label: str, default: str) -> str:
        version_prompts.append((label, default))
        return default

    def reject_git_prompt(*_args: object, **_kwargs: object) -> str:
        raise AssertionError("Git disabled must not prompt for identity")

    module_globals["prompt_version"] = record_version
    module_globals["prompt"] = reject_git_prompt
    selected_modules = wizard["collect_user_modules"](
        {"node_version": "24.11.1", "go_version": "1.22.1"}
    )
    disabled_modules = {
        **chosen_modules,
        "install_oh_my_zsh": False,
        "configure_uv": False,
        "configure_node": False,
        "configure_go": False,
        "configure_homebrew_environment": False,
    }
    module_globals["multi_select"] = lambda *_args, **_kwargs: disabled_modules.copy()
    selected_disabled = wizard["collect_user_modules"]()
finally:
    module_globals["multi_select"] = original_multi_select
    module_globals["prompt_version"] = original_prompt_version
    module_globals["prompt"] = original_prompt

assert selected_modules == {
    **chosen_modules,
    "install_oh_my_zsh": False,
    "node_version": "24.11.1",
    "go_version": "1.22.1",
}
assert version_prompts == [("Node.js", "24.11.1"), ("Go", "1.22.1")]
assert selected_disabled == disabled_modules

user_only_globals = wizard["collect_user_only"].__globals__
original_connection = user_only_globals["collect_connection"]
original_user_modules = user_only_globals["collect_user_modules"]
original_user_confirm = user_only_globals["confirm"]
try:
    user_only_globals["collect_connection"] = lambda *_args: (
        "[user_only]\ntest ansible_connection=local\n",
        {"host": "localhost", "user": "developer", "auth": "key"},
        [],
    )
    user_only_globals["collect_user_modules"] = lambda _defaults=None: selected_modules.copy()
    for allow_dependencies in (False, True):
        user_only_globals["confirm"] = lambda *_args, **_kwargs: allow_dependencies
        playbook, inventory, variables, extra_args, summary = wizard[
            "collect_user_only"
        ]()
        assert playbook.name == "user-only.yml"
        assert inventory.startswith("[user_only]")
        assert variables["configure_shell"] is False
        assert variables["configure_node"] is True
        assert variables["configure_go"] is True
        assert variables["configure_uv"] is True
        assert variables["user_only_allow_system_dependencies"] is allow_dependencies
        assert extra_args == (["--ask-become-pass"] if allow_dependencies else [])
        assert summary["系统依赖例外"] == ("允许" if allow_dependencies else "禁止")
finally:
    user_only_globals["collect_connection"] = original_connection
    user_only_globals["collect_user_modules"] = original_user_modules
    user_only_globals["confirm"] = original_user_confirm

auto_finalize_vars = {
    "configure_ssh": True,
    "target_authorized_keys": ["ssh-ed25519 AAAATEST target-comment"],
    "target_passwordless_sudo": True,
}
auto_finalize_connection = {"auth": "key"}
assert wizard["can_auto_finalize_ubuntu"](
    "remote",
    auto_finalize_connection,
    auto_finalize_vars,
    ["ssh-ed25519 AAAATEST key-comment"],
)
assert not wizard["can_auto_finalize_ubuntu"](
    "remote",
    auto_finalize_connection,
    auto_finalize_vars,
    ["ssh-ed25519 AAAAOTHER"],
)
assert not wizard["can_auto_finalize_ubuntu"](
    "remote",
    auto_finalize_connection,
    {**auto_finalize_vars, "target_passwordless_sudo": False},
    ["ssh-ed25519 AAAATEST"],
)
assert not wizard["can_auto_finalize_ubuntu"](
    "local",
    auto_finalize_connection,
    auto_finalize_vars,
    ["ssh-ed25519 AAAATEST"],
)
assert not wizard["can_auto_finalize_ubuntu"](
    "remote",
    {"auth": "password"},
    auto_finalize_vars,
    ["ssh-ed25519 AAAATEST"],
)

credential_globals = wizard["collect_target_credentials"].__globals__
original_choose = credential_globals["choose"]
original_collect_public_keys = credential_globals["collect_public_keys"]
original_confirm = credential_globals["confirm"]
try:
    credential_globals["choose"] = lambda *_args, **_kwargs: "key"
    credential_globals["collect_public_keys"] = lambda *_args, **_kwargs: [
        "ssh-ed25519 AAAATEST"
    ]
    confirm_defaults: list[bool] = []

    def confirm_passwordless(_label: str, default: bool = True) -> bool:
        confirm_defaults.append(default)
        return True

    credential_globals["confirm"] = confirm_passwordless
    key_only = wizard["collect_target_credentials"]()
finally:
    credential_globals["choose"] = original_choose
    credential_globals["collect_public_keys"] = original_collect_public_keys
    credential_globals["confirm"] = original_confirm

assert confirm_defaults == [False]
assert key_only["target_password_hash"] == ""
assert key_only["target_passwordless_sudo"] is True

credential_globals = wizard["collect_target_credentials"].__globals__
original_choose = credential_globals["choose"]
original_confirm = credential_globals["confirm"]
try:
    credential_globals["choose"] = lambda *_args, **_kwargs: "existing"
    existing_defaults: list[bool] = []

    def confirm_existing(_label: str, default: bool = True) -> bool:
        existing_defaults.append(default)
        return default

    credential_globals["confirm"] = confirm_existing
    existing = wizard["collect_target_credentials"](
        account_exists=True,
    )
finally:
    credential_globals["choose"] = original_choose
    credential_globals["confirm"] = original_confirm

assert existing_defaults == [False]
assert existing["target_passwordless_sudo"] is False

print("交互式向导测试通过。")
