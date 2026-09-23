#!/usr/bin/env python3
"""Negative and positive checks for the Release VM-evidence gate."""

from __future__ import annotations

import runpy
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parent.parent
module = runpy.run_path(str(ROOT_DIR / "scripts/verify-vm-evidence.py"))
select_run = module["select_run"]
load_report = module["load_report"]
validate_report = module["validate_report"]
source_sha = "0123456789abcdef0123456789abcdef01234567"
created_at = datetime.now(timezone.utc).isoformat()
runs = {
    "workflow_runs": [
        {
            "id": 123,
            "head_sha": source_sha,
            "conclusion": "success",
            "event": "workflow_dispatch",
            "created_at": created_at,
        }
    ]
}
assert select_run(runs, source_sha, 8) == "123"

old_runs = {
    "workflow_runs": [
        {
            **runs["workflow_runs"][0],
            "created_at": (datetime.now(timezone.utc) - timedelta(days=9)).isoformat(),
        }
    ]
}
try:
    select_run(old_runs, source_sha, 8)
except ValueError:
    pass
else:
    raise AssertionError("expired VM evidence was accepted")

with tempfile.TemporaryDirectory(prefix="devops-toolkit-vm-evidence-") as directory:
    report = Path(directory) / "report.txt"
    report.write_text(
        "\n".join(
            [
                "schema=1",
                "result=passed",
                f"source_sha={source_sha}",
                "source_dirty=false",
                "ansible_core=2.21.4",
                "ubuntu_images=22.04,24.04",
                "test_faults=1",
                "cleanup_status=passed",
                "emergency_cleanup=passed",
            ]
        )
        + "\n",
        encoding="utf-8",
    )
    values = load_report(report)
    validate_report(values, source_sha)
    for field, bad_value in (
        ("result", "failed"),
        ("source_sha", "f" * 40),
        ("source_dirty", "true"),
        ("test_faults", "0"),
        ("cleanup_status", "failed"),
    ):
        tampered = {**values, field: bad_value}
        try:
            validate_report(tampered, source_sha)
        except ValueError:
            pass
        else:
            raise AssertionError(f"tampered VM report field was accepted: {field}")

print("VM smoke Release 证据测试通过。")
