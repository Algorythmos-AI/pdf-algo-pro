#!/usr/bin/env python3
"""Line-coverage gate for the ci.yml `ios` job (ADR-0014). Standard library only.

    xcrun xccov view --report --json Tests.xcresult > coverage.json
    python3 scripts/ci/coverage_gate.py coverage.json --min 80

Counts executable lines in first-party targets, excluding test bundles, generated code and
SwiftUI previews (files whose names end in `+Previews.swift` or live under `Generated/`).
Fails when overall coverage, or coverage of any first-party target, is below the threshold.
"""
from __future__ import annotations

import argparse
import json
import sys

EXCLUDED_SUFFIXES = ("+Previews.swift", "Previews.swift")
EXCLUDED_PARTS = ("/Generated/", "/Tests/", "/.build/", "/DerivedData/")


def included(path: str) -> bool:
    return not path.endswith(EXCLUDED_SUFFIXES) and not any(part in path for part in EXCLUDED_PARTS)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("report")
    ap.add_argument("--min", type=float, default=80.0)
    args = ap.parse_args()

    report = json.load(open(args.report, encoding="utf-8"))
    total_cov = total_exec = 0
    failures = []
    for target in report.get("targets", []):
        name = target.get("name", "")
        if name.endswith((".xctest", "Tests")):
            continue
        cov = sum(f.get("coveredLines", 0) for f in target.get("files", []) if included(f.get("path", "")))
        exe = sum(f.get("executableLines", 0) for f in target.get("files", []) if included(f.get("path", "")))
        if not exe:
            continue
        pct = 100.0 * cov / exe
        total_cov, total_exec = total_cov + cov, total_exec + exe
        print(f"{name}: {pct:.1f}% ({cov}/{exe})")
        if pct < args.min:
            failures.append(f"{name} is at {pct:.1f}%, below {args.min:.0f}%")

    if not total_exec:
        print("::error::no first-party executable lines found in the coverage report")
        return 1
    overall = 100.0 * total_cov / total_exec
    print(f"overall: {overall:.1f}% ({total_cov}/{total_exec})")
    if overall < args.min:
        failures.append(f"overall coverage is {overall:.1f}%, below {args.min:.0f}%")
    for f in failures:
        print(f"::error::{f}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
