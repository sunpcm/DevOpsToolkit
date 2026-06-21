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

print("交互式向导测试通过。")
