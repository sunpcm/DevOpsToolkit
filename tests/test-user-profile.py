#!/usr/bin/env python3
"""Matrix checks for independent user-profile environment switches."""

from __future__ import annotations

import itertools
import re
import subprocess
import tempfile
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

    # A token in a template is not proof that a POSIX shell can source it.
    # Use a fresh HOME for every combination and harmless local stand-ins so
    # the test needs neither network access nor real runtime installations.
    with tempfile.TemporaryDirectory(prefix="devops-profile-matrix-") as home_dir:
        home = Path(home_dir)
        config_file = home / ".config/devops-toolkit/environment.sh"
        config_file.parent.mkdir(parents=True)
        config_file.write_text(rendered, encoding="utf-8")

        uv = home / ".local/bin/uv"
        uv.parent.mkdir(parents=True)
        uv.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        uv.chmod(0o755)

        nvm = home / ".nvm/nvm.sh"
        nvm.parent.mkdir(parents=True)
        nvm.write_text("NVM_MATRIX_LOADED=1\n", encoding="utf-8")

        goenv = home / ".local/share/devops-toolkit/goenv/bin/goenv"
        goenv.parent.mkdir(parents=True)
        goenv.write_text(
            "#!/bin/sh\n"
            "if [ \"$1\" = init ] && [ \"$2\" = - ]; then\n"
            "  printf 'GOENV_MATRIX_LOADED=1\\n'\n"
            "fi\n",
            encoding="utf-8",
        )
        goenv.chmod(0o755)

        shell_env = {"HOME": str(home), "PATH": "/usr/bin:/bin"}
        result = subprocess.run(
            [
                "/bin/sh",
                "-c",
                '. "$HOME/.config/devops-toolkit/environment.sh"; '
                'printf "uv=%s\\nnvm=%s\\ngoenv=%s\\n" '
                '"$(command -v uv || :)" "${NVM_MATRIX_LOADED-}" '
                '"${GOENV_MATRIX_LOADED-}"',
            ],
            env=shell_env,
            capture_output=True,
            text=True,
            check=True,
        )
        observed = dict(line.split("=", 1) for line in result.stdout.splitlines())
        assert (observed["uv"] == str(uv)) is values["configure_uv"], values
        assert (observed["nvm"] == "1") is values["configure_node"], values
        assert (observed["goenv"] == "1") is values["configure_go"], values

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
