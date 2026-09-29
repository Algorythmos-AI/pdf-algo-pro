"""Tests for coverage_gate.py with synthetic xccov reports.

    uv run --with pytest==8.4.2 pytest -q scripts/ci
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import coverage_gate  # noqa: E402

ROOT = "/Users/runner/work/pdf-algo-pro/pdf-algo-pro"


def report(tmp_path: Path, targets: list[dict]) -> str:
    path = tmp_path / "coverage.json"
    path.write_text(json.dumps({"targets": targets}))
    return str(path)


def file(path: str, covered: int, executable: int) -> dict:
    return {"path": f"{ROOT}/{path}", "coveredLines": covered, "executableLines": executable}


def test_modules_come_from_paths_and_exclusions_apply():
    assert coverage_gate.module_of(f"{ROOT}/Packages/Core/Sources/Core/Document.swift") == "Core"
    assert coverage_gate.module_of(f"{ROOT}/Packages/Features/Reader/Sources/ReaderFeature/ReaderModel.swift") == "ReaderFeature"
    assert coverage_gate.module_of(f"{ROOT}/App/PDFAlgoPro/AppModel.swift") == "App"
    for excluded in [
        "Packages/Core/Tests/CoreTests/CoreTests.swift", "Packages/Core/Sources/CoreTestSupport/Fakes.swift",
        "Packages/DesignSystem/Sources/DesignSystem/Generated/Tokens.swift", "App/UITests/PDFAlgoProUITests.swift",
        "Packages/Features/Library/Sources/LibraryFeature/LibraryView+Previews.swift",
    ]:
        assert coverage_gate.module_of(f"{ROOT}/{excluded}") is None


def test_best_result_per_file_across_binaries(tmp_path, capsys):
    path = report(tmp_path, [
        {"name": "CoreTests.xctest", "files": [file("Packages/Core/Sources/Core/Document.swift", 40, 50)]},
        {"name": "PDFAlgoPro.app", "files": [file("Packages/Core/Sources/Core/Document.swift", 45, 50),
                                             file("App/PDFAlgoPro/AppModel.swift", 9, 10)]},
    ])
    assert coverage_gate.main([path, "--min", "80"]) == 0
    out = capsys.readouterr().out
    assert "Core: 90.0% (45/50)" in out and "App: 90.0% (9/10)" in out and "overall: 90.0% (54/60)" in out


def test_a_module_below_the_threshold_fails(tmp_path, capsys):
    path = report(tmp_path, [{"name": "PDFAlgoPro.app", "files": [
        file("Packages/Search/Sources/Search/LocalSearchIndex.swift", 7, 10),
        file("Packages/Core/Sources/Core/Route.swift", 100, 100),
    ]}])
    assert coverage_gate.main([path, "--min", "80"]) == 1
    assert "Search is at 70.0%" in capsys.readouterr().out


def test_an_empty_report_fails(tmp_path):
    assert coverage_gate.main([report(tmp_path, []), "--min", "80"]) == 1
