#!/usr/bin/env python3
"""生成只读的月度依赖审计清单。

默认离线检查仓库内固定值一致性；`--check-security` 额外调用 OSV API 查询已知漏洞，
仍为只读，不更新依赖、不自动升级、不创建或合并 PR。
"""

import argparse
import http.client
import json
import math
import re
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")

OSV_QUERY_URL = "https://api.osv.dev/v1/query"
PYPI_ECOSYSTEM = "PyPI"
DEFAULT_TIMEOUT = 20.0
DEFAULT_MAX_PAGES = 5
DEFAULT_MAX_RESPONSE_BYTES = 5_000_000


class OsvError(Exception):
    """OSV 查询未能完成，调用方应报告「未完成」而非「安全」."""


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
    parser.add_argument(
        "--check-security",
        action="store_true",
        help="调用 OSV API 查询已知漏洞（需要联网；默认关闭，保持离线）",
    )
    parser.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT)
    parser.add_argument("--max-pages", type=int, default=DEFAULT_MAX_PAGES)
    parser.add_argument("--max-response-bytes", type=int, default=DEFAULT_MAX_RESPONSE_BYTES)
    args = parser.parse_args()
    if not math.isfinite(args.timeout) or args.timeout <= 0:
        parser.error("--timeout 必须为有限的非零正数")
    if args.max_pages < 1:
        parser.error("--max-pages 必须至少为 1")
    if args.max_response_bytes < 1:
        parser.error("--max-response-bytes 必须至少为 1")
    return args


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


@dataclass(frozen=True)
class PackageRef:
    label: str
    name: str
    version: str
    ecosystem: str = PYPI_ECOSYSTEM


@dataclass(frozen=True)
class CommitRef:
    label: str
    commit: str


SEMVER_TRIPLET_RE = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")


def _cosign_go_module(version: str) -> tuple[str, str] | None:
    """把 Cosign tag 映射为 (Go module, 数字版本)，仅支持当前 v3.X.Y。

    未来若升到 v4，模块路径应为 github.com/sigstore/cosign/v4，沿用 /v3 会得空
    结果；因此仅 major==3 且完整三段数字时映射，其余返回 None 交未检查。
    """
    if not version.startswith("v"):
        return None
    numeric = version[1:]
    if not SEMVER_TRIPLET_RE.match(numeric):
        return None
    if numeric.split(".", 1)[0] != "3":
        return None
    return "github.com/sigstore/cosign/v3", numeric


def classify_requirements_lines(text: str) -> tuple[list[tuple[str, str]], list[str]]:
    """把 requirements 文本拆成精确 `name==version` pin 与未支持的声明。

    未支持的声明包含 extras、通配、范围/标记、VCS/URL、`-r`/`-e` 等；它们不能
    当作准确 PyPI 生态坐标，必须由调用方显式列入「未检查」，不能静默丢弃。
    """
    pins: list[tuple[str, str]] = []
    unsupported: list[str] = []
    for raw in text.splitlines():
        stripped = raw.split("#", 1)[0].strip()
        if not stripped:
            continue
        if (
            stripped.startswith(("-", "--"))
            or stripped.startswith(("git+", "hg+", "svn+", "bzr+"))
            or "://" in stripped
            or "==" not in stripped
        ):
            unsupported.append(stripped)
            continue
        name, _, version = stripped.partition("==")
        name = name.strip()
        version = version.strip()
        if (
            not name
            or not version
            or any(ch in name for ch in ("[", "]", "*"))
            or any(op in name for op in ("<", ">", "~=", "!=", ";", ","))
            or any(op in version for op in ("<", ">", "~=", "!=", "*", ";", ","))
        ):
            unsupported.append(stripped)
            continue
        pins.append((name, version))
    return pins, unsupported


def parse_requirements_pins(text: str) -> list[tuple[str, str]]:
    """从 requirements 文本提取精确 `name==version` 的 PyPI 固定值。

    只返回可明确映射为 PyPI 生态坐标的精确 pin；其余声明由
    `classify_requirements_lines` 显式列入「未检查」，不静默丢弃。
    """
    pins, _ = classify_requirements_lines(text)
    return pins


def collect_package_refs(root: Path) -> list[PackageRef]:
    """收集可明确映射到生态坐标的依赖固定值（PyPI / Go / GIT）。"""
    refs: list[PackageRef] = []
    seen: set[tuple[str, str]] = set()
    installer = (root / "install.sh").read_text(encoding="utf-8")
    variables = (root / "ansible/group_vars/all.yml").read_text(encoding="utf-8")
    ansible_core = shell_constant(installer, "ANSIBLE_CORE_VERSION")
    refs.append(PackageRef("ansible-core", "ansible-core", ansible_core))
    seen.add(("ansible-core", ansible_core))

    uv = yaml_scalar(variables, "uv_version")
    refs.append(PackageRef("uv", "uv", uv))
    seen.add(("uv", uv))

    try:
        go_version = yaml_scalar(variables, "go_version")
    except ValueError:
        go_version = None
    if go_version and SEMVER_TRIPLET_RE.match(go_version):
        refs.append(PackageRef("Go 标准库", "stdlib", go_version, "Go"))

    try:
        node_version = yaml_scalar(variables, "node_version")
    except ValueError:
        node_version = None
    if node_version and SEMVER_TRIPLET_RE.match(node_version):
        refs.append(PackageRef("Node", "https://github.com/nodejs/node.git", f"v{node_version}", "GIT"))

    try:
        cosign_version = shell_constant(installer, "COSIGN_VERSION")
    except ValueError:
        cosign_version = None
    if cosign_version:
        mapped = _cosign_go_module(cosign_version)
        if mapped is not None:
            module, numeric = mapped
            refs.append(PackageRef("Cosign", module, numeric, "Go"))

    reqs_path = root / "requirements-dev.txt"
    if reqs_path.exists():
        for name, version in parse_requirements_pins(reqs_path.read_text(encoding="utf-8")):
            if (name, version) in seen:
                continue
            seen.add((name, version))
            refs.append(PackageRef(f"requirements-dev.txt:{name}", name, version))
    return refs


COMMIT_KEYS: tuple[tuple[str, str], ...] = (
    ("nvm_version", "nvm (nvm-sh/nvm)"),
    ("goenv_source_commit", "goenv (go-nv/goenv)"),
    ("ohmyzsh_version", "Oh My Zsh (ohmyzsh/ohmyzsh)"),
    ("linuxbrew_version", "Linuxbrew (Homebrew/brew)"),
)


def _zsh_plugin_version(text: str, repo: str) -> str | None:
    match = re.search(
        rf"^  {re.escape(repo)}:\n(?:    [^\n]+\n)*?    version: ([^\n#]+)",
        text,
        re.MULTILINE,
    )
    return match.group(1).strip() if match else None


def classify_commit_pins(text: str) -> tuple[list[CommitRef], list[str]]:
    """从 all.yml 文本提取 40 位 hex 的 commit refs，并显式列出未覆盖/非 hex 缺口。"""
    refs: list[CommitRef] = []
    unchecked: list[str] = []
    for key, label in COMMIT_KEYS:
        try:
            value = yaml_scalar(text, key)
        except ValueError:
            unchecked.append(f"`{key}` 缺失或无法解析（{label}），未查询。")
            continue
        if COMMIT_RE.fullmatch(value):
            refs.append(CommitRef(label, value))
        else:
            unchecked.append(f"`{key}` 当前值 `{value}` 非 40 位 commit（{label}），未查询。")
    for repo in ("zsh-autosuggestions", "zsh-syntax-highlighting"):
        value = _zsh_plugin_version(text, repo)
        if value is None:
            unchecked.append(f"zsh 插件 `{repo}` 未提供 40 位 commit 固定值，未查询。")
        elif COMMIT_RE.fullmatch(value):
            refs.append(CommitRef(f"{repo} (zsh-users)", value))
        else:
            unchecked.append(f"zsh 插件 `{repo}` 的 `version` 为 `{value}`，非 40 位 commit，未查询。")
    return refs, unchecked


def collect_commit_refs(root: Path) -> list[CommitRef]:
    """收集 all.yml 中 40 位 hex 的精确提交 pin，走 OSV commit 查询（无需假设生态坐标）。"""
    variables = (root / "ansible/group_vars/all.yml").read_text(encoding="utf-8")
    refs, _ = classify_commit_pins(variables)
    return refs


def _http_post(url: str, payload: bytes, timeout: float, max_response_bytes: int) -> bytes:
    request = urllib.request.Request(
        url,
        data=payload,
        headers={
            "Content-Type": "application/json",
            "Accept": "application/json",
            "User-Agent": "DevOpsToolkit-dependency-audit",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            body = response.read(max_response_bytes + 1)
    except urllib.error.HTTPError as exc:
        raise OsvError(f"OSV HTTP 错误 {exc.code}") from exc
    except urllib.error.URLError as exc:
        raise OsvError("OSV 网络错误") from exc
    except OSError as exc:
        raise OsvError("OSV 请求失败") from exc
    except http.client.HTTPException as exc:
        raise OsvError("OSV HTTP 读取失败") from exc
    if len(body) > max_response_bytes:
        raise OsvError("OSV 响应超过大小限制")
    return body


def _parse_page(body: bytes, label: str) -> tuple[list[dict], str | None]:
    try:
        data = json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise OsvError(f"OSV 响应不是合法 JSON（{label}）") from exc
    if not isinstance(data, dict):
        raise OsvError(f"OSV 响应不是 JSON 对象（{label}）")
    unknown = set(data) - {"vulns", "next_page_token"}
    if unknown:
        raise OsvError(f"OSV 响应包含非标准字段（{label}）")
    if "vulns" not in data:
        vulns: list = []
    else:
        vulns = data["vulns"]
        if not isinstance(vulns, list):
            raise OsvError(f"OSV `vulns` 字段类型异常（{label}）")
        if not all(isinstance(v, dict) for v in vulns):
            raise OsvError(f"OSV `vulns` 字段格式异常（{label}）")
    token = data.get("next_page_token")
    if token is not None and not isinstance(token, str):
        raise OsvError(f"OSV `next_page_token` 字段格式异常（{label}）")
    if token == "":
        token = None
    return vulns, token


def query_osv(
    query: dict,
    label: str,
    *,
    timeout: float,
    max_pages: int,
    max_response_bytes: int,
) -> list[dict]:
    """按需分页查询 OSV，返回收集到的漏洞对象列表；无法完成时抛 OsvError。"""
    page_token: str | None = None
    collected: list[dict] = []
    for _ in range(max_pages):
        payload = dict(query)
        if page_token is not None:
            payload["page_token"] = page_token
        body = _http_post(
            OSV_QUERY_URL,
            json.dumps(payload).encode("utf-8"),
            timeout,
            max_response_bytes,
        )
        vulns, next_token = _parse_page(body, label)
        collected.extend(vulns)
        if next_token is None:
            return collected
        page_token = next_token
    raise OsvError(f"OSV 分页超过上限（{max_pages} 页）")


def _valid_withdrawn_time(value: object) -> bool:
    """仅接受带时区的 RFC3339 时间字符串，其余（bool/对象/数字/无时区）均为非法。"""
    if not isinstance(value, str):
        return False
    text = value.strip()
    if not text:
        return False
    try:
        parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return False
    return parsed.tzinfo is not None and parsed.utcoffset() is not None


def split_vulns(vulns: list[dict]) -> tuple[list[dict], list[dict]]:
    """把 OSV 漏洞拆成「有效」与「已撤回（withdrawn）」两组。

    仅缺失/null 或合法带时区 RFC3339 撤回时间视为已撤回；非法值抛 OsvError，
    避免有效漏洞被静默过滤。
    """
    active: list[dict] = []
    withdrawn: list[dict] = []
    for vuln in vulns:
        if "withdrawn" not in vuln or vuln["withdrawn"] is None:
            active.append(vuln)
        elif _valid_withdrawn_time(vuln["withdrawn"]):
            withdrawn.append(vuln)
        else:
            raise OsvError("OSV `withdrawn` 字段格式异常")
    return active, withdrawn

def vuln_text(vuln: dict) -> str:
    vuln_id = vuln.get("id") or "<unknown-id>"
    summary = vuln.get("summary") or ""
    aliases = vuln.get("aliases")
    if isinstance(aliases, list) and aliases:
        alias_text = ", ".join(str(alias) for alias in aliases)
        return f"`{vuln_id}` — {summary}（别名：{alias_text}）"
    return f"`{vuln_id}` — {summary}"


def distinct_vulns(vulns: list[dict]) -> int:
    """按共享 ID/别名去重，返回独立漏洞数量（跨生态别名合并为同一漏洞）。"""
    id_to_root: dict[str, int] = {}
    parent: list[int] = []

    def find(x: int) -> int:
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(a: int, b: int) -> None:
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[rb] = ra

    for vuln in vulns:
        idx = len(parent)
        parent.append(idx)
        identifiers: list[str] = []
        vid = vuln.get("id")
        if isinstance(vid, str) and vid:
            identifiers.append(vid)
        aliases = vuln.get("aliases")
        if isinstance(aliases, list):
            identifiers.extend(a for a in aliases if isinstance(a, str) and a)
        for identifier in identifiers:
            if identifier in id_to_root:
                union(idx, id_to_root[identifier])
            else:
                id_to_root[identifier] = idx
    return len({find(i) for i in range(len(parent))})


def collect_unchecked(root: Path) -> list[str]:
    lines: list[str] = []
    lock = json.loads((root / "ansible/collections.lock.json").read_text(encoding="utf-8"))
    names = sorted(entry["name"] for entry in lock["collections"])
    lines.append(
        f"- Ansible collections（非 PyPI 生态坐标，未查询）：{', '.join(f'`{n}`' for n in names)}。"
    )

    variables = (root / "ansible/group_vars/all.yml").read_text(encoding="utf-8")
    _, commit_unchecked = classify_commit_pins(variables)
    lines.extend(f"- {note}" for note in commit_unchecked)

    installer = (root / "install.sh").read_text(encoding="utf-8")
    try:
        go_version = yaml_scalar(variables, "go_version")
    except ValueError:
        lines.append("- Go 标准库版本缺失，无法映射 Go 生态坐标，未查询。")
    else:
        if not SEMVER_TRIPLET_RE.match(go_version):
            lines.append(
                f"- Go 版本 `{go_version}` 非完整 `X.Y.Z` 数字版本，无法映射 OSV Go 标准库坐标，未查询。"
            )
    try:
        node_version = yaml_scalar(variables, "node_version")
    except ValueError:
        lines.append("- Node 版本缺失，无法映射 GIT tag，未查询。")
    else:
        if not SEMVER_TRIPLET_RE.match(node_version):
            lines.append(
                f"- Node 版本 `{node_version}` 非完整 `X.Y.Z` 数字版本，无法映射 OSV GIT tag，未查询。"
            )
    try:
        cosign_version = shell_constant(installer, "COSIGN_VERSION")
    except ValueError:
        lines.append("- Cosign 版本缺失，无法映射 Go module 坐标，未查询。")
    else:
        if _cosign_go_module(cosign_version) is None:
            lines.append(
                f"- Cosign 版本 `{cosign_version}` 非当前支持的 `v3.X.Y`，无法映射 Go module 坐标，未查询。"
            )

    reqs_path = root / "requirements-dev.txt"
    if not reqs_path.exists():
        lines.append("- `requirements-dev.txt` 未提供，无 Python 开发依赖可查。")
    else:
        _, unsupported = classify_requirements_lines(reqs_path.read_text(encoding="utf-8"))
        if unsupported:
            lines.append(
                "- `requirements-dev.txt` 中未支持的声明（非精确 `==`、extras、范围/标记、VCS/URL、通配等，未当作准确 PyPI 坐标查询）："
                + "；".join(f"`{line}`" for line in unsupported)
                + "。"
            )

    lines.append("- Go 质量工具 actionlint、gitleaks（已固定版本，本次未实现其 Go 模块坐标查询，未查询）。")
    lines.append("- uv/goenv/Cosign 预编译归档二进制：无 OSV 包坐标，未查询（源码坐标已按上方逻辑查询）。")
    lines.append("- apt 系统包与 Homebrew 公式为发行版/滚动输入，未锁定，未查询。")
    lines.append("- 未锁定的传递依赖不在固定值清单内，未查询。")
    lines.append("- 二进制 SBOM 与传递依赖未覆盖，未查询。")
    return lines


def build_security_report(
    root: Path,
    *,
    timeout: float,
    max_pages: int,
    max_response_bytes: int,
) -> tuple[str, bool]:
    """返回 (markdown 段落, 是否有问题)。有问题 = 发现漏洞或任一查询未完成。"""
    try:
        package_refs = collect_package_refs(root)
        commit_refs = collect_commit_refs(root)
        unchecked = collect_unchecked(root)
    except (OSError, ValueError, TypeError, json.JSONDecodeError) as exc:
        section = (
            "\n## 已知漏洞查询（OSV）\n\n"
            f"安全查询未能完成：{exc}。本结果表示「未完成」，不代表安全。\n"
        )
        return section, True

    rows: list[str] = []
    affected_count = 0
    incomplete_count = 0
    checked_count = len(package_refs) + len(commit_refs)
    all_active: list[dict] = []
    all_withdrawn: list[dict] = []

    for ref in package_refs:
        query = {"package": {"name": ref.name, "ecosystem": ref.ecosystem}, "version": ref.version}
        try:
            vulns = query_osv(
                query, ref.label, timeout=timeout, max_pages=max_pages,
                max_response_bytes=max_response_bytes,
            )
            active, withdrawn = split_vulns(vulns)
        except OsvError as exc:
            incomplete_count += 1
            rows.append(f"| `{ref.label}` | `{ref.version}` | 未完成：{exc} |")
            continue
        all_active.extend(active)
        all_withdrawn.extend(withdrawn)
        if active:
            affected_count += 1
            detail = "；".join(vuln_text(v) for v in active)
            if withdrawn:
                detail += f"（另有 {len(withdrawn)} 条已撤回，不计入风险）"
            rows.append(f"| `{ref.label}` | `{ref.version}` | 发现 {len(active)} 条漏洞记录：{detail} |")
        elif withdrawn:
            rows.append(f"| `{ref.label}` | `{ref.version}` | 无有效漏洞（{len(withdrawn)} 条已撤回） |")
        else:
            rows.append(f"| `{ref.label}` | `{ref.version}` | OSV 未记录已知漏洞 |")

    for ref in commit_refs:
        try:
            vulns = query_osv(
                {"commit": ref.commit}, ref.label, timeout=timeout, max_pages=max_pages,
                max_response_bytes=max_response_bytes,
            )
            active, withdrawn = split_vulns(vulns)
        except OsvError as exc:
            incomplete_count += 1
            rows.append(f"| `{ref.label}` | `{ref.commit}` | 未完成：{exc} |")
            continue
        all_active.extend(active)
        all_withdrawn.extend(withdrawn)
        if active:
            affected_count += 1
            detail = "；".join(vuln_text(v) for v in active)
            if withdrawn:
                detail += f"（另有 {len(withdrawn)} 条已撤回，不计入风险）"
            rows.append(f"| `{ref.label}` | `{ref.commit}` | 发现 {len(active)} 条漏洞记录：{detail} |")
        elif withdrawn:
            rows.append(f"| `{ref.label}` | `{ref.commit}` | 无有效漏洞（{len(withdrawn)} 条已撤回） |")
        else:
            rows.append(f"| `{ref.label}` | `{ref.commit}` | OSV 未记录已知漏洞 |")

    record_count = len(all_active)
    distinct_count = distinct_vulns(all_active)
    withdrawn_total = len(all_withdrawn)
    has_issues = affected_count > 0 or incomplete_count > 0
    status = "存在已知漏洞或未完成" if has_issues else "未发现已知漏洞（不等于无风险）"
    rows_md = "\n".join(rows) if rows else "| （无可查询目标） | | |"
    summary = (
        f"本次检查 {checked_count} 个目标：{affected_count} 个受影响目标，"
        f"共 {record_count} 条 OSV 漏洞记录（去重后 {distinct_count} 个独立漏洞，"
        f"跨生态别名已合并），另有 {withdrawn_total} 条已撤回记录不计入风险，"
        f"未完成 {incomplete_count} 个；其余目标 OSV 未记录漏洞。结论：{status}。"
    )
    section = (
        "\n## 已知漏洞查询（OSV）\n\n"
        f"查询接口：`POST {OSV_QUERY_URL}`（`PyPI`/`Go` 包坐标、`GIT` tag 或精确 `commit`）。\n\n"
        f"{summary}\n\n"
        "| 目标 | 固定值 | 结果 |\n|---|---|---|\n"
        f"{rows_md}\n\n"
        "### 未检查 / 未覆盖\n\n"
        + "\n".join(unchecked)
        + "\n\n"
        "### 结论与限制\n\n"
        "- 本查询只读，不更新依赖、不自动升级、不创建或合并 PR。\n"
        "- 受影响目标数、OSV 记录数与去重后独立漏洞数分开统计；同一 CVE 的 GHSA/PYSEC 等跨生态别名按共享 ID/别名合并。\n"
        "- `GIT` tag 查询与精确 `commit` 查询的匹配记录数可能有轻微差异；本报告仅陈述 OSV 当前匹配情况，不宣称全面无漏洞。\n"
        "- 「OSV 未记录漏洞」仅表示 OSV 数据库当前无匹配，不代表无风险；OSV 覆盖率有限。\n"
        "- 已撤回（`withdrawn`）的漏洞记录不计入有效风险，并在结果中单独标注。\n"
        "- 任一查询因网络、HTTP、JSON 或分页超限而未完成时，本报告视为「未完成」，不会报告为「全部安全」。\n"
    )
    return section, has_issues


def main() -> int:
    args = parse_args()
    try:
        report, errors = build_report(args.root.resolve())
    except (KeyError, OSError, TypeError, ValueError, json.JSONDecodeError) as exc:
        print(f"dependency audit failed: {exc}")
        return 1

    security_issue = False
    if args.check_security:
        security_section, security_issue = build_security_report(
            args.root.resolve(),
            timeout=args.timeout,
            max_pages=args.max_pages,
            max_response_bytes=args.max_response_bytes,
        )
        report += security_section

    if args.output:
        args.output.write_text(report, encoding="utf-8")
    else:
        print(report, end="")

    return 1 if (errors or security_issue) else 0


if __name__ == "__main__":
    raise SystemExit(main())
