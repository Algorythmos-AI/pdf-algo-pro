#!/usr/bin/env python3
"""Write the test plans from the generated Xcode project. Standard library only.

    xcodegen generate && python3 scripts/ci/write_testplan.py

XcodeGen does not generate test plans, and a plan refers to project targets by their generated IDs,
so the plans are derived from the project each time it is generated (locally and in CI):

  * PDFAlgoPro.xctestplan, run on every pull request: every local package's test target (found from
    each Package.swift), the app's unit tests and the UI tests, with code coverage on. Classes whose
    name ends in PerformanceTests are skipped, and so are those ending in StoreScreenshotTests, which
    take the App Store screenshots on a device on request (docs/app-store-strategy.md), and those
    ending in DeviceUITests, which run only on a device.
  * Performance.xctestplan, run on a schedule and on request (P9): only those classes, without
    coverage, so the timings are not slowed by instrumentation.
  * StoreScreenshots.xctestplan, run on request on a device: only the StoreScreenshotTests classes,
    without coverage.
  * Device.xctestplan, run on an iPhone by scripts/dev/device_tests.sh (docs/process/device-test-run.md):
    the app's unit tests and the UI tests, DeviceUITests classes included, without coverage. Package
    test targets are left out: a device cannot host them ("Tool-hosted testing is unavailable"). So are
    the performance classes, the store screenshots, and the unit suites in DEVICE_SKIPPED_UNIT_SUITES.

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
DEVICE_PLAN = ROOT / "Device.xctestplan"
# Seconds a single test may run in the pull request plan before it fails (see plans()).
TEST_ALLOWANCE = 300
PERFORMANCE_CLASS = re.compile(r"\bclass\s+(\w+PerformanceTests)\b")
# Run on request only, on a device: never in the pull request plan.
STORE_SCREENSHOT_CLASS = re.compile(r"\bclass\s+(\w*StoreScreenshotTests)\b")
# Run on a device only (Device.xctestplan): never in the pull request plan, so the simulator never runs
# them and the shard inventory does not expect them.
DEVICE_CLASS = re.compile(r"\bclass\s+(\w+DeviceUITests)\b")
# Swift Testing suites of the app's unit tests that cannot pass on a device, named as xcodebuild names
# them without the target (ci.yml's iOS 27 job skips the first the same way): the snapshot references
# are recorded on the pinned CI simulator, so they always differ on a device, and StoreKit's test session
# answers only in a run started from Xcode (StoreSessionTests.swift).
DEVICE_SKIPPED_UNIT_SUITES = ("AppTests/SnapshotTests", "StoreSessionTests")
APP, UNIT_TESTS, UI_TESTS = "PDFAlgoPro", "PDFAlgoProTests", "PDFAlgoProUITests"
APP_TEST_TARGETS = ((UNIT_TESTS, "App/Tests"), (UI_TESTS, "App/UITests"))


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


def plan_target(target: dict, skipped: list[str]) -> dict:
    return {"skippedTests": sorted(skipped), "target": target} if skipped else {"target": target}


def plans(pbxproj: str) -> dict[Path, dict]:
    """Every test plan, by the path it is written to, from the text of the generated project file."""
    entries = [({"containerPath": f"container:{path}", "identifier": name, "name": name},
                ROOT / path / "Tests" / name) for path, name in package_test_targets()]
    for name, folder in APP_TEST_TARGETS:
        entries.append(({"containerPath": "container:PDFAlgoPro.xcodeproj",
                         "identifier": target_id(pbxproj, name), "name": name}, ROOT / folder))
    variables = {"containerPath": "container:PDFAlgoPro.xcodeproj",
                 "identifier": target_id(pbxproj, APP), "name": APP}

    targets, performance, screenshots, device = [], [], [], []
    for target, folder in entries:
        classes = performance_classes(folder)
        shots = performance_classes(folder, STORE_SCREENSHOT_CLASS)
        device_only = performance_classes(folder, DEVICE_CLASS)
        targets.append(plan_target(target, classes + shots + device_only))
        if classes:
            performance.append({"selectedTests": classes, "target": target})
        if shots:
            screenshots.append({"selectedTests": shots, "target": target})
        if target["name"] == UNIT_TESTS:
            device.append(plan_target(target, classes + shots + list(DEVICE_SKIPPED_UNIT_SUITES)))
        elif target["name"] == UI_TESTS:
            device.append(plan_target(target, classes + shots))
    return {
        PLAN: {
            "configurations": [{"id": "4F1C2A00-0000-4000-8000-000000000001", "name": "Default", "options": {}}],
            # A test that hangs fails by name after the allowance, instead of holding the job until its
            # 60-minute timeout cancels it with no verdict. XCTest rounds the allowance up to whole
            # minutes. The slowest UI test took 69 s on CI (run 414); Swift Testing suites keep their own
            # .timeLimit traits.
            "defaultOptions": {"codeCoverage": True, "defaultTestExecutionTimeAllowance": TEST_ALLOWANCE,
                               "targetForVariableExpansion": variables, "testTimeoutsEnabled": True},
            "testTargets": targets,
            "version": 1,
        },
        PERFORMANCE_PLAN: {
            "configurations": [{"id": "4F1C2A00-0000-4000-8000-000000000002", "name": "Default", "options": {}}],
            "defaultOptions": {"codeCoverage": False, "targetForVariableExpansion": variables},
            "testTargets": performance,
            "version": 1,
        },
        STORE_SCREENSHOTS_PLAN: {
            "configurations": [{"id": "4F1C2A00-0000-4000-8000-000000000003", "name": "Default", "options": {}}],
            # The device's model can take a while to answer a screenshot's question.
            "defaultOptions": {"codeCoverage": False, "defaultTestExecutionTimeAllowance": TEST_ALLOWANCE,
                               "targetForVariableExpansion": variables, "testTimeoutsEnabled": True},
            "testTargets": screenshots,
            "version": 1,
        },
        DEVICE_PLAN: {
            "configurations": [{"id": "4F1C2A00-0000-4000-8000-000000000004", "name": "Default", "options": {}}],
            # Set in the test runner: UI_DEVICE=1 tells a test it runs on a device, and UI_EVIDENCE=all
            # keeps the screen of quarantined audit findings too (UITestCase.keepEvidence). No REPORTS_DIR:
            # the runner on the phone cannot write to the Mac, so the evidence goes into the result bundle
            # as attachments, which scripts/dev/device_tests.sh exports.
            "defaultOptions": {"codeCoverage": False, "defaultTestExecutionTimeAllowance": TEST_ALLOWANCE,
                               "environmentVariableEntries": [{"key": "UI_DEVICE", "value": "1"},
                                                              {"key": "UI_EVIDENCE", "value": "all"}],
                               "targetForVariableExpansion": variables, "testTimeoutsEnabled": True},
            "testTargets": device,
            "version": 1,
        },
    }


def main() -> int:
    written = plans(PROJECT.read_text(encoding="utf-8"))
    for path, plan in written.items():
        write(path, plan)
    performance = written[PERFORMANCE_PLAN]["testTargets"]
    screenshots = written[STORE_SCREENSHOTS_PLAN]["testTargets"]
    print(f"wrote {PLAN.name} with {len(written[PLAN]['testTargets'])} test targets, {PERFORMANCE_PLAN.name} "
          f"with {sum(len(t['selectedTests']) for t in performance)} performance classes, "
          f"{STORE_SCREENSHOTS_PLAN.name} with {sum(len(t['selectedTests']) for t in screenshots)} class(es) "
          f"and {DEVICE_PLAN.name} with {len(written[DEVICE_PLAN]['testTargets'])} test targets")
    return 0


if __name__ == "__main__":
    sys.exit(main())
