#!/usr/bin/env python3
"""Check that the shards' combined coverage kept every shard's coverage. Standard library only.

    python3 scripts/ci/coverage_union.py lines/*.json --out coverage.json
    python3 scripts/ci/coverage_compare.py coverage.json shards/ios-shard-*/coverage.json \
        [--expect unit,ui-1,ui-2,ui-3] [--summary "$GITHUB_STEP_SUMMARY"]

The coverage gate reads the combined report, which must be the union of the shards: a line any shard
ran counts as covered. (It caught `xcresulttool merge` losing covered lines on run 37914825017, which
is why the union is now taken by coverage_union.py.) This compares each first-party file's covered lines
in the merged report with the best of the single-shard reports (files as coverage_gate.py counts
them) and fails when the merged report has fewer, because the gate would then be judging less than
the tests ran. It also fails when a shard's report is missing, unreadable or holds no executable
line, since that shard's coverage would silently drop out of the merge.

A shard's name is its folder's, without the `ios-shard-` prefix.

With --baseline, it instead compares the merged report with the serial pipeline's (`ios-serial`,
run on request with `serial_baseline`), so the split is shown to judge the same lines as the single
job it replaced:

    python3 scripts/ci/coverage_compare.py coverage/merged.json --baseline serial/coverage.json

It lists every file the merge covers fewer lines of than the serial run, and fails when the merge's
first-party line coverage is more than BASELINE_TOLERANCE points below the serial run's. Not exact
equality per file: UI tests take timing-dependent paths, so two serial runs of one commit can differ
by a few lines.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import coverage_gate  # noqa: E402

PREFIX = "ios-shard-"
SHOWN = 20
# `Assumption:` two serial runs of one commit differ by less than half a point of first-party line
# coverage; checked by the first serial_baseline run, whose summary prints both percentages.
BASELINE_TOLERANCE = 0.5


def shard_name(path: str) -> str:
    folder = Path(path).parent.name
    return folder[len(PREFIX):] if folder.startswith(PREFIX) else folder


def read(path: str) -> dict | None:
    """The report, or None when it is missing, unreadable or has no executable line at all."""
    try:
        with open(path, encoding="utf-8") as f:
            report = json.load(f)
    except (OSError, json.JSONDecodeError):
        return None
    if not isinstance(report, dict):
        return None
    lines = sum(f.get("executableLines", 0) for t in report.get("targets", []) for f in t.get("files", []))
    return report if lines else None


def percent(files: dict[str, tuple[int, int]]) -> str:
    covered, executable = sum(c for c, _ in files.values()), sum(e for _, e in files.values())
    return f"{100.0 * covered / executable:.1f}% ({covered}/{executable})" if executable else "no first-party lines"


def compare(merged_path: str, shard_paths: list[str], expect: list[str]) -> tuple[list[str], str]:
    """(errors, markdown summary)."""
    errors: list[str] = []
    shards: dict[str, dict[str, tuple[int, int]]] = {}
    for path in sorted(shard_paths):
        name = shard_name(path)
        report = read(path)
        if report is None:
            errors.append(f"shard {name}: its coverage report is missing, unreadable or empty, so its coverage "
                          "is not in the merge; see that shard's job")
            continue
        shards[name] = coverage_gate.collect(report)
    for name in expect:
        if name not in shards and not any(e.startswith(f"shard {name}:") for e in errors):
            errors.append(f"shard {name}: no coverage report was uploaded; its job failed before exporting one")

    merged_report = read(merged_path)
    if merged_report is None:
        errors.append(f"the merged coverage report {merged_path} is missing, unreadable or empty")
        return errors, ""
    merged = coverage_gate.collect(merged_report)

    lost: list[str] = []
    for name, files in sorted(shards.items()):
        for path, (covered, _) in files.items():
            in_merge = merged.get(path, (0, 0))[0]
            if in_merge < covered:
                lost.append(f"{path}: {in_merge} lines covered after the merge, {covered} in shard {name}")
    if lost:
        shown = "; ".join(sorted(lost)[:SHOWN]) + (f"; and {len(lost) - SHOWN} more" if len(lost) > SHOWN else "")
        errors.append(f"merging the shards lost coverage in {len(lost)} file(s), so the coverage gate would "
                      f"judge less than the tests ran (xcresulttool merge did not keep the union): {shown}")

    rows = ["### Coverage by shard", "", "| Report | First-party line coverage |", "| --- | --- |"]
    rows += [f"| {name} | {percent(files)} |" for name, files in sorted(shards.items())]
    rows.append(f"| merged | {percent(merged)} |")
    return errors, "\n".join(rows) + "\n\n"


def totals(files: dict[str, tuple[int, int]]) -> tuple[int, int]:
    return sum(c for c, _ in files.values()), sum(e for _, e in files.values())


def compare_baseline(merged_path: str, baseline_path: str) -> tuple[list[str], str]:
    """(errors, markdown summary) for the merged report against the serial run's."""
    errors: list[str] = []
    merged_report, baseline_report = read(merged_path), read(baseline_path)
    if baseline_report is None:
        errors.append(f"the serial run's coverage report {baseline_path} is missing, unreadable or empty; "
                      "see the ios-serial job")
    if merged_report is None:
        errors.append(f"the merged coverage report {merged_path} is missing, unreadable or empty; see ios-report")
    if errors:
        return errors, ""
    merged, baseline = coverage_gate.collect(merged_report), coverage_gate.collect(baseline_report)
    (mc, me), (bc, be) = totals(merged), totals(baseline)
    merged_pct, baseline_pct = 100.0 * mc / me if me else 0.0, 100.0 * bc / be if be else 0.0
    behind = sorted(((covered - merged.get(path, (0, 0))[0], path) for path, (covered, _) in baseline.items()
                     if merged.get(path, (0, 0))[0] < covered), reverse=True)
    rows = ["### Coverage: shards merged against the serial run", "",
            "| Report | First-party line coverage |", "| --- | --- |",
            f"| serial (ios-serial) | {percent(baseline)} |", f"| shards merged | {percent(merged)} |", ""]
    if behind:
        rows += [f"{len(behind)} file(s) have fewer covered lines in the merge than in the serial run:", "",
                 "| File | Lines fewer |", "| --- | ---: |"]
        rows += [f"| `{path}` | {fewer} |" for fewer, path in behind[:SHOWN]]
        rows.append("")
    if merged_pct < baseline_pct - BASELINE_TOLERANCE:
        shown = "; ".join(f"{path} ({fewer} fewer)" for fewer, path in behind[:5])
        errors.append(f"the shards together cover {merged_pct:.1f}% against the serial run's {baseline_pct:.1f}%, "
                      f"more than {BASELINE_TOLERANCE} points less, so the split drops coverage the single job "
                      f"had: {shown or 'no single file behind; files are missing from the merge'}")
    return errors, "\n".join(rows) + "\n"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("merged")
    ap.add_argument("shards", nargs="*")
    ap.add_argument("--expect", default="", help="comma-separated shard names that must all have coverage")
    ap.add_argument("--summary")
    ap.add_argument("--baseline", help="the serial run's coverage report, to compare the merged one with")
    args = ap.parse_args(argv)
    if args.baseline:
        errors, summary = compare_baseline(args.merged, args.baseline)
    else:
        errors, summary = compare(args.merged, args.shards, [n for n in args.expect.split(",") if n])
    print(summary)
    if args.summary and summary:
        with open(args.summary, "a", encoding="utf-8") as f:
            f.write(summary)
    for error in errors:
        print(f"::error::{error}")
    if not errors:
        print("merged coverage matches the serial run's" if args.baseline
              else "merged coverage keeps every shard's coverage")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
