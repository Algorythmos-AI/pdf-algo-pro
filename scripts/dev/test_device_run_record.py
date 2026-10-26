"""Tests for device_run_record.py with synthetic devicectl and xcresulttool output.

    uv run --with pytest==8.4.2 pytest -q scripts/dev
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import device_run_record  # noqa: E402

DOC = device_run_record.DOC
HEADER = "| " + " | ".join(device_run_record.COLUMNS) + " |"
UDID = "00000000-0000000000000000"
IDENTIFIER = "11111111-2222-3333-4444-555555555555"


def phone(state: str = "connected", transport: str | None = "wired", pairing: str = "paired",
          developer_mode: dict | None = None, platform: str = "iOS") -> dict:
    connection = {"pairingState": pairing, "state": state}
    if transport:
        connection["transportType"] = transport
    return {
        "identifier": IDENTIFIER,
        "properties": {
            "connection": connection,
            "hardware": {"marketingName": "iPhone 17 Pro", "platform": platform, "reality": "physical",
                         "udid": UDID},
            "software": {"osVersionNumber": {"stringValue": "27.0.1"}},
            "state": {"name": "Test Phone", "developerModeStatus": developer_mode or {"enabled": {"mode": 1}}},
        },
    }


def listing(*devices: dict) -> dict:
    return {"info": {"outcome": "success"}, "result": {"devices": list(devices)}}


@pytest.mark.parametrize("wanted", [UDID, IDENTIFIER, "Test Phone"])
def test_a_connected_phone_is_found_by_udid_identifier_or_name(wanted):
    device, problems, warnings = device_run_record.check_device(listing(phone()), wanted)
    assert (problems, warnings) == ([], [])
    assert (device["udid"], device["model"], device["ios"]) == (UDID, "iPhone 17 Pro", "27.0.1")


def test_a_phone_over_wi_fi_is_a_warning_not_a_failure():
    _, problems, warnings = device_run_record.check_device(listing(phone("disconnected", "localNetwork")), UDID)
    assert problems == []
    assert "available (paired)" in warnings[0]
    _, problems, warnings = device_run_record.check_device(listing(phone("connected", "localNetwork")), UDID)
    assert problems == [] and "Wi-Fi" in warnings[0]


@pytest.mark.parametrize("device,fix", [
    (phone("unavailable"), "connect the cable"),
    (phone(pairing="unpaired"), "Trust This Computer"),
    (phone(developer_mode={"disabled": {}}), "Developer Mode"),
    (phone(platform="watchOS"), "not an iPhone"),
])
def test_a_phone_that_cannot_run_says_how_to_fix_it(device, fix):
    _, problems, _ = device_run_record.check_device(listing(device), UDID)
    assert any(fix in p for p in problems)


def test_an_unknown_device_names_the_phones_there_are_without_their_ids():
    device, problems, _ = device_run_record.check_device(listing(phone("disconnected")), "nope")
    assert device is None
    assert "iPhone 17 Pro (available (paired))" in problems[0]
    assert UDID not in problems[0] and IDENTIFIER not in problems[0] and "Test Phone" not in problems[0]


def test_the_deprecated_fields_are_read_when_properties_are_missing():
    old = {"identifier": IDENTIFIER,
           "connectionProperties": {"pairingState": "paired", "tunnelState": "connected", "transportType": "wired"},
           "deviceProperties": {"name": "Old", "osVersionNumber": "26.5", "developerModeStatus": "enabled"},
           "hardwareProperties": {"marketingName": "iPhone 15", "platform": "iOS", "reality": "physical", "udid": UDID}}
    device, problems, warnings = device_run_record.check_device(listing(old), UDID)
    assert (problems, warnings) == ([], [])
    assert (device["model"], device["ios"]) == ("iPhone 15", "26.5")


def test_the_device_command_prints_the_facts_for_the_shell_and_fails_on_a_problem(tmp_path, capsys):
    path = tmp_path / "devices.json"
    path.write_text(json.dumps(listing(phone())))
    assert device_run_record.main(["device", str(path), "--id", IDENTIFIER]) == 0
    assert capsys.readouterr().out.splitlines() == [f"udid={UDID}", "model=iPhone 17 Pro", "ios=27.0.1"]
    path.write_text(json.dumps(listing(phone(developer_mode={"disabled": {}}))))
    assert device_run_record.main(["device", str(path), "--id", IDENTIFIER]) == 1
    captured = capsys.readouterr()
    assert captured.out == "" and "Developer Mode" in captured.err
    assert device_run_record.main(["device", str(tmp_path / "absent.json"), "--id", IDENTIFIER]) == 1


# --- record ---------------------------------------------------------------------------------------

def case(name: str, result: str) -> dict:
    return {"nodeType": "Test Case", "name": name, "nodeIdentifier": f"ReaderUITests/{name}", "result": result,
            "durationInSeconds": 1.0, "children": []}


def results(path: Path, *cases: dict) -> Path:
    path.write_text(json.dumps({"testNodes": [{"nodeType": "Test Plan", "name": "Device", "children": [
        {"nodeType": "UI test bundle", "name": "PDFAlgoProUITests", "children": [
            {"nodeType": "Test Suite", "name": "ReaderUITests", "children": list(cases)}]}]}]}))
    return path


def doc(tmp_path: Path, rows: str = "") -> Path:
    path = tmp_path / "device-test-run.md"
    path.write_text("# Device test run\n\n## Manual checklist\n\n1. **Face ID.** Unlock.\n2. **Print.** Print.\n\n"
                    f"## Runs\n\nA row per run.\n\n{HEADER}\n|{'---|' * len(device_run_record.COLUMNS)}\n{rows}"
                    "\nAfter the table.\n")
    return path


def record(tmp_path: Path, path: Path, *extra: str) -> int:
    return device_run_record.main(["record", "--doc", str(path), "--date", "2026-10-26", "--commit", "abc1234",
                                   "--xcode", "27.0 (27A266a)", "--device", "iPhone 17 Pro", "--ios", "27.0.1",
                                   "--flags", "Device --purchases", "--bundle", str(tmp_path / "Device.xcresult"),
                                   "--ci-ios", "success", *extra])


def test_a_run_is_added_as_the_last_row_with_failed_tests_that_passed_again_as_flaky(tmp_path):
    first = results(tmp_path / "tests.json", case("testA()", "Passed"), case("testB()", "Failed"),
                    case("testC()", "Failed"))
    again = results(tmp_path / "retry.json", case("testB()", "Passed"), case("testC()", "Failed"))
    path = doc(tmp_path, rows="| 2026-10-01 | 1234567 | x | x | x | x | x | x | x | x | x |\n")
    assert record(tmp_path, path, "--tests", str(first), "--retries", str(again)) == 0
    lines = path.read_text().splitlines()
    row = lines[lines.index("| 2026-10-01 | 1234567 | x | x | x | x | x | x | x | x | x |") + 1]
    assert row == ("| 2026-10-26 | abc1234 | 27.0 (27A266a) | iPhone 17 Pro | 27.0.1 | Device --purchases | "
                   f"1 / 1 / 1 | `{device_run_record.public_path(str(tmp_path / 'Device.xcresult'))}` | success | "
                   "pending | none yet |")
    assert lines[lines.index(row) + 1] == ""


def test_a_run_without_results_is_still_recorded(tmp_path):
    path = doc(tmp_path)
    assert record(tmp_path, path, "--tests", str(tmp_path / "absent.json")) == 0
    assert "| no results |" in path.read_text()


def test_a_result_bundle_in_the_home_folder_is_written_without_it():
    shown = device_run_record.public_path(str(Path.home() / "Results" / "Device.xcresult"))
    if not (Path.home() / "Results").resolve().is_relative_to(device_run_record.ROOT):
        assert shown == "~/Results/Device.xcresult"
    inside = device_run_record.public_path(str(device_run_record.ROOT / ".build" / "device-tests" / "x.xcresult"))
    assert inside == ".build/device-tests/x.xcresult"


def test_a_cell_never_breaks_the_table(tmp_path):
    path = doc(tmp_path)
    assert record(tmp_path, path, "--issues", "#1 | #2\nand more") == 0
    assert "#1 \\| #2 and more" in path.read_text()


@pytest.mark.parametrize("commit", ["abc1234; rm -rf /", "HEAD", "ABC1234"])
def test_the_commit_must_be_a_hash(tmp_path, commit):
    path = doc(tmp_path)
    with pytest.raises(SystemExit):
        device_run_record.main(["record", "--doc", str(path), "--commit", commit, "--xcode", "x", "--device", "x",
                                "--ios", "x", "--flags", "x", "--bundle", "x"])


def test_a_document_without_the_table_is_refused(tmp_path):
    path = tmp_path / "other.md"
    path.write_text("# Other\n\n## Runs\n\nNo table.\n")
    with pytest.raises(SystemExit, match="columns"):
        record(tmp_path, path)


def test_the_checklist_is_printed_from_the_document(tmp_path, capsys):
    assert device_run_record.main(["checklist", "--doc", str(doc(tmp_path))]) == 0
    out = capsys.readouterr().out
    assert out.startswith("## Manual checklist") and "2. **Print.** Print." in out and "## Runs" not in out


def test_the_real_document_has_the_table_and_the_checklist():
    text = DOC.read_text(encoding="utf-8")
    assert HEADER in text.splitlines()
    assert "1. **Face ID.**" in device_run_record.checklist(DOC)


# --- commit ---------------------------------------------------------------------------------------

@pytest.mark.parametrize("status,label", [
    ([], "abc1234"),
    (["?? notes.txt\n", "?? .scratch/\n", "?? docs/draft.md\n"], "abc1234"),
    ([" M docs/process/device-test-run.md\n"], "abc1234-dirty"),
    (["M  App/PDFAlgoPro/AppModel.swift\n"], "abc1234-dirty"),
    (["?? App/Tests/NewTests.swift\n"], "abc1234-dirty"),
    (["?? App/UITests/Helpers/\n"], "abc1234-dirty"),
    (["?? Packages/Core/Sources/Core/New.swift\n"], "abc1234-dirty"),
    (['?? "App/Tests/With space.swift"\n'], "abc1234-dirty"),
    (["?? Config/Other.xcconfig\n"], "abc1234-dirty"),
    (["?? Extra.xctestplan\n"], "abc1234-dirty"),
])
def test_the_commit_is_dirty_when_what_is_built_differs_from_it(status, label):
    assert device_run_record.commit_label("abc1234", status) == label


def test_the_commit_command_reads_the_status_from_stdin(monkeypatch, capsys):
    import io

    monkeypatch.setattr(sys, "stdin", io.StringIO("?? App/UITests/ScanDeviceUITests.swift\n"))
    assert device_run_record.main(["commit", "abc1234"]) == 0
    assert capsys.readouterr().out.strip() == "abc1234-dirty"
    with pytest.raises(SystemExit):
        device_run_record.main(["commit", "HEAD; id"])


def test_a_dirty_commit_is_recorded_as_such(tmp_path):
    path = doc(tmp_path)
    assert device_run_record.main(["record", "--doc", str(path), "--commit", "abc1234-dirty", "--xcode", "x",
                                   "--device", "x", "--ios", "x", "--flags", "x", "--bundle", "x"]) == 0
    assert "| abc1234-dirty |" in path.read_text()
