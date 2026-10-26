"""Tests for write_testplan.py: the committed plans are the ones it writes, and what the Device plan runs.

    uv run --with pytest==8.4.2 pytest -q scripts/ci
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import write_testplan  # noqa: E402

ROOT = write_testplan.ROOT
APP_TARGETS = (write_testplan.UNIT_TESTS, write_testplan.UI_TESTS)


def pbxproj(ids: dict[str, str]) -> str:
    """A project file with just the native targets' lines the writer reads."""
    return "".join(f"\t\t{identifier} /* {name} */ = {{\n\t\t\tisa = PBXNativeTarget;\n"
                   for name, identifier in ids.items())


def committed_ids() -> dict[str, str]:
    """The generated target IDs, as the committed pull request plan records them (the project itself
    is not in git)."""
    plan = json.loads(write_testplan.PLAN.read_text(encoding="utf-8"))
    ids = {write_testplan.APP: plan["defaultOptions"]["targetForVariableExpansion"]["identifier"]}
    for entry in plan["testTargets"]:
        if entry["target"]["name"] in APP_TARGETS:
            ids[entry["target"]["name"]] = entry["target"]["identifier"]
    return ids


def test_the_committed_plans_are_the_ones_the_writer_writes():
    for path, plan in write_testplan.plans(pbxproj(committed_ids())).items():
        assert path.exists(), f"{path.name} is not committed; run xcodegen generate && {write_testplan.__file__}"
        assert json.loads(path.read_text(encoding="utf-8")) == plan, (
            f"{path.name} is out of date: run xcodegen generate && python3 scripts/ci/write_testplan.py, "
            "then commit the plans")


def test_the_device_plan_runs_the_app_targets_only_without_coverage():
    device = write_testplan.plans(pbxproj(committed_ids()))[write_testplan.DEVICE_PLAN]
    assert [t["target"]["name"] for t in device["testTargets"]] == list(APP_TARGETS)
    options = device["defaultOptions"]
    assert options["codeCoverage"] is False
    assert options["defaultTestExecutionTimeAllowance"] == write_testplan.TEST_ALLOWANCE
    assert {e["key"]: e["value"] for e in options["environmentVariableEntries"]} == {
        "UI_DEVICE": "1", "UI_EVIDENCE": "all"}
    skipped = {t["target"]["name"]: t.get("skippedTests", []) for t in device["testTargets"]}
    assert {"AppTests/SnapshotTests", "StoreSessionTests", "EnginePerformanceTests"} <= set(skipped["PDFAlgoProTests"])
    assert {"StoreScreenshotTests", "LaunchPerformanceTests"} <= set(skipped["PDFAlgoProUITests"])


def test_the_device_plan_is_listed_in_the_scheme():
    project = (ROOT / "project.yml").read_text(encoding="utf-8")
    assert re.search(r"^\s+- path: Device\.xctestplan$", project, re.M)


def test_each_suite_the_device_plan_skips_exists():
    sources = "\n".join(p.read_text(encoding="utf-8") for p in (ROOT / "App" / "Tests").rglob("*.swift"))
    for suite in write_testplan.DEVICE_SKIPPED_UNIT_SUITES:
        *parents, name = suite.split("/")
        assert re.search(rf"\b(struct|class|enum)\s+{name}\b", sources), f"{suite} is not in App/Tests"
        for parent in parents:
            assert re.search(rf"\b(struct|class|enum|extension)\s+{parent}\b", sources), f"{parent} is not in App/Tests"


def test_a_device_ui_test_class_runs_on_the_device_and_never_in_the_pull_request_plan(tmp_path, monkeypatch):
    (tmp_path / "Packages").mkdir()
    (tmp_path / "App" / "Tests").mkdir(parents=True)
    (tmp_path / "App" / "UITests").mkdir(parents=True)
    (tmp_path / "App" / "UITests" / "Scan.swift").write_text(
        "final class ScanDeviceUITests: UITestCase {}\nfinal class ReaderUITests: UITestCase {}\n", encoding="utf-8")
    monkeypatch.setattr(write_testplan, "ROOT", tmp_path)
    written = write_testplan.plans(pbxproj({"PDFAlgoPro": "A" * 24, "PDFAlgoProTests": "B" * 24,
                                            "PDFAlgoProUITests": "C" * 24}))
    pull_request = {t["target"]["name"]: t.get("skippedTests", []) for t in written[write_testplan.PLAN]["testTargets"]}
    device = {t["target"]["name"]: t.get("skippedTests", []) for t in written[write_testplan.DEVICE_PLAN]["testTargets"]}
    assert pull_request["PDFAlgoProUITests"] == ["ScanDeviceUITests"]
    assert device["PDFAlgoProUITests"] == []
    assert device["PDFAlgoProTests"] == sorted(write_testplan.DEVICE_SKIPPED_UNIT_SUITES)
