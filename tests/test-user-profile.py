#!/usr/bin/env python3
"""Matrix checks for independent user-profile environment switches."""

from __future__ import annotations

import itertools
import re
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parent.parent
TEMPLATE_DIR = ROOT_DIR / "ansible" / "roles" / "user_profile" / "templates"


def render_boolean_blocks(template: str, values: dict[str, bool]) -> str:
    """Render the simple boolean Jinja blocks used by these two templates."""
    pattern = re.compile(
        r"{% if ([a-z_]+) \| bool %}(.*?){% endif %}",
        re.DOTALL,
    )

    def replace(match: re.Match[str]) -> str:
        return match.group(2) if values[match.group(1)] else ""

    return pattern.sub(replace, template)


environment_template = (TEMPLATE_DIR / "environment.sh.j2").read_text(
    encoding="utf-8"
)
tokens = {
    "configure_uv": 'export PATH="$HOME/.local/bin:$PATH"',
    "configure_homebrew_environment": "brew shellenv",
    "configure_node": 'export NVM_DIR="$HOME/.nvm"',
    "configure_go": 'export GOENV_ROOT="$HOME/.local/share/devops-toolkit/goenv"',
}

for flags in itertools.product((False, True), repeat=len(tokens)):
    values = dict(zip(tokens, flags, strict=True))
    rendered = render_boolean_blocks(environment_template, values)
    for key, token in tokens.items():
        assert (token in rendered) is values[key], (values, key, rendered)

shell_template = (TEMPLATE_DIR / "shell.zsh.j2").read_text(encoding="utf-8")
without_oh_my_zsh = render_boolean_blocks(
    shell_template,
    {"install_oh_my_zsh": False},
)
with_oh_my_zsh = render_boolean_blocks(
    shell_template,
    {"install_oh_my_zsh": True},
)
assert "oh-my-zsh.sh" not in without_oh_my_zsh
assert "oh-my-zsh.sh" in with_oh_my_zsh

tasks = (ROOT_DIR / "ansible" / "playbooks" / "user-only.yml").read_text(
    encoding="utf-8"
)
assert tasks.index("Install only whitelisted user-profile dependencies") < tasks.index(
    "Recheck required commands after the optional dependency installation"
)
for command in ("curl", "bash", "tar", "cc", "make"):
    assert command in tasks

role_tasks = (
    ROOT_DIR / "ansible" / "roles" / "user_profile" / "tasks" / "main.yml"
).read_text(encoding="utf-8")
assert "DEVOPSTOOLKIT USER ENVIRONMENT" in role_tasks
assert "DEVOPSTOOLKIT USER SHELL" in role_tasks
assert "{{ profile_target_home }}/.profile" in role_tasks

print("用户环境开关矩阵测试通过。")
