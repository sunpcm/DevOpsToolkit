#!/usr/bin/env python3
"""Select and validate traceable VM-smoke evidence for a release."""

from __future__ import annotations

import argparse
import json
import re
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any


SHA_RE = re.compile(r"^[0-9a-f]{40}$")
EXPECTED_REPORT = {
    "schema": "1",
    "result": "passed",
    "source_dirty": "false",
    "ansible_core": "2.21.4",
    "ubuntu_images": "22.04,24.04",
    "test_faults": "1",
    "cleanup_status": "passed",
}


def utc_timestamp(value: str) -> datetime:
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        raise ValueError("timestamp must include a timezone")
    return parsed.astimezone(timezone.utc)


def select_run(data: Any, source_sha: str, max_age_days: int) -> str:
    if not isinstance(data, dict) or not isinstance(data.get("workflow_runs"), list):
        raise TypeError("workflow run response must contain workflow_runs")
    cutoff = datetime.now(timezone.utc) - timedelta(days=max_age_days)
    for run in data["workflow_runs"]:
        if not isinstance(run, dict):
            raise TypeError("workflow run entry must be an object")
        if (
            run.get("head_sha") == source_sha
            and run.get("conclusion") == "success"
            and run.get("event") in {"schedule", "workflow_dispatch"}
            and utc_timestamp(str(run.get("created_at", ""))) >= cutoff
        ):
            run_id = run.get("id")
            if not isinstance(run_id, int) or run_id <= 0:
                raise TypeError("workflow run id must be a positive integer")
            return str(run_id)
    raise ValueError("no recent successful VM smoke run matches the release commit")


def load_report(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        key, separator, value = line.partition("=")
        if not separator or not key or key in result:
            raise ValueError(f"invalid or duplicate report field: {line}")
        result[key] = value
    return result


def validate_report(values: dict[str, str], source_sha: str) -> None:
    expected = {**EXPECTED_REPORT, "source_sha": source_sha}
    mismatches = {
        key: {"expected": value, "actual": values.get(key)}
        for key, value in expected.items()
        if values.get(key) != value
    }
    if mismatches:
        raise ValueError(f"VM smoke report mismatch: {mismatches}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    select = subparsers.add_parser("select-run")
    select.add_argument("--runs", type=Path, required=True)
    select.add_argument("--sha", required=True)
    select.add_argument("--max-age-days", type=int, default=8)
    report = subparsers.add_parser("verify-report")
    report.add_argument("--report", type=Path, required=True)
    report.add_argument("--sha", required=True)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if not SHA_RE.fullmatch(args.sha):
            raise ValueError("source SHA must be 40 lowercase hex characters")
        if args.command == "select-run":
            if args.max_age_days < 1:
                raise ValueError("max age must be positive")
            data = json.loads(args.runs.read_text(encoding="utf-8"))
            print(select_run(data, args.sha, args.max_age_days))
        else:
            validate_report(load_report(args.report), args.sha)
    except (KeyError, OSError, TypeError, ValueError, json.JSONDecodeError) as exc:
        print(f"VM evidence verification failed: {exc}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
