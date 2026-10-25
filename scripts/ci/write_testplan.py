#!/usr/bin/env python3
"""Write the test plans from the generated Xcode project. Standard library only.

    xcodegen generate && python3 scripts/ci/write_testplan.py

XcodeGen does not generate test plans, and a plan refers to project targets by their generated IDs,
so the plans are derived from the project each time it is generated (locally and in CI):

  * PDFAlgoPro.xctestplan, run on every pull request: every local package's test target (found from
    each Package.swift), the app's unit tests and the UI tests, with code coverage on. Classes whose
    name ends in PerformanceTests are skipped, and so are those ending in StoreScreenshotTests, which
    take the App Store screenshots on a device on request (docs/app-store-strategy.md).
  * Performance.xctestplan, run on a schedule and on request (P9): only those classes, without
    coverage, so the timings are not slowed by instrumentation.
  * StoreScreenshots.xctestplan, run on request on a device: only the StoreScreenshotTests classes,
    without coverage.

Run it again whenever a package, test target or performance class is added, removed or renamed.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / "PDFAlgoPro.xcodeproj" / "project.pbxproj"
PLAN = ROOT / "PDFAlgoPro.xctestplan"
PERFORMANCE_PLAN = ROOT / "Performance.xctestplan"
STORE_SCREENSHOTS_PLAN = ROOT / "StoreScreenshots.xctestplan"
# Seconds a single test may run in the pull request plan before it fails (see main()).
TEST_ALLOWANCE = 300
PERFORMANCE_CLASS = re.compile(r"\bclass\s+(\w+PerformanceTests)\b")
# Run on request only, on a device: never in the pull request plan.
STORE_SCREENSHOT_CLASS = re.compile(r"\bclass\s+(\w*StoreScreenshotTests)\b")
APP, UNIT_TESTS, UI_TESTS = "PDFAlgoPro", "PDFAlgoProTests", "PDFAlgoProUITests"


def target_id(pbxproj: str, name: str) -> str:
    m = re.search(rf"^\s*([0-9A-F]{{24}}) /\* {re.escape(name)} \*/ = {{\s*isa = PBXNativeTarget;", pbxproj, re.M)
    if not m:
        raise SystemExit(f"target {name} not found in {PROJECT}; run xcodegen generate first")
    return m.group(1)


def package_test_targets() -> list[tuple[str, str]]:
    found = []
    for manifest in sorted((ROOT / "Packages").rglob("Package.swift")):
        if ".build" in manifest.parts:
            continue
        for name in re.findall(r'\.testTarget\(\s*name:\s*"([^"]+)"', manifest.read_text(encoding="utf-8")):
            found.append((manifest.parent.relative_to(ROOT).as_posix(), name))
    return found


def performance_classes(folder: Path, pattern: re.Pattern[str] = PERFORMANCE_CLASS) -> list[str]:
    """The XCTest classes in a test target's sources whose name matches `pattern` (PerformanceTests)."""
    names: set[str] = set()
    for source in folder.rglob("*.swift"):
        names.update(pattern.findall(source.read_text(encoding="utf-8")))
    return sorted(names)


def write(path: Path, plan: dict) -> None:
    path.write_text(json.dumps(plan, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    pbxproj = PROJECT.read_text(encoding="utf-8")
    entries = [({"containerPath": f"container:{path}", "identifier": name, "name": name},
                ROOT / path / "Tests" / name) for path, name in package_test_targets()]
    for name, folder in ((UNIT_TESTS, "App/Tests"), (UI_TESTS, "App/UITests")):
        entries.append(({"containerPath": "container:PDFAlgoPro.xcodeproj",
                         "identifier": target_id(pbxproj, name), "name": name}, ROOT / folder))
    variables = {"containerPath": "container:PDFAlgoPro.xcodeproj",
                 "identifier": target_id(pbxproj, APP), "name": APP}

    targets, performance, screenshots = [], [], []
    for target, folder in entries:
        classes = performance_classes(folder)
        shots = performance_classes(folder, STORE_SCREENSHOT_CLASS)
        skipped = sorted(classes + shots)
        targets.append({"skippedTests": skipped, "target": target} if skipped else {"target": target})
        if classes:
            performance.append({"selectedTests": classes, "target": target})
        if shots:
            screenshots.append({"selectedTests": shots, "target": target})
    write(PLAN, {
        "configurations": [{"id": "4F1C2A00-0000-4000-8000-000000000001", "name": "Default", "options": {}}],
        # A test that hangs fails by name after the allowance, instead of holding the job until its
        # 60-minute timeout cancels it with no verdict. XCTest rounds the allowance up to whole
        # minutes. The slowest UI test took 69 s on CI (run 414); Swift Testing suites keep their own
        # .timeLimit traits.
        "defaultOptions": {"codeCoverage": True, "defaultTestExecutionTimeAllowance": TEST_ALLOWANCE,
                           "targetForVariableExpansion": variables, "testTimeoutsEnabled": True},
        "testTargets": targets,
        "version": 1,
    })
    write(PERFORMANCE_PLAN, {
        "configurations": [{"id": "4F1C2A00-0000-4000-8000-000000000002", "name": "Default", "options": {}}],
        "defaultOptions": {"codeCoverage": False, "targetForVariableExpansion": variables},
        "testTargets": performance,
        "version": 1,
    })
    write(STORE_SCREENSHOTS_PLAN, {
        "configurations": [{"id": "4F1C2A00-0000-4000-8000-000000000003", "name": "Default", "options": {}}],
        # The device's model can take a while to answer a screenshot's question.
        "defaultOptions": {"codeCoverage": False, "defaultTestExecutionTimeAllowance": TEST_ALLOWANCE,
                           "targetForVariableExpansion": variables, "testTimeoutsEnabled": True},
        "testTargets": screenshots,
        "version": 1,
    })
    print(f"wrote {PLAN.name} with {len(targets)} test targets, {PERFORMANCE_PLAN.name} with "
          f"{sum(len(t['selectedTests']) for t in performance)} performance classes and "
          f"{STORE_SCREENSHOTS_PLAN.name} with {sum(len(t['selectedTests']) for t in screenshots)} class(es)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
