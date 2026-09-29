#!/usr/bin/env python3
"""Line-coverage gate for the ci.yml `ios` job (ADR-0014). Standard library only.

    xcrun xccov view --report --json Tests.xcresult > coverage.json
    python3 scripts/ci/coverage_gate.py coverage.json --min 80

Coverage is grouped by source module, from each file's path (`Packages/.../Sources/<Module>/` or
`App/PDFAlgoPro/`), not by the binary that ran it: a package's code is compiled into its own test
bundle and into the app, and both runs count. A file reported by several binaries keeps its best
result. Test code, test support targets, generated code and SwiftUI previews (`*Previews.swift`) are
excluded. Fails when overall coverage, or any module's coverage, is below the threshold.
"""
from __future__ import annotations

import argparse
import json
import re
import sys

EXCLUDED_SUFFIXES = ("Previews.swift",)
EXCLUDED_PARTS = ("/Generated/", "/Tests/", "/UITests/", "TestSupport/", "/.build/", "/DerivedData/", "/SourcePackages/")
MODULE = re.compile(r"/Packages/(?:[^/]+/)*?Sources/([^/]+)/|/App/(PDFAlgoPro)/")


def module_of(path: str) -> str | None:
    if path.endswith(EXCLUDED_SUFFIXES) or any(part in path for part in EXCLUDED_PARTS):
        return None
    m = MODULE.search(path)
    if not m:
        return None
    return m.group(1) or "App"


def collect(report: dict) -> dict[str, tuple[int, int]]:
    """Best (covered, executable) per file path across every target in the report."""
    files: dict[str, tuple[int, int]] = {}
    for target in report.get("targets", []):
        for f in target.get("files", []):
            path = f.get("path", "")
            if module_of(path) is None:
                continue
            covered, executable = f.get("coveredLines", 0), f.get("executableLines", 0)
            best = files.get(path)
            if best is None or covered > best[0]:
                files[path] = (covered, executable)
    return files


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("report")
    ap.add_argument("--min", type=float, default=80.0)
    args = ap.parse_args(argv)

    report = json.load(open(args.report, encoding="utf-8"))
    modules: dict[str, list[int]] = {}
    for path, (covered, executable) in collect(report).items():
        totals = modules.setdefault(module_of(path) or "?", [0, 0])
        totals[0] += covered
        totals[1] += executable

    total_cov = sum(c for c, _ in modules.values())
    total_exec = sum(e for _, e in modules.values())
    if not total_exec:
        print("::error::no first-party executable lines found in the coverage report")
        return 1
    failures = []
    for name in sorted(modules):
        covered, executable = modules[name]
        if not executable:
            continue
        pct = 100.0 * covered / executable
        print(f"{name}: {pct:.1f}% ({covered}/{executable})")
        if pct < args.min:
            failures.append(f"{name} is at {pct:.1f}%, below {args.min:.0f}%")
    overall = 100.0 * total_cov / total_exec
    print(f"overall: {overall:.1f}% ({total_cov}/{total_exec})")
    if overall < args.min:
        failures.append(f"overall coverage is {overall:.1f}%, below {args.min:.0f}%")
    for f in failures:
        print(f"::error::{f}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
