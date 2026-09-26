#!/usr/bin/env python3
"""Generate a read-only inventory for the monthly dependency review."""

from __future__ import annotations

import argparse
import json
import re
from datetime import datetime, timezone
from pathlib import Path

SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")


def yaml_scalar(text: str, key: str) -> str:
    match = re.search(rf"^{re.escape(key)}:\s*[\"']?([^\s\"'#]+)", text, re.MULTILINE)
    if not match:
        raise ValueError(f"missing YAML scalar: {key}")
    return match.group(1)


def shell_constant(text: str, key: str) -> str:
    match = re.search(rf'^readonly {re.escape(key)}="([^"]+)"$', text, re.MULTILINE)
    if not match:
        raise ValueError(f"missing shell constant: {key}")
    return match.group(1)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path)
    return parser.parse_args()


def build_report(root: Path) -> tuple[str, list[str]]:
    errors: list[str] = []
    variables = (root / "ansible/group_vars/all.yml").read_text(encoding="utf-8")
    installer = (root / "install.sh").read_text(encoding="utf-8")
    release = (root / ".github/workflows/release.yml").read_text(encoding="utf-8")
    lock = json.loads((root / "ansible/collections.lock.json").read_text(encoding="utf-8"))
    if not isinstance(lock, dict) or not isinstance(lock.get("collections"), list):
        raise TypeError("collection lock must contain a collections list")
    collections = lock["collections"]
    if not all(isinstance(entry, dict) for entry in collections):
        raise TypeError("collection lock entries must be objects")

    ansible_core = shell_constant(installer, "ANSIBLE_CORE_VERSION")
    cosign = shell_constant(installer, "COSIGN_VERSION")
    values = {
        "uv": yaml_scalar(variables, "uv_version"),
        "NVM": yaml_scalar(variables, "nvm_version"),
        "goenv": yaml_scalar(variables, "goenv_version"),
        "goenv source": yaml_scalar(variables, "goenv_source_commit"),
        "Go": yaml_scalar(variables, "go_version"),
        "Node LTS": yaml_scalar(variables, "node_version"),
    }

    workflow_text = "\n".join(
        path.read_text(encoding="utf-8")
        for path in sorted((root / ".github/workflows").glob("*.yml"))
    )
    workflow_ansible = set(re.findall(r"ansible-core==([0-9.]+)", workflow_text))
    workflow_ansible.update(re.findall(r'ansible_core:\s*"([0-9.]+)"', workflow_text))
    if workflow_ansible != {ansible_core}:
        errors.append(
            f"workflow ansible-core pins {sorted(workflow_ansible)} do not match {ansible_core}"
        )
    workflow_cosign = re.search(r"^\s+COSIGN_VERSION:\s*(\S+)$", release, re.MULTILINE)
    if workflow_cosign is None or workflow_cosign.group(1) != cosign:
        errors.append("release.yml COSIGN_VERSION does not match install.sh")
    if not COMMIT_RE.fullmatch(values["NVM"]):
        errors.append("nvm_version is not an immutable 40-character commit")
    if not COMMIT_RE.fullmatch(values["goenv source"]):
        errors.append("goenv_source_commit is not an immutable 40-character commit")

    collection_rows: list[str] = []
    for entry in sorted(collections, key=lambda item: item["name"]):
        digest = str(entry.get("sha256", ""))
        if not SHA256_RE.fullmatch(digest):
            errors.append(f"{entry.get('name', '<unknown>')} has an invalid SHA256")
        collection_rows.append(
            f"| `{entry['name']}` | `{entry['version']}` | `{entry['artifact']}` | `{digest}` |"
        )

    cosign_rows: list[str] = []
    for asset, digest in re.findall(
        r"(cosign-(?:darwin|linux)-(?:amd64|arm64))\) printf '%s\\n' '([0-9a-f]+)'",
        installer,
    ):
        if not SHA256_RE.fullmatch(digest):
            errors.append(f"{asset} has an invalid SHA256")
        cosign_rows.append(f"| `{asset}` | `{digest}` |")
    if len(cosign_rows) != 4:
        errors.append("installer must pin four supported Cosign artifacts")
    release_cosign_hash = re.search(
        r"^\s+COSIGN_LINUX_AMD64_SHA256:\s*([0-9a-f]+)$", release, re.MULTILINE
    )
    installer_linux_amd64 = re.search(
        r"cosign-linux-amd64\) printf '%s\\n' '([0-9a-f]+)'", installer
    )
    if (
        release_cosign_hash is None
        or installer_linux_amd64 is None
        or release_cosign_hash.group(1) != installer_linux_amd64.group(1)
    ):
        errors.append("release.yml Cosign linux-amd64 checksum does not match install.sh")

    uv_rows: list[str] = []
    uv_artifact_block = variables.split("uv_artifacts:\n", 1)[1].split(
        "\nuv_release_base_url_default:", 1
    )[0]
    for architecture, archive, digest in re.findall(
        r"^  (x86_64|aarch64):\n    archive: (\S+)\n    sha256: ([0-9a-f]+)$",
        uv_artifact_block,
        re.MULTILINE,
    ):
        if not SHA256_RE.fullmatch(digest):
            errors.append(f"uv {architecture} has an invalid SHA256")
        uv_rows.append(f"| `{architecture}` | `{archive}` | `{digest}` |")
    if len(uv_rows) != 2:
        errors.append("uv must pin x86_64 and aarch64 artifacts")

    goenv_rows: list[str] = []
    goenv_artifact_block = variables.split("goenv_artifacts:\n", 1)[1].split(
        "\ngoenv_release_base_url_default:", 1
    )[0]
    for architecture, archive, digest, binary_digest in re.findall(
        r"^  (x86_64|aarch64):\n    archive: (\S+)\n    sha256: ([0-9a-f]+)\n"
        r"    binary_sha256: ([0-9a-f]+)$",
        goenv_artifact_block,
        re.MULTILINE,
    ):
        if not SHA256_RE.fullmatch(digest):
            errors.append(f"goenv {architecture} has an invalid SHA256")
        if not SHA256_RE.fullmatch(binary_digest):
            errors.append(f"goenv {architecture} has an invalid binary SHA256")
        platform = "amd64" if architecture == "x86_64" else "arm64"
        if archive != f"goenv_{values['goenv']}_linux_{platform}.tar.gz":
            errors.append(f"goenv {architecture} archive does not match version")
        goenv_rows.append(
            f"| `{architecture}` | `{archive}` | `{digest}` | `{binary_digest}` |"
        )
    if len(goenv_rows) != 2:
        errors.append("goenv must pin x86_64 and aarch64 artifacts")

    action_rows: list[str] = []
    for workflow in sorted((root / ".github/workflows").glob("*.yml")):
        text = workflow.read_text(encoding="utf-8")
        for reference in re.findall(r"uses:\s+([^\s]+)", text):
            if not reference.startswith("./") and not re.fullmatch(r"[^@\s]+@[0-9a-f]{40}", reference):
                errors.append(f"{workflow.name} has a non-immutable action reference: {reference}")
        for action, revision, label in re.findall(
            r"uses:\s+([^@\s]+)@([0-9a-f]{40})(?:\s+#\s*([^\n]+))?",
            text,
        ):
            action_rows.append(
                f"| `{workflow.name}` | `{action}` | `{revision}` | {label.strip() or '-'} |"
            )

    generated = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    error_lines = [f"- {error}" for error in errors] or ["- 无；仓库内固定值一致性检查通过。"]
    report = f"""# DevOpsToolkit 月度依赖审计

生成时间：`{generated}`

来源：当前 checkout；本报告只读，不更新依赖、不创建或合并 PR。

## 核心版本

| 依赖 | 当前固定值 | 人工复核入口 |
|---|---|---|
| Ansible Core | `{ansible_core}` | https://pypi.org/project/ansible-core/ |
| Cosign | `{cosign}` | https://github.com/sigstore/cosign/releases |
| uv | `{values['uv']}` | https://github.com/astral-sh/uv/releases |
| NVM | `{values['NVM']}` | https://github.com/nvm-sh/nvm/commits/master/ |
| goenv | `{values['goenv']}` (source `{values['goenv source']}`) | https://github.com/go-nv/goenv/releases/tag/{values['goenv']} |
| Go | `{values['Go']}` | https://go.dev/dl/ |
| Node LTS | `{values['Node LTS']}` | https://nodejs.org/en/about/previous-releases |

## Ansible collections

| 名称 | 版本 | 归档 | SHA256 |
|---|---|---|---|
{chr(10).join(collection_rows)}

## Cosign 归档校验值

| 归档 | SHA256 |
|---|---|
{chr(10).join(cosign_rows)}

## uv 归档校验值

| 架构 | 归档 | SHA256 |
|---|---|---|
{chr(10).join(uv_rows)}

## goenv 归档校验值

| 架构 | 归档 | 归档 SHA256 | 二进制 SHA256 |
|---|---|---|---|
{chr(10).join(goenv_rows)}

## GitHub Actions

| Workflow | Action | 固定 commit | 注释版本 |
|---|---|---|---|
{chr(10).join(action_rows)}

## 一致性检查

{chr(10).join(error_lines)}

## 审核规则

1. 在官方来源确认新版本、支持周期、变更日志与安全公告，不根据本报告自动升级。
2. 所有更新通过独立 PR；归档类依赖必须由维护者重新下载并独立复核 SHA256。
3. PR 必须通过静态门禁、篡改负向测试与一次性 VM smoke；高风险更新禁止自动合并。
4. apt、Docker APT 仓库与 Homebrew formula 是滚动输入，需单独审查，不能由固定 Git commit 推导为 bit-for-bit 可复现。
"""
    return report, errors


def main() -> int:
    args = parse_args()
    try:
        report, errors = build_report(args.root.resolve())
        if args.output:
            args.output.write_text(report, encoding="utf-8")
        else:
            print(report, end="")
    except (KeyError, OSError, TypeError, ValueError, json.JSONDecodeError) as exc:
        print(f"dependency audit failed: {exc}")
        return 1
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
