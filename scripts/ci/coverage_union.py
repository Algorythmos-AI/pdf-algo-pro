#!/usr/bin/env python3
"""The shards' coverage as one report: a line counts as covered when any shard ran it. Standard library only.

    xcrun xccov view --archive --json unit.xcresult > lines/unit.json    # one per shard
    python3 scripts/ci/coverage_union.py lines/*.json --out coverage.json \
        [--reports shards/ios-shard-*/coverage.json]

`xcresulttool merge` of the shards' result bundles does not keep that union: on run 37914825017 the
merged report had fewer covered lines than a single shard in 19 files (ScanView.swift: 640 after the
merge, 707 in the unit shard), and the coverage gate judged less than the tests ran. So the union is
taken here, line by line, from each shard's per-line archive (`xccov view --archive --json`, a map
from each file's path to its lines, each with `line`, `isExecutable` and `executionCount`).

The output has the shape of `xccov view --report --json` that coverage_gate.py and
coverage_compare.py read: one target whose files carry `path`, `coveredLines`, `executableLines` and
`lineCoverage`.

--reports checks the union against xccov's own per-shard reports: every first-party file a shard's
report counts must be in the union with the same number of executable lines. A difference means the
archive was read wrongly, and the gate would judge a wrong total, so it fails rather than warns.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import coverage_gate  # noqa: E402

SHOWN = 20


def lines_of(entry) -> list:
    """A file's lines, whether the archive gives them as a list or under "lines"."""
    if isinstance(entry, list):
        return entry
    if isinstance(entry, dict) and isinstance(entry.get("lines"), list):
        return entry["lines"]
    return []


def read_archive(path: str) -> dict[str, tuple[set[int], set[int]]]:
    """{file path: (executable line numbers, covered line numbers)} from one shard's archive."""
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, dict):
        raise ValueError(f"{path}: expected a map from file paths to their lines, found {type(data).__name__}")
    files: dict[str, tuple[set[int], set[int]]] = {}
    for file_path, entry in data.items():
        executable: set[int] = set()
        covered: set[int] = set()
        for line in lines_of(entry):
            if not isinstance(line, dict) or not line.get("isExecutable"):
                continue
            number = line.get("line")
            if not isinstance(number, int):
                continue
            executable.add(number)
            count = line.get("executionCount")
            if isinstance(count, int) and count > 0:
                covered.add(number)
        files[file_path] = (executable, covered)
    return files


def union(archives: list[dict[str, tuple[set[int], set[int]]]]) -> dict[str, tuple[set[int], set[int]]]:
    merged: dict[str, tuple[set[int], set[int]]] = {}
    for archive in archives:
        for path, (executable, covered) in archive.items():
            known = merged.setdefault(path, (set(), set()))
            known[0].update(executable)
            known[1].update(covered)
    return merged


def report(files: dict[str, tuple[set[int], set[int]]]) -> dict:
    entries = []
    for path in sorted(files):
        executable, covered = files[path]
        if not executable:
            continue
        hit = len(covered & executable)
        entries.append({"path": path, "name": Path(path).name, "coveredLines": hit,
                        "executableLines": len(executable), "lineCoverage": hit / len(executable)})
    return {"targets": [{"name": "shards (union of covered lines)", "files": entries}]}


def check(files: dict[str, tuple[set[int], set[int]]], report_paths: list[str]) -> list[str]:
    """Differences between the union and xccov's per-shard reports, for the files the gate counts."""
    problems: list[str] = []
    for report_path in report_paths:
        try:
            with open(report_path, encoding="utf-8") as f:
                shard = coverage_gate.collect(json.load(f))
        except (OSError, json.JSONDecodeError) as error:
            problems.append(f"{report_path}: cannot read it ({error})")
            continue
        for path, (_, executable) in shard.items():
            if path not in files:
                problems.append(f"{path}: in {report_path} but not in any shard's archive")
            elif len(files[path][0]) != executable:
                problems.append(f"{path}: {len(files[path][0])} executable lines in the archives, "
                                f"{executable} in {report_path}")
    return problems


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("archives", nargs="+", help="`xccov view --archive --json` output, one per shard")
    ap.add_argument("--out", required=True, help="where to write the report")
    ap.add_argument("--reports", nargs="*", default=[], help="the shards' `xccov view --report --json` output")
    args = ap.parse_args(argv)

    archives = []
    for path in args.archives:
        try:
            archives.append(read_archive(path))
        except (OSError, json.JSONDecodeError, ValueError) as error:
            print(f"::error::Cannot read the coverage archive {path}: {error}")
            return 1
    files = union(archives)
    if not any(executable for executable, _ in files.values()):
        print("::error::The coverage archives hold no executable line; see the shards' xccov output")
        return 1
    problems = check(files, args.reports)
    if problems:
        shown = "; ".join(problems[:SHOWN]) + (f"; and {len(problems) - SHOWN} more" if len(problems) > SHOWN else "")
        print(f"::error::The union of the shards' coverage does not match their own reports in "
              f"{len(problems)} file(s), so it is not written: {shown}")
        return 1
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(report(files), f)
    covered = sum(len(c & e) for e, c in files.values())
    executable = sum(len(e) for e, _ in files.values())
    print(f"union of {len(archives)} shard(s): {covered}/{executable} lines covered in {len(files)} files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
