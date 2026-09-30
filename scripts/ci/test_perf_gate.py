"""Tests for perf_gate.py with synthetic metrics and the real budget table.

    uv run --with pytest==8.4.2 pytest -q scripts/ci
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import perf_gate  # noqa: E402

CLOCK = "com.apple.dt.XCTMetric_Clock.time.monotonic"
LAUNCH = "com.apple.dt.XCTMetric_ApplicationLaunch-AppLaunch.duration"


def result(identifier: str, values: list[float], metric: str = CLOCK, unit: str = "s") -> dict:
    return {"testIdentifier": identifier, "testRuns": [{"metrics": [
        {"identifier": metric, "displayName": "metric", "measurements": values, "unitOfMeasurement": unit}]}]}


def write(tmp_path: Path, tests: list[dict]) -> Path:
    path = tmp_path / "metrics.json"
    path.write_text(json.dumps(tests))
    return path


def test_every_test_has_its_budget_row_in_the_document():
    table = perf_gate.budgets(perf_gate.BUDGETS.read_text(encoding="utf-8"))
    assert set(perf_gate.TESTS.values()) <= set(table)
    assert table["Open a 20-page PDF to first page visible"] == 0.15
    assert table["Scan → searchable PDF, 10 pages"] == 8


def test_budgets_read_durations_in_milliseconds_and_seconds_and_skip_other_rows():
    table = perf_gate.budgets(
        "| Budget | p50 | p95 |\n|---|---|---|\n| Fast | 150 ms | 300 ms |\n| Slow | 1.2 s | 2 s |\n"
        "| Rate | 2 pages per second | 1 page per second |\nNot a | table\n")
    assert table == {"Fast": 0.15, "Slow": 1.2}


def test_the_median_of_the_iterations_is_compared_with_the_p50_and_tolerance(tmp_path):
    save = "EnginePerformanceTests/testSaveAfterAnEditIn500Pages()"
    search = "EnginePerformanceTests/testSearchA1000DocumentLibrary()"
    metrics = write(tmp_path, [
        result(save, [0.9, 0.35, 0.36]),          # median 360 ms: 120% of 300 ms exactly, within
        result(search, [0.2, 0.13, 0.12]),        # median 130 ms: over 120 ms
        result("LaunchPerformanceTests/testColdLaunchToTheFirstFrame()", [300, 350, 320], LAUNCH, "ms"),
        result("OtherTests/testSomething()", [1.0]),
    ])
    assert perf_gate.main([str(metrics), "--out", str(tmp_path)]) == 0
    rows = {row["test"]: row for row in json.loads((tmp_path / "performance.json").read_text())}
    assert rows[save]["status"] == "within" and abs(rows[save]["median"] - 0.36) < 1e-9
    assert rows[search]["status"] == "over"
    assert rows["LaunchPerformanceTests/testColdLaunchToTheFirstFrame()"]["median"] == 0.32
    assert rows["OtherTests/testSomething()"]["status"] == "no budget row"
    assert rows["RetrievalPerformanceTests/testRetrievalOver500Pages()"]["status"] == "not measured"
    assert "| Search across a 1,000-document library (index warm) | 100 ms | 130 ms | 130% | over |" in (
        tmp_path / "performance.md").read_text()


def test_enforce_fails_only_when_something_is_over(tmp_path):
    save = "EnginePerformanceTests/testSaveAfterAnEditIn500Pages()"
    assert perf_gate.main([str(write(tmp_path, [result(save, [0.1, 0.1, 0.1])])), "--out", str(tmp_path), "--enforce"]) == 0
    assert perf_gate.main([str(write(tmp_path, [result(save, [1, 1, 1])])), "--out", str(tmp_path), "--enforce"]) == 1


def test_a_missing_budget_row_is_an_error(tmp_path):
    budgets = tmp_path / "budgets.md"
    budgets.write_text("| Budget | p50 |\n|---|---|\n| Something else | 1 s |\n")
    assert perf_gate.main([str(write(tmp_path, [])), "--budgets", str(budgets), "--out", str(tmp_path)]) == 2
