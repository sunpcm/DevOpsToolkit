#!/usr/bin/env python3
"""Validate a one-time local VM-smoke report before manual release approval."""

from __future__ import annotations

import argparse
import re
from datetime import datetime, timedelta, timezone
from pathlib import Path


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


def load_report(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        key, separator, value = line.partition("=")
        if not separator or not key or key in result:
            raise ValueError(f"invalid or duplicate report field: {line}")
        result[key] = value
    return result


def validate_report(values: dict[str, str], source_sha: str, max_age_days: int = 8) -> None:
    expected = {**EXPECTED_REPORT, "source_sha": source_sha}
    mismatches = {
        key: {"expected": value, "actual": values.get(key)}
        for key, value in expected.items()
        if values.get(key) != value
    }
    if mismatches:
        raise ValueError(f"VM smoke report mismatch: {mismatches}")
    started = utc_timestamp(values["started_at"])
    finished = utc_timestamp(values["finished_at"])
    now = datetime.now(timezone.utc)
    if not (now - timedelta(days=max_age_days) <= started <= finished <= now):
        raise ValueError("VM smoke report is expired, future-dated or has invalid timestamps")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["verify-report"])
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--sha", required=True)
    parser.add_argument("--max-age-days", type=int, default=8)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        if not SHA_RE.fullmatch(args.sha):
            raise ValueError("source SHA must be 40 lowercase hex characters")
        if args.max_age_days < 1:
            raise ValueError("max age must be positive")
        validate_report(load_report(args.report), args.sha, args.max_age_days)
    except (KeyError, OSError, TypeError, ValueError) as exc:
        print(f"VM evidence verification failed: {exc}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
