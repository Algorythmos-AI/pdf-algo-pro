#!/usr/bin/env python3
"""Write PDFAlgoPro.xctestplan from the generated Xcode project. Standard library only.

    xcodegen generate && python3 scripts/ci/write_testplan.py

XcodeGen does not generate test plans, and a plan refers to project targets by their generated IDs,
so the plan is derived from the project each time it is generated (locally and in CI). It lists every
local package's test target (found from each Package.swift), the app's unit tests and the UI tests, with code coverage
on. Run it again whenever a package or test target is added, removed or renamed.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PROJECT = ROOT / "PDFAlgoPro.xcodeproj" / "project.pbxproj"
PLAN = ROOT / "PDFAlgoPro.xctestplan"
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


def main() -> int:
    pbxproj = PROJECT.read_text(encoding="utf-8")
    targets = [{"target": {"containerPath": f"container:{path}", "identifier": name, "name": name}}
               for path, name in package_test_targets()]
    for name in (UNIT_TESTS, UI_TESTS):
        targets.append({"target": {"containerPath": "container:PDFAlgoPro.xcodeproj",
                                   "identifier": target_id(pbxproj, name), "name": name}})
    plan = {
        "configurations": [{"id": "4F1C2A00-0000-4000-8000-000000000001", "name": "Default", "options": {}}],
        "defaultOptions": {
            "codeCoverage": True,
            "targetForVariableExpansion": {"containerPath": "container:PDFAlgoPro.xcodeproj",
                                           "identifier": target_id(pbxproj, APP), "name": APP},
        },
        "testTargets": targets,
        "version": 1,
    }
    PLAN.write_text(json.dumps(plan, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {PLAN.name} with {len(targets)} test targets")
    return 0


if __name__ == "__main__":
    sys.exit(main())
