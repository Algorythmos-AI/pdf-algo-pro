"""Tests for device_resume.py with synthetic xcodebuild enumeration and xcresulttool output.

    uv run --with pytest==8.4.2 pytest -q scripts/dev
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import device_resume  # noqa: E402

UI = "PDFAlgoProUITests"
UNIT = "PDFAlgoProTests"
PLAN = [f"{UNIT}/AppLockTests/backgroundLocks()", f"{UI}/LibraryUITests/testA()",
        f"{UI}/LibraryUITests/testB()", f"{UI}/ReaderUITests/testC()", f"{UI}/UITestCase"]


def enumeration(tmp_path: Path, plan: list[str] = PLAN) -> Path:
    path = tmp_path / "enumerated.json"
    path.write_text(json.dumps({"errors": [], "values": [
        {"testPlan": "Device", "enabledTests": [{"identifier": i} for i in plan], "disabledTests": []}]}))
    return path


def case(identifier: str, result: str, message: str = "") -> dict:
    node = {"nodeType": "Test Case", "name": identifier.split("/")[-1], "nodeIdentifier": identifier,
            "result": result, "durationInSeconds": 1.0}
    if message:
        node["children"] = [{"nodeType": "Failure Message", "name": message}]
    return node


def results(tmp_path: Path, name: str, ui: list[dict], unit: list[dict] | None = None,
            stopped: bool = False) -> Path:
    bundles = []
    if unit:
        bundles.append({"nodeType": "Unit test bundle", "name": UNIT,
                        "children": [{"nodeType": "Test Suite", "name": "AppLockTests", "children": unit}]})
    suites: dict[str, list[dict]] = {}
    for node in ui:
        suites.setdefault(node["nodeIdentifier"].split("/")[0], []).append(node)
    children = [{"nodeType": "Test Suite", "name": s, "children": c} for s, c in suites.items()]
    if stopped:
        children.append({"nodeType": "Test Suite", "name": "System Failures", "children": [
            case("PDFAlgoProUITests-Runner (17696) encountered an error", "Failed",
                 "An error occurred while communicating with a remote process.")]})
    bundles.append({"nodeType": "UI test bundle", "name": UI, "children": children})
    path = tmp_path / f"{name}.json"
    path.write_text(json.dumps({"testNodes": [{"nodeType": "Test Plan", "name": "Device", "children": bundles}]}))
    return path


def run_next(tmp_path: Path, *files: Path, with_failed: bool = False, capsys=None) -> list[str]:
    args = ["next", str(enumeration(tmp_path)), *map(str, files)] + (["--with-failed"] if with_failed else [])
    assert device_resume.main(args) == 0
    return [line for line in capsys.readouterr().out.splitlines() if line]


def run_report(tmp_path: Path, *files: Path) -> tuple[int, str, str, str]:
    summary, failed, counts = tmp_path / "summary.md", tmp_path / "failed.txt", tmp_path / "counts.txt"
    code = device_resume.main(["report", str(enumeration(tmp_path)), *map(str, files), "--summary", str(summary),
                               "--failed-ids", str(failed), "--counts", str(counts)])
    return code, summary.read_text(), failed.read_text(), counts.read_text().strip()


def test_the_tests_a_stopped_runner_never_reached_run_next_with_the_one_it_was_in(tmp_path, capsys):
    first = results(tmp_path, "first", [case("LibraryUITests/testA()", "Passed"),
                                         case("LibraryUITests/testB()", "Failed", "No matches found")],
                    unit=[case("AppLockTests/backgroundLocks()", "Passed")], stopped=True)
    assert run_next(tmp_path, first, capsys=capsys) == [f"-only-testing:{UI}/ReaderUITests/testC()"]
    assert run_next(tmp_path, first, with_failed=True, capsys=capsys) == [
        f"-only-testing:{UI}/ReaderUITests/testC()", f"-only-testing:{UI}/LibraryUITests/testB()"]


def test_a_unit_test_is_asked_for_as_listed_so_that_swift_testing_finds_it(tmp_path, capsys):
    # On the iPhone run of 2026-10-26, `-only-testing:PDFAlgoProTests/AppLockTests/off` matched nothing,
    # three rounds in a row, and 65 unit tests "never ran"; with "()" xcodebuild finds it.
    first = results(tmp_path, "first", [case("LibraryUITests/testA()", "Passed")], stopped=True)
    assert run_next(tmp_path, first, capsys=capsys) == [
        f"-only-testing:{UNIT}/AppLockTests/backgroundLocks()", f"-only-testing:{UI}/LibraryUITests/testB()",
        f"-only-testing:{UI}/ReaderUITests/testC()"]


def test_a_class_with_no_tests_of_its_own_is_never_asked_for(tmp_path, capsys):
    first = results(tmp_path, "first", [case("LibraryUITests/testA()", "Passed"), case("LibraryUITests/testB()", "Passed"),
                                         case("ReaderUITests/testC()", "Passed")],
                    unit=[case("AppLockTests/backgroundLocks()", "Passed")])
    assert run_next(tmp_path, first, with_failed=True, capsys=capsys) == []


def test_an_ordinary_failure_with_every_test_run_is_not_run_a_third_time(tmp_path, capsys):
    first = results(tmp_path, "first", [case("LibraryUITests/testA()", "Passed"),
                                         case("LibraryUITests/testB()", "Failed", "wrong"),
                                         case("ReaderUITests/testC()", "Passed")],
                    unit=[case("AppLockTests/backgroundLocks()", "Passed")])
    assert run_next(tmp_path, first, with_failed=True, capsys=capsys) == []


def test_once_every_test_ran_the_runner_stop_is_not_a_failure(tmp_path):
    first = results(tmp_path, "first", [case("LibraryUITests/testA()", "Passed"),
                                         case("LibraryUITests/testB()", "Failed", "No matches found")],
                    unit=[case("AppLockTests/backgroundLocks()", "Passed")], stopped=True)
    resumed = results(tmp_path, "resume", [case("LibraryUITests/testB()", "Passed"),
                                           case("ReaderUITests/testC()", "Passed")])
    code, summary, failed, counts = run_report(tmp_path, first, resumed)
    assert code == 0
    assert counts == "3 / 0 / 1"
    assert failed == ""
    assert "stopped 1 time(s)" in summary


def test_a_test_that_never_ran_and_one_that_failed_again_fail_the_run(tmp_path):
    first = results(tmp_path, "first", [case("LibraryUITests/testA()", "Passed"),
                                         case("LibraryUITests/testB()", "Failed", "first")],
                    unit=[case("AppLockTests/backgroundLocks()", "Passed")], stopped=True)
    resumed = results(tmp_path, "resume", [case("LibraryUITests/testB()", "Failed", "second")], stopped=True)
    code, summary, failed, counts = run_report(tmp_path, first, resumed)
    assert code == 1
    assert counts == "2 / 2 / 0"
    assert failed.splitlines() == [f"{UI}/LibraryUITests/testB", f"{UI}/ReaderUITests/testC"]
    assert "never ran" in summary and "first" in summary


def test_a_failed_tests_attachments_are_gathered_from_every_bundle(tmp_path):
    exported = tmp_path / "attachments"
    for bundle, test, name in [("Device", "LibraryUITests/testB()", "first.png"),
                               ("Device-resume-1", "LibraryUITests/testB()", "second.png"),
                               ("Device-resume-1", "ReaderUITests/testC()", "passed.png")]:
        folder = exported / bundle
        folder.mkdir(parents=True, exist_ok=True)
        (folder / name).write_bytes(b"png")
        manifest = folder / "manifest.json"
        entries = json.loads(manifest.read_text()) if manifest.exists() else []
        entries.append({"testIdentifier": test, "attachments": [{"exportedFileName": name}]})
        manifest.write_text(json.dumps(entries))
    failed = tmp_path / "failed.txt"
    failed.write_text(f"{UI}/LibraryUITests/testB\n")
    out = tmp_path / "failed-attachments"
    assert device_resume.main(["attachments", str(failed), str(exported), str(out)]) == 0
    folder = out / f"{UI}_LibraryUITests_testB"
    assert sorted(p.name for p in folder.iterdir()) == ["Device-first.png", "Device-resume-1-second.png"]
    assert [p.name for p in out.iterdir()] == [folder.name]
