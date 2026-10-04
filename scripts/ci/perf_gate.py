#!/usr/bin/env python3
"""Compare the Performance test plan's results with docs/performance-budgets.md. Standard library only.

    xcrun xcresulttool get test-results metrics --path Performance.xcresult > metrics.json
    python3 scripts/ci/perf_gate.py metrics.json [--enforce]

Each performance test is named after a row of the budget table (TESTS below). For each one, the
median of its iterations is compared with the row's p50 budget, allowing 120% by default. The
tolerance is an `Assumption:` recorded in the budgets document; the simulator is not the baseline
iPhone, so these runs show trends and large regressions, and device runs give the timings.

Writes reports/performance.md and reports/performance.json. Exits 0 unless --enforce is given and a
measurement is over its budget. It always exits 2 when a test's budget row is missing from the
document, so the two cannot drift apart.
"""
from __future__ import annotations

import argparse
import json
import re
import statistics
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BUDGETS = ROOT / "docs" / "performance-budgets.md"

# Test identifier (as xcresulttool reports it) -> the budget row it measures (first column, verbatim).
TESTS = {
    "LaunchPerformanceTests/testColdLaunchToTheFirstFrame()": "Cold launch to first frame (baseline iPhone)",
    "EnginePerformanceTests/testOpenA20PagePDFToTheFirstPage()": "Open a 20-page PDF to first page visible",
    "EnginePerformanceTests/testOpenA500PagePDFToTheFirstPage()": "Open a 500-page PDF to first page visible",
    "EnginePerformanceTests/testRenderThe100PageThumbnailGrid()": "Page thumbnail grid (100 pages) populated",
    "EnginePerformanceTests/testSaveAfterAnEditIn500Pages()": "Save after an edit (500-page PDF)",
    "EnginePerformanceTests/testEditALineOfTextIn500Pages()": "Edit a line of text (500-page PDF)",
    "EnginePerformanceTests/testSearchA1000DocumentLibrary()": "Search across a 1,000-document library (index warm)",
    "EnginePerformanceTests/testScanTenPagesToASearchablePDF()": "Scan → searchable PDF, 10 pages",
    "RetrievalPerformanceTests/testRetrievalOver500Pages()": "Retrieval over a 500-page PDF (chunks for an answer)",
}
# The metric each kind of test reports; the first one present is used.
METRICS = ("com.apple.dt.XCTMetric_Clock.time.monotonic", "com.apple.dt.XCTMetric_ApplicationLaunch-AppLaunch.duration")
DURATION = re.compile(r"^\s*(\d+(?:\.\d+)?)\s*(ms|s)\s*$")


def budgets(markdown: str) -> dict[str, float]:
    """Budget row name -> p50 in seconds, for every table row whose p50 is a duration."""
    found: dict[str, float] = {}
    for line in markdown.splitlines():
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if len(cells) < 2 or not line.lstrip().startswith("|"):
            continue
        m = DURATION.match(cells[1])
        if m:
            found[cells[0]] = float(m.group(1)) / (1000 if m.group(2) == "ms" else 1)
    return found


def medians(metrics: list[dict]) -> dict[str, tuple[float, str]]:
    """Test identifier -> (median, metric display name), from xcresulttool's metrics output."""
    found: dict[str, tuple[float, str]] = {}
    for test in metrics:
        measured = {m["identifier"]: m for run in test.get("testRuns", []) for m in run.get("metrics", [])}
        for identifier in METRICS:
            metric = measured.get(identifier)
            if metric and metric.get("measurements"):
                values = [float(v) for v in metric["measurements"]]
                if metric.get("unitOfMeasurement") == "ms":
                    values = [v / 1000 for v in values]
                found[test["testIdentifier"]] = (statistics.median(values), metric.get("displayName", identifier))
                break
    return found


def seconds(value: float) -> str:
    return f"{value * 1000:.0f} ms" if value < 1 else f"{value:.2f} s"


def evaluate(measured: dict[str, tuple[float, str]], table: dict[str, float], tolerance: float) -> list[dict]:
    rows = []
    for test, name in TESTS.items():
        budget = table[name]
        row = {"budget": name, "test": test, "p50": budget, "limit": budget * tolerance}
        if test in measured:
            median = measured[test][0]
            row.update(median=median, ratio=median / budget,
                       status="within" if median <= budget * tolerance else "over")
        else:
            row.update(median=None, ratio=None, status="not measured")
        rows.append(row)
    for test in sorted(set(measured) - set(TESTS)):
        rows.append({"budget": None, "test": test, "p50": None, "limit": None,
                     "median": measured[test][0], "ratio": None, "status": "no budget row"})
    return rows


def report(rows: list[dict], tolerance: float) -> str:
    lines = [
        "# Performance report",
        "",
        f"Median of each test's iterations against its p50 budget, allowing {tolerance:.0%}. "
        "Simulator runs show trends; the baseline iPhone gives the timings (docs/performance-budgets.md).",
        "",
        "| Budget | p50 | Median | Ratio | Status |",
        "|---|---|---|---|---|",
    ]
    for row in rows:
        name = row["budget"] or f"`{row['test']}`"
        p50 = seconds(row["p50"]) if row["p50"] is not None else "—"
        median = seconds(row["median"]) if row["median"] is not None else "—"
        ratio = f"{row['ratio']:.0%}" if row["ratio"] is not None else "—"
        lines.append(f"| {name} | {p50} | {median} | {ratio} | {row['status']} |")
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("metrics", type=Path, help="xcresulttool get test-results metrics output")
    parser.add_argument("--budgets", type=Path, default=BUDGETS)
    parser.add_argument("--tolerance", type=float, default=1.2)
    parser.add_argument("--out", type=Path, default=ROOT / "reports")
    parser.add_argument("--enforce", action="store_true", help="exit 1 when a median is over its budget")
    args = parser.parse_args(argv)

    table = budgets(args.budgets.read_text(encoding="utf-8"))
    missing = sorted(set(TESTS.values()) - set(table))
    if missing:
        print(f"budget rows not found in {args.budgets.name}: {missing}", file=sys.stderr)
        return 2
    rows = evaluate(medians(json.loads(args.metrics.read_text(encoding="utf-8"))), table, args.tolerance)
    args.out.mkdir(parents=True, exist_ok=True)
    text = report(rows, args.tolerance)
    (args.out / "performance.md").write_text(text, encoding="utf-8")
    (args.out / "performance.json").write_text(json.dumps(rows, indent=2) + "\n", encoding="utf-8")
    print(text)
    over = [row["budget"] for row in rows if row["status"] == "over"]
    if over:
        print(f"over budget: {', '.join(over)}", file=sys.stderr)
    return 1 if over and args.enforce else 0


if __name__ == "__main__":
    sys.exit(main())
