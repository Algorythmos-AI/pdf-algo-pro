"""Tests for coverage_union.py with synthetic `xccov view --archive --json` output.

    uv run --with pytest==8.4.2 pytest -q scripts/ci
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import coverage_gate  # noqa: E402
import coverage_union  # noqa: E402

ROOT = "/Users/runner/work/pdf-algo-pro/pdf-algo-pro"
SCAN = f"{ROOT}/Packages/Features/Scan/Sources/ScanFeature/ScanView.swift"
CORE = f"{ROOT}/Packages/Core/Sources/Core/Document.swift"


def archive(path: Path, files: dict[str, dict[int, int | None]]) -> str:
    """An archive: for each file, line number → execution count (None for a line that is not code)."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({p: [{"line": n, "isExecutable": c is not None, "executionCount": c,
                                     "subranges": []} for n, c in lines.items()] for p, lines in files.items()}))
    return str(path)


def xccov_report(path: Path, files: dict[str, tuple[int, int]]) -> str:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"targets": [{"name": "PDFAlgoPro.app", "files": [
        {"path": p, "coveredLines": c, "executableLines": e} for p, (c, e) in files.items()]}]}))
    return str(path)


def test_a_line_any_shard_ran_counts_as_covered(tmp_path, capsys):
    # As on run 37914825017: the unit shard ran lines of ScanView the UI shard did not, and the other
    # way round; the union keeps both, where xcresulttool merge kept fewer.
    unit = archive(tmp_path / "unit.json", {SCAN: {1: 3, 2: 0, 3: None, 4: 0}, CORE: {1: 1, 2: 1}})
    ui = archive(tmp_path / "ui.json", {SCAN: {1: 0, 2: 5, 3: None, 4: 0}})
    out = tmp_path / "coverage.json"
    assert coverage_union.main([unit, ui, "--out", str(out)]) == 0
    files = coverage_gate.collect(json.loads(out.read_text()))
    assert files[SCAN] == (2, 3), "lines 1 and 2 covered, of 3 executable lines; line 3 is not code"
    assert files[CORE] == (2, 2)
    assert "union of 2 shard(s): 4/5 distinct first-party lines covered (80.0%)" in capsys.readouterr().out


def test_the_union_must_fit_each_shards_own_report(tmp_path, capsys):
    unit = archive(tmp_path / "unit.json", {SCAN: {1: 1, 2: 0, 3: 0}})
    # xccov's report counts a line once per function around it, so it may count more lines than the
    # archive has (run 37920045109: AssistantView.swift, 359 in the archive, 958 in the report).
    agreeing = xccov_report(tmp_path / "ios-shard-unit" / "coverage.json", {SCAN: (1, 3)})
    nested = xccov_report(tmp_path / "ios-shard-ui-1" / "coverage.json", {SCAN: (2, 8)})
    out = tmp_path / "coverage.json"
    assert coverage_union.main([unit, "--out", str(out), "--reports", agreeing, nested]) == 0
    assert "xccov's reports count lines once per function: best shard per file 2/8 (25.0%)" in \
        capsys.readouterr().out
    # Never fewer: a report counting fewer lines than the archive, or a file the archives lack, means
    # the archive was read wrongly, and the gate would judge a wrong total.
    differing = xccov_report(tmp_path / "ios-shard-ui-2" / "coverage.json", {SCAN: (1, 2), CORE: (1, 1)})
    out.unlink()
    assert coverage_union.main([unit, "--out", str(out), "--reports", differing]) == 1
    printed = capsys.readouterr().out
    assert f"{SCAN}: 3 distinct executable lines in the archives, more than the 2" in printed
    assert f"{CORE}: 1 executable lines in" in printed and "none in any shard's archive" in printed
    assert not out.exists(), "Nothing is written for the gate to judge"


def test_lines_given_under_a_lines_key_are_read_too(tmp_path):
    path = tmp_path / "unit.json"
    path.write_text(json.dumps({SCAN: {"lines": [{"line": 1, "isExecutable": True, "executionCount": 2},
                                                 {"line": 2, "isExecutable": True, "executionCount": 0}]}}))
    assert coverage_union.read_archive(str(path)) == {SCAN: ({1, 2}, {1})}


def test_an_unreadable_or_empty_archive_fails(tmp_path, capsys):
    broken = tmp_path / "broken.json"
    broken.write_text("[1, 2]")
    out = tmp_path / "coverage.json"
    assert coverage_union.main([str(broken), "--out", str(out)]) == 1
    empty = archive(tmp_path / "empty.json", {SCAN: {1: None}})
    assert coverage_union.main([empty, "--out", str(out)]) == 1
    printed = capsys.readouterr().out
    assert "expected a map from file paths" in printed and "hold no executable line" in printed
