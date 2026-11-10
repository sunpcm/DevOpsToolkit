#!/usr/bin/env python3
"""Unit tests for scripts/dependency-audit.py.

全部使用 mock，不访问真实网络，覆盖离线默认、无漏洞/有漏洞、分页/超限、
HTTP/格式失败，以及报告保留与退出码。
"""

from __future__ import annotations

import http.client
import importlib.util
import json
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT_PATH = ROOT / "scripts" / "dependency-audit.py"

spec = importlib.util.spec_from_file_location("dependency_audit", SCRIPT_PATH)
assert spec is not None and spec.loader is not None
da = importlib.util.module_from_spec(spec)
sys.modules["dependency_audit"] = da
spec.loader.exec_module(da)

OsvError = da.OsvError
parse_requirements_pins = da.parse_requirements_pins
classify_requirements_lines = da.classify_requirements_lines
classify_commit_pins = da.classify_commit_pins
distinct_vulns = da.distinct_vulns
collect_package_refs = da.collect_package_refs
collect_commit_refs = da.collect_commit_refs
split_vulns = da.split_vulns
query_osv = da.query_osv
build_security_report = da.build_security_report
main = da.main

_ORIG_HTTP_POST = da._http_post
_ORIG_QUERY_OSV = da.query_osv
_ORIG_COLLECT_PACKAGE = da.collect_package_refs
_ORIG_COLLECT_COMMIT = da.collect_commit_refs
_ORIG_COLLECT_UNCHECKED = da.collect_unchecked


def make_http_sequence(pages):
    """返回 (fake_http_post, calls)。

    pages 中每个元素要么是 (vulns, next_token) 元组，要么是 Exception；fake 按序弹出一页。
    """
    calls: list[dict] = []

    def fake(url, payload, timeout, max_response_bytes):
        calls.append(json.loads(payload.decode("utf-8")))
        if not pages:
            raise AssertionError("unexpected extra HTTP call")
        item = pages.pop(0)
        if isinstance(item, Exception):
            raise item
        vulns, token = item
        body: dict = {"vulns": vulns}
        if token is not None:
            body["next_page_token"] = token
        return json.dumps(body).encode("utf-8")

    return fake, calls


def test_parse_requirements_pins_exact_only() -> None:
    text = """\
# comment
requests==2.32.3
urllib3==2.2.3 # inline
flask>=3.0
black ~= 24.0
pytest==8.3.5 ; python_version >= "3.9"
-e git+https://github.com/foo/bar.git@abc#egg=bar
pkg==1.0,<2.0
-r requirements.txt
"""
    assert parse_requirements_pins(text) == [("requests", "2.32.3"), ("urllib3", "2.2.3")]


def test_collect_package_refs_real_root() -> None:
    refs = collect_package_refs(ROOT)
    by_name = {ref.name: ref for ref in refs}
    assert "ansible-core" in by_name
    assert "uv" in by_name
    assert "ansible-lint" in by_name
    assert "ruff" in by_name
    assert "shellcheck-py" in by_name
    assert by_name["ansible-core"].version == "2.21.4"
    assert by_name["uv"].version
    assert sum(1 for ref in refs if ref.name == "ansible-core") == 1

    assert "stdlib" in by_name
    assert by_name["stdlib"].ecosystem == "Go"
    assert by_name["stdlib"].version == "1.27.3"

    assert "https://github.com/nodejs/node.git" in by_name
    assert by_name["https://github.com/nodejs/node.git"].ecosystem == "GIT"
    assert by_name["https://github.com/nodejs/node.git"].version == "v24.22.2"

    assert "github.com/sigstore/cosign/v3" in by_name
    assert by_name["github.com/sigstore/cosign/v3"].ecosystem == "Go"
    assert by_name["github.com/sigstore/cosign/v3"].version == "3.1.1"


def _write_minimal_root(
    tmp_path: Path, *, go_version: str, node_version: str, cosign_version: str
) -> Path:
    """写一个最小可解析的仓库骨架，用于版本映射负例测试。"""
    group_vars = tmp_path / "ansible" / "group_vars"
    group_vars.mkdir(parents=True, exist_ok=True)
    (tmp_path / "install.sh").write_text(
        'readonly ANSIBLE_CORE_VERSION="2.21.4"\n'
        f'readonly COSIGN_VERSION="{cosign_version}"\n',
        encoding="utf-8",
    )
    (group_vars / "all.yml").write_text(
        'uv_version: "0.13.7"\n'
        f'go_version: "{go_version}"\n'
        f'node_version: "{node_version}"\n'
        "nvm_version: 4e8758a801eea9479b32a904f31093e410ddaba4\n"
        "goenv_source_commit: 66571a3851c83e1341dce284aba907964c3d6a48\n",
        encoding="utf-8",
    )
    (tmp_path / "ansible" / "collections.lock.json").write_text(
        '{"collections": []}', encoding="utf-8"
    )
    return tmp_path


def test_collect_package_refs_non_semver_unmapped() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = _write_minimal_root(
            Path(tmp),
            go_version="1.27",
            node_version="24.22.2-beta",
            cosign_version="v4.0.0",
        )
        refs = collect_package_refs(root)
        names = [ref.name for ref in refs]
        assert "stdlib" not in names
        assert "https://github.com/nodejs/node.git" not in names
        assert "github.com/sigstore/cosign/v3" not in names
        assert "github.com/sigstore/cosign/v4" not in names
        # 正常精确 pin 仍应映射
        assert any(ref.name == "uv" and ref.version == "0.13.7" for ref in refs)


def test_collect_unchecked_non_semver_reported() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = _write_minimal_root(
            Path(tmp),
            go_version="1.27",
            node_version="24",
            cosign_version="v3",
        )
        unchecked = "\n".join(da.collect_unchecked(root))
        assert "Go 版本" in unchecked and "非完整 `X.Y.Z`" in unchecked
        assert "Node 版本" in unchecked and "非完整 `X.Y.Z`" in unchecked
        assert "Cosign 版本" in unchecked and "`v3.X.Y`" in unchecked
        assert "actionlint" in unchecked and "已固定版本" in unchecked


def test_collect_commit_refs_real_root() -> None:
    refs = collect_commit_refs(ROOT)
    labels = " ".join(ref.label for ref in refs)
    assert "nvm" in labels
    assert "goenv" in labels
    assert "Oh My Zsh" in labels
    assert "Linuxbrew" in labels
    assert "zsh-autosuggestions" in labels
    assert "zsh-syntax-highlighting" in labels
    assert len(refs) >= 6
    for ref in refs:
        assert len(ref.commit) == 40
        assert all(char in "0123456789abcdef" for char in ref.commit)


def test_split_vulns_withdrawn() -> None:
    vulns = [
        {"id": "ACTIVE-1", "summary": "active"},
        {"id": "WITHDRAWN-1", "summary": "withdrawn", "withdrawn": "2024-01-01T00:00:00Z"},
    ]
    active, withdrawn = split_vulns(vulns)
    assert [v["id"] for v in active] == ["ACTIVE-1"]
    assert [v["id"] for v in withdrawn] == ["WITHDRAWN-1"]


def test_query_osv_no_vulns() -> None:
    fake, calls = make_http_sequence([([], None)])
    da._http_post = fake
    try:
        result = query_osv(
            {"package": {"name": "x", "ecosystem": "PyPI"}, "version": "1.0"},
            "x",
            timeout=5,
            max_pages=5,
            max_response_bytes=100_000,
        )
    finally:
        da._http_post = _ORIG_HTTP_POST
    assert result == []
    assert len(calls) == 1
    assert calls[0]["package"]["name"] == "x"
    assert "page_token" not in calls[0]


def test_query_osv_pagination() -> None:
    fake, calls = make_http_sequence([([{"id": "V1"}], "token-1"), ([{"id": "V2"}], None)])
    da._http_post = fake
    try:
        result = query_osv(
            {"commit": "a" * 40}, "c", timeout=5, max_pages=5, max_response_bytes=100_000
        )
    finally:
        da._http_post = _ORIG_HTTP_POST
    assert [v["id"] for v in result] == ["V1", "V2"]
    assert len(calls) == 2
    assert "page_token" not in calls[0]
    assert calls[1]["page_token"] == "token-1"


def test_query_osv_pagination_limit() -> None:
    fake, _ = make_http_sequence([([{"id": "V1"}], "token-1"), ([], "token-2")])
    da._http_post = fake
    try:
        try:
            query_osv(
                {"commit": "a" * 40}, "c", timeout=5, max_pages=1, max_response_bytes=100_000
            )
            assert False, "should have raised OsvError on pagination limit"
        except OsvError as exc:
            assert "分页" in str(exc)
    finally:
        da._http_post = _ORIG_HTTP_POST


def test_query_osv_http_error() -> None:
    fake, _ = make_http_sequence([OsvError("OSV HTTP 错误 500")])
    da._http_post = fake
    try:
        try:
            query_osv(
                {"commit": "a" * 40}, "c", timeout=5, max_pages=1, max_response_bytes=100_000
            )
            assert False, "should have raised OsvError on HTTP failure"
        except OsvError as exc:
            assert "HTTP" in str(exc)
    finally:
        da._http_post = _ORIG_HTTP_POST


def test_query_osv_format_failure() -> None:
    da._http_post = lambda *a, **k: b"not-json"
    try:
        try:
            query_osv(
                {"commit": "a" * 40}, "c", timeout=5, max_pages=1, max_response_bytes=100_000
            )
            assert False, "should have raised OsvError on malformed JSON"
        except OsvError as exc:
            assert "JSON" in str(exc)
    finally:
        da._http_post = _ORIG_HTTP_POST


def test_parse_page_malformed_shape() -> None:
    for body in (b'{"vulns": "not-a-list"}', b'{"vulns": [1]}', b'{"next_page_token": 123}'):
        try:
            da._parse_page(body, "x")
            assert False, f"should have raised OsvError for {body!r}"
        except OsvError:
            pass


def test_parse_page_falsy_vulns_rejected() -> None:
    for body in (b'{"vulns": false}', b'{"vulns": {}}', b'{"vulns": 0}', b'{"vulns": null}'):
        try:
            da._parse_page(body, "x")
            assert False, f"should have raised OsvError for {body!r}"
        except OsvError as exc:
            assert "vulns" in str(exc)


def test_parse_page_missing_vulns_defaults_empty() -> None:
    assert da._parse_page(b"{}", "x") == ([], None)
    vulns, token = da._parse_page(b'{"next_page_token": "t"}', "x")
    assert vulns == []
    assert token == "t"


def test_parse_page_error_object_rejected_no_body_leak() -> None:
    try:
        da._parse_page(b'{"error": "upstream unavailable"}', "x")
        assert False, "should have raised OsvError for error object"
    except OsvError as exc:
        assert "非标准" in str(exc)
        assert "upstream" not in str(exc)


def test_query_osv_error_object_raises() -> None:
    da._http_post = lambda *a, **k: b'{"error": "upstream unavailable"}'
    try:
        try:
            query_osv(
                {"commit": "a" * 40}, "c", timeout=5, max_pages=1, max_response_bytes=100_000
            )
            assert False, "should have raised OsvError"
        except OsvError as exc:
            assert "非标准" in str(exc)
    finally:
        da._http_post = _ORIG_HTTP_POST


def test_parse_page_unknown_fields_rejected() -> None:
    for body in (
        b'{"message": "upstream unavailable"}',
        b'{"code": 503, "message": "unavailable", "status": "UNAVAILABLE"}',
        b'{"error": "upstream unavailable"}',
        b'{"vulns": [], "extra": 1}',
    ):
        try:
            da._parse_page(body, "x")
            assert False, f"should have raised OsvError for {body!r}"
        except OsvError as exc:
            assert "非标准" in str(exc)


def test_parse_page_empty_next_page_token_completes() -> None:
    vulns, token = da._parse_page(b'{"vulns": [{"id": "V1"}], "next_page_token": ""}', "x")
    assert [v["id"] for v in vulns] == ["V1"]
    assert token is None


def test_split_vulns_invalid_withdrawn() -> None:
    for value in (True, {}, "not-a-timestamp", 0, []):
        try:
            da.split_vulns([{"id": "X", "withdrawn": value}])
            assert False, f"should have raised OsvError for withdrawn={value!r}"
        except OsvError as exc:
            assert "withdrawn" in str(exc)


def test_split_vulns_missing_or_null_active() -> None:
    active, withdrawn = da.split_vulns(
        [{"id": "A", "withdrawn": None}, {"id": "B"}]
    )
    assert [v["id"] for v in active] == ["A", "B"]
    assert withdrawn == []


def test_http_post_incomplete_read_normalized() -> None:
    class FakeResponse:
        def __enter__(self):
            return self

        def __exit__(self, *args):
            return False

        def read(self, size):
            raise http.client.IncompleteRead(b"partial", 100)

    orig_urlopen = da.urllib.request.urlopen
    da.urllib.request.urlopen = lambda request, timeout=None: FakeResponse()
    try:
        try:
            da._http_post("http://x", b"{}", 5, 100_000)
            assert False, "should have raised OsvError on IncompleteRead"
        except OsvError as exc:
            assert "读取" in str(exc)
    finally:
        da.urllib.request.urlopen = orig_urlopen


def test_parse_args_rejects_nonfinite_timeout() -> None:
    for value in ("inf", "nan"):
        saved = sys.argv
        try:
            sys.argv = ["dependency-audit.py", "--timeout", value]
            try:
                da.parse_args()
                assert False, f"should reject --timeout {value}"
            except SystemExit as exc:
                assert exc.code != 0
        finally:
            sys.argv = saved


def test_classify_requirements_lines_unsupported() -> None:
    text = """\
requests==2.32.3
flask[async]>=3.0
uv==0.1.*
pkg @ https://example.com/pkg.whl
-e git+https://github.com/foo/bar.git@abc#egg=bar
-r other.txt
"""
    pins, unsupported = classify_requirements_lines(text)
    assert pins == [("requests", "2.32.3")]
    assert any("flask[async]" in line for line in unsupported)
    assert any("0.1.*" in line for line in unsupported)
    assert any("@ https" in line for line in unsupported)
    assert any("-e git+" in line for line in unsupported)
    assert any("-r other.txt" in line for line in unsupported)


def test_classify_commit_pins_nonhex_reported() -> None:
    text = """\
nvm_version: v0.41.0
goenv_source_commit: 66571a3851c83e1341dce284aba907964c3d6a48
ohmyzsh_version: c954bbb168fc645592c50017de0d0e138db8df5f
linuxbrew_version: 686144996e76cda071d5829d1c180704dd271fc3
zsh_plugin_sources:
  zsh-autosuggestions:
    repo: https://github.com/zsh-users/zsh-autosuggestions
    version: 0e810e5afa27acbd074398eefbe28d13005dbc15
  zsh-syntax-highlighting:
    repo: https://github.com/zsh-users/zsh-syntax-highlighting
    version: main
"""
    refs, unchecked = classify_commit_pins(text)
    labels = " ".join(ref.label for ref in refs)
    assert "nvm" not in labels
    assert "goenv" in labels
    assert any("nvm_version" in note and "v0.41.0" in note for note in unchecked)
    assert any("zsh-syntax-highlighting" in note and "main" in note for note in unchecked)


def test_distinct_vulns_union() -> None:
    vulns = [
        {"id": "GHSA-1", "aliases": ["CVE-2026-1"]},
        {"id": "PYSEC-1", "aliases": ["CVE-2026-1"]},
        {"id": "OSV-2", "aliases": ["CVE-2026-2"]},
    ]
    assert distinct_vulns(vulns) == 2
    assert distinct_vulns([]) == 0


def test_build_security_report_clean() -> None:
    da.query_osv = lambda query, label, *, timeout, max_pages, max_response_bytes: []
    try:
        section, has_issues = build_security_report(
            ROOT, timeout=5, max_pages=5, max_response_bytes=100_000
        )
    finally:
        da.query_osv = _ORIG_QUERY_OSV
    assert has_issues is False
    assert "OSV 未记录已知漏洞" in section
    assert "未完成 0 个" in section


def test_build_security_report_found() -> None:
    def fake(query, label, *, timeout, max_pages, max_response_bytes):
        if "package" in query:
            return [{"id": "PYSEC-1", "summary": "test vuln", "aliases": ["CVE-2024-1"]}]
        return []

    da.query_osv = fake
    try:
        section, has_issues = build_security_report(
            ROOT, timeout=5, max_pages=5, max_response_bytes=100_000
        )
    finally:
        da.query_osv = _ORIG_QUERY_OSV
    assert has_issues is True
    assert "PYSEC-1" in section
    assert "发现" in section


def test_build_security_report_withdrawn_only() -> None:
    def fake(query, label, *, timeout, max_pages, max_response_bytes):
        return [{"id": "OLD-1", "summary": "withdrawn", "withdrawn": "2024-01-01T00:00:00Z"}]

    da.query_osv = fake
    try:
        section, has_issues = build_security_report(
            ROOT, timeout=5, max_pages=5, max_response_bytes=100_000
        )
    finally:
        da.query_osv = _ORIG_QUERY_OSV
    assert has_issues is False
    assert "已撤回" in section


def test_build_security_report_incomplete() -> None:
    def fake(query, label, *, timeout, max_pages, max_response_bytes):
        raise OsvError("OSV HTTP 错误 500")

    da.query_osv = fake
    try:
        section, has_issues = build_security_report(
            ROOT, timeout=5, max_pages=5, max_response_bytes=100_000
        )
    finally:
        da.query_osv = _ORIG_QUERY_OSV
    assert has_issues is True
    assert "未完成" in section


def test_build_security_report_distinct_counting() -> None:
    da.collect_package_refs = lambda root: [da.PackageRef("uv", "uv", "0.9.18")]
    da.collect_commit_refs = lambda root: [da.CommitRef("nvm (nvm-sh/nvm)", "a" * 40)]
    da.collect_unchecked = lambda root: []

    def fake(query, label, *, timeout, max_pages, max_response_bytes):
        if "package" in query:
            return [
                {"id": "GHSA-1", "summary": "dup", "aliases": ["CVE-2026-1"]},
                {"id": "PYSEC-1", "summary": "dup", "aliases": ["CVE-2026-1"]},
            ]
        return [{"id": "OSV-C-1", "summary": "same", "aliases": ["CVE-2026-1"]}]

    da.query_osv = fake
    try:
        section, has_issues = build_security_report(
            ROOT, timeout=5, max_pages=5, max_response_bytes=100_000
        )
    finally:
        da.query_osv = _ORIG_QUERY_OSV
        da.collect_package_refs = _ORIG_COLLECT_PACKAGE
        da.collect_commit_refs = _ORIG_COLLECT_COMMIT
        da.collect_unchecked = _ORIG_COLLECT_UNCHECKED
    assert has_issues is True
    assert "2 个受影响目标" in section
    assert "3 条 OSV 漏洞记录" in section
    assert "去重后 1 个独立漏洞" in section


def test_main_offline_default_no_network() -> None:
    called: list[bool] = []

    def boom(*args, **kwargs):
        called.append(True)
        raise AssertionError("network must not be called in offline mode")

    with tempfile.TemporaryDirectory() as tmpdir:
        out = Path(tmpdir) / "report.md"
        da._http_post = boom
        saved_argv = sys.argv
        try:
            sys.argv = ["dependency-audit.py", "--output", str(out)]
            rc = main()
        finally:
            sys.argv = saved_argv
            da._http_post = _ORIG_HTTP_POST
        assert rc == 0
        assert called == []
        assert out.exists()
        text = out.read_text(encoding="utf-8")
        assert "月度依赖审计" in text
        assert "已知漏洞查询" not in text


def _run_main_with_http(out: Path, http_post) -> int:
    da._http_post = http_post
    saved_argv = sys.argv
    try:
        sys.argv = ["dependency-audit.py", "--check-security", "--output", str(out)]
        return main()
    finally:
        sys.argv = saved_argv
        da._http_post = _ORIG_HTTP_POST


def test_main_check_security_clean() -> None:
    with tempfile.TemporaryDirectory() as tmpdir:
        out = Path(tmpdir) / "report.md"
        rc = _run_main_with_http(out, lambda *a, **k: b'{"vulns": []}')
        assert rc == 0
        text = out.read_text(encoding="utf-8")
        assert "已知漏洞查询（OSV）" in text
        assert "OSV 未记录已知漏洞" in text


def test_main_check_security_found_nonzero_report_retained() -> None:
    def fake(url, payload, timeout, max_response_bytes):
        data = json.loads(payload.decode("utf-8"))
        if "package" in data:
            return json.dumps(
                {"vulns": [{"id": "PYSEC-2024-999", "summary": "known vuln"}]}
            ).encode("utf-8")
        return b'{"vulns": []}'

    with tempfile.TemporaryDirectory() as tmpdir:
        out = Path(tmpdir) / "report.md"
        rc = _run_main_with_http(out, fake)
        assert rc == 1
        assert out.exists()
        text = out.read_text(encoding="utf-8")
        assert "PYSEC-2024-999" in text
        assert "发现" in text


def test_main_check_security_incomplete_nonzero_report_retained() -> None:
    def fail(*args, **kwargs):
        raise OsvError("OSV HTTP 错误 500")

    with tempfile.TemporaryDirectory() as tmpdir:
        out = Path(tmpdir) / "report.md"
        rc = _run_main_with_http(out, fail)
        assert rc == 1
        assert out.exists()
        text = out.read_text(encoding="utf-8")
        assert "未完成" in text
        assert "不代表无风险" in text


def test_main_check_security_error_object_nonzero_report_retained() -> None:
    with tempfile.TemporaryDirectory() as tmpdir:
        out = Path(tmpdir) / "report.md"
        rc = _run_main_with_http(out, lambda *a, **k: b'{"error": "upstream unavailable"}')
        assert rc == 1
        assert out.exists()
        text = out.read_text(encoding="utf-8")
        assert "未完成" in text
        assert "存在已知漏洞或未完成" in text
        assert "未发现已知漏洞" not in text


def test_main_check_security_unknown_field_nonzero_report_retained() -> None:
    with tempfile.TemporaryDirectory() as tmpdir:
        out = Path(tmpdir) / "report.md"
        rc = _run_main_with_http(
            out, lambda *a, **k: b'{"message": "upstream unavailable"}'
        )
        assert rc == 1
        assert out.exists()
        text = out.read_text(encoding="utf-8")
        assert "未完成" in text
        assert "存在已知漏洞或未完成" in text
        assert "未发现已知漏洞" not in text


if __name__ == "__main__":
    test_parse_requirements_pins_exact_only()
    test_classify_requirements_lines_unsupported()
    test_classify_commit_pins_nonhex_reported()
    test_distinct_vulns_union()
    test_collect_package_refs_real_root()
    test_collect_commit_refs_real_root()
    test_split_vulns_withdrawn()
    test_query_osv_no_vulns()
    test_query_osv_pagination()
    test_query_osv_pagination_limit()
    test_query_osv_http_error()
    test_query_osv_format_failure()
    test_parse_page_malformed_shape()
    test_parse_page_falsy_vulns_rejected()
    test_parse_page_missing_vulns_defaults_empty()
    test_parse_page_error_object_rejected_no_body_leak()
    test_parse_page_unknown_fields_rejected()
    test_parse_page_empty_next_page_token_completes()
    test_query_osv_error_object_raises()
    test_http_post_incomplete_read_normalized()
    test_parse_args_rejects_nonfinite_timeout()
    test_split_vulns_invalid_withdrawn()
    test_split_vulns_missing_or_null_active()
    test_build_security_report_clean()
    test_build_security_report_found()
    test_build_security_report_withdrawn_only()
    test_build_security_report_incomplete()
    test_build_security_report_distinct_counting()
    test_main_offline_default_no_network()
    test_main_check_security_clean()
    test_main_check_security_found_nonzero_report_retained()
    test_main_check_security_incomplete_nonzero_report_retained()
    test_main_check_security_error_object_nonzero_report_retained()
    test_main_check_security_unknown_field_nonzero_report_retained()
    print("Dependency audit unit tests passed.")
