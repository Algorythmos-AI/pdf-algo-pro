"""Tests for coverage_compare.py with synthetic xccov reports.

    uv run --with pytest==8.4.2 pytest -q scripts/ci
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import coverage_compare  # noqa: E402

ROOT = "/Users/runner/work/pdf-algo-pro/pdf-algo-pro"
READER = f"{ROOT}/Packages/Features/Reader/Sources/ReaderFeature/ReaderModel.swift"
CORE = f"{ROOT}/Packages/Core/Sources/Core/Document.swift"
TEST = f"{ROOT}/Packages/Core/Tests/CoreTests/DocumentTests.swift"
EXPECT = ["unit", "ui-1"]


def report(path: Path, files: dict[str, tuple[int, int]]) -> str:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"targets": [{"name": "PDFAlgoPro.app", "files": [
        {"path": p, "coveredLines": c, "executableLines": e} for p, (c, e) in files.items()]}]}))
    return str(path)


def shards(tmp_path: Path) -> list[str]:
    return [report(tmp_path / "ios-shard-unit" / "coverage.json", {CORE: (90, 100), READER: (10, 50), TEST: (5, 5)}),
            report(tmp_path / "ios-shard-ui-1" / "coverage.json", {CORE: (20, 100), READER: (40, 50)})]


def test_a_merge_that_keeps_the_union_passes(tmp_path, capsys):
    merged = report(tmp_path / "coverage.json", {CORE: (92, 100), READER: (45, 50)})
    summary = tmp_path / "summary.md"
    assert coverage_compare.main([merged, *shards(tmp_path), "--expect", "unit,ui-1", "--summary", str(summary)]) == 0
    text = summary.read_text()
    assert "| unit | 66.7% (100/150) |" in text
    assert "| merged | 91.3% (137/150) |" in text


def test_a_merge_with_fewer_covered_lines_than_a_shard_fails(tmp_path, capsys):
    merged = report(tmp_path / "coverage.json", {CORE: (90, 100), READER: (10, 50)})
    errors, _ = coverage_compare.compare(merged, shards(tmp_path), EXPECT)
    assert len(errors) == 1
    assert "lost coverage in 1 file(s)" in errors[0] and "ReaderModel.swift: 10" in errors[0] and "shard ui-1" in errors[0]


def test_a_file_missing_from_the_merge_counts_as_lost(tmp_path):
    merged = report(tmp_path / "coverage.json", {CORE: (90, 100)})
    errors, _ = coverage_compare.compare(merged, shards(tmp_path), EXPECT)
    assert any("ReaderModel.swift: 0 lines covered after the merge" in e for e in errors)


def test_test_code_is_not_compared(tmp_path):
    merged = report(tmp_path / "coverage.json", {CORE: (92, 100), READER: (45, 50), TEST: (0, 5)})
    assert coverage_compare.compare(merged, shards(tmp_path), EXPECT)[0] == []


def test_an_empty_missing_or_unreadable_shard_report_fails(tmp_path):
    merged = report(tmp_path / "coverage.json", {CORE: (92, 100), READER: (45, 50)})
    paths = shards(tmp_path)
    Path(paths[1]).write_text("")
    errors, _ = coverage_compare.compare(merged, paths, EXPECT + ["ui-2"])
    assert any(e.startswith("shard ui-1: its coverage report is missing, unreadable or empty") for e in errors)
    assert any(e.startswith("shard ui-2: no coverage report was uploaded") for e in errors)
    report(Path(paths[1]), {})
    errors, _ = coverage_compare.compare(merged, paths, EXPECT)
    assert any(e.startswith("shard ui-1:") for e in errors)


def test_an_empty_merged_report_fails(tmp_path):
    merged = tmp_path / "coverage.json"
    merged.write_text("{}")
    errors, summary = coverage_compare.compare(str(merged), shards(tmp_path), EXPECT)
    assert any("merged coverage report" in e for e in errors) and summary == ""
