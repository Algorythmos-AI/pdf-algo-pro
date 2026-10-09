"""Tests for xcresult_report.py with synthetic `xcresulttool get test-results tests` output.

    uv run --with pytest==8.4.2 pytest -q scripts/ci
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import xcresult_report  # noqa: E402


def case(name: str, result: str, *children: dict, suite: str = "PaywallUITests", seconds: float = 2.0) -> dict:
    return {"nodeType": "Test Case", "name": name, "nodeIdentifier": f"{suite}/{name}", "result": result,
            "durationInSeconds": seconds, "children": list(children)}


def message(text: str) -> dict:
    return {"nodeType": "Failure Message", "name": text, "result": "Failed"}


def repetition(number: int, result: str, *children: dict) -> dict:
    return {"nodeType": "Repetition", "name": f"Repetition {number}", "result": result, "children": list(children)}


def results(tmp_path: Path, *cases: dict, bundle: str = "PDFAlgoProUITests", suite: str = "PaywallUITests",
            name: str = "tests.json") -> str:
    tree = {"testNodes": [{"nodeType": "Test Plan", "name": "PDFAlgoPro", "result": "Failed", "children": [
        {"nodeType": "UI test bundle", "name": bundle, "result": "Failed", "children": [
            {"nodeType": "Test Suite", "name": suite, "result": "Failed", "children": list(cases)}]}]}]}
    path = tmp_path / name
    path.write_text(json.dumps(tree))
    return str(path)


def test_a_failure_is_named_with_its_messages(tmp_path, capsys):
    path = results(tmp_path, case("testOffer()", "Failed", message("Contrast: 'Restore' at 3.9:1\nsecond line")),
                   case("testHome()", "Passed"))
    ids = tmp_path / "failed.txt"
    assert xcresult_report.main([path, "--failed-ids", str(ids)]) == 1
    out = capsys.readouterr().out
    assert "::error title=PDFAlgoProUITests/PaywallUITests/testOffer()::Contrast: 'Restore' at 3.9:1%0Asecond line" in out
    assert "1 passed, 1 failed" in out
    assert ids.read_text() == "PaywallUITests/testOffer()\n"


def test_a_failure_without_a_message_still_says_so(tmp_path, capsys):
    assert xcresult_report.main([results(tmp_path, case("testOffer()", "Failed"))]) == 1
    assert "::no message recorded" in capsys.readouterr().out


def test_a_retried_test_that_passed_is_flaky_not_failed(tmp_path, capsys):
    flaky = case("testOffer()", "Passed", repetition(1, "Failed", message("Audit found 1 issue")),
                 repetition(2, "Passed"))
    ids = tmp_path / "failed.txt"
    assert xcresult_report.main([results(tmp_path, flaky), "--failed-ids", str(ids)]) == 0
    out = capsys.readouterr().out
    assert "::warning title=Flaky%3A PDFAlgoProUITests/PaywallUITests/testOffer()::" in out
    assert "Audit found 1 issue" in out and "::error" not in out
    assert ids.read_text() == ""


def test_the_last_repetition_decides_whatever_the_case_says(tmp_path, capsys):
    # Repetitions can arrive out of order, and the case's own result may summarise them differently.
    failing = case("testOffer()", "Passed", repetition(2, "Failed", message("second try")),
                   repetition(1, "Failed", message("first try")))
    assert xcresult_report.main([results(tmp_path, failing)]) == 1
    out = capsys.readouterr().out
    assert "::second try" in out and "first try" not in out


def test_the_flaky_budget_fails_the_run_when_exceeded(tmp_path, capsys):
    flaky = [case(f"test{i}()", "Passed", repetition(1, "Failed", message("x")), repetition(2, "Passed"))
             for i in range(4)]
    path = results(tmp_path, *flaky)
    assert xcresult_report.main([path, "--flaky-budget", "4"]) == 0
    assert xcresult_report.main([path, "--flaky-budget", "3"]) == 1
    assert "4 tests were flaky in this run, more than the budget of 3" in capsys.readouterr().out


def test_expected_failures_and_skips_do_not_fail(tmp_path, capsys):
    path = results(tmp_path, case("testKnown()", "Expected Failure", message("#53 contrast on sheets")),
                   case("testDevice()", "Skipped"), case("testFine()", "Passed"))
    summary = tmp_path / "summary.md"
    assert xcresult_report.main([path, "--summary", str(summary)]) == 0
    text = summary.read_text()
    assert "#### Quarantined (expected failures)" in text and "#53 contrast on sheets" in text
    assert "1 quarantined · 1 skipped · 1 passed" in text


def test_shards_are_read_together(tmp_path, capsys):
    one = results(tmp_path, case("testA()", "Passed", seconds=30), name="one.json")
    two = results(tmp_path, case("testB()", "Failed", message("boom"), suite="ReaderUITests", seconds=50),
                  suite="ReaderUITests", name="two.json")
    summary = tmp_path / "summary.md"
    assert xcresult_report.main([one, two, "--summary", str(summary)]) == 1
    text = summary.read_text()
    assert "| `PDFAlgoProUITests/ReaderUITests/testB()` | boom |" in text
    assert text.index("PDFAlgoProUITests/ReaderUITests` | 1 | 50") < text.index("PDFAlgoProUITests/PaywallUITests` | 1 | 30")
    assert xcresult_report.test_identifiers(two) == ["ReaderUITests/testB()"]


def test_swift_testing_arguments_carry_their_messages(tmp_path, capsys):
    parameterised = case("catalogueIsWellFormed(name:)", "Failed",
                         {"nodeType": "Arguments", "name": "\"open\"", "result": "Failed",
                          "children": [message("Expectation failed: name.isEmpty == false")]},
                         suite="TelemetryTests")
    assert xcresult_report.main([results(tmp_path, parameterised, bundle="TelemetryTests",
                                         suite="TelemetryTests")]) == 1
    assert "Expectation failed: name.isEmpty == false" in capsys.readouterr().out


def test_no_results_or_unreadable_results_fail(tmp_path, capsys):
    empty = tmp_path / "empty.json"
    empty.write_text(json.dumps({"testNodes": []}))
    assert xcresult_report.main([str(empty)]) == 1
    broken = tmp_path / "broken.json"
    broken.write_text("{not json")
    assert xcresult_report.main([str(broken)]) == 1
    out = capsys.readouterr().out
    assert "No test results to report" in out and "Cannot read test results" in out


def test_durations_read_either_field():
    assert xcresult_report.seconds_of({"durationInSeconds": 1.5}) == 1.5
    assert xcresult_report.seconds_of({"duration": "12s"}) == 12.0
    assert xcresult_report.seconds_of({"duration": "1m 2s"}) == 0.0


def test_a_failed_test_run_again_on_its_own_is_judged_by_that_run(tmp_path, capsys):
    # A UI shard re-runs only its failed tests, in a second result bundle (run 37924545633: xcodebuild's
    # own retry ran all 41 tests of ui-2 again for 3 failures, and the shard ran out of time).
    first = results(tmp_path, case("testOffer()", "Failed", message("Contrast failed: explanation")),
                    case("testJourney()", "Failed", message("1 accessibility finding(s)")),
                    case("testHome()", "Passed"), name="tests.json")
    retry_ids = tmp_path / "retry.txt"
    assert xcresult_report.main([first, "--retry-ids", str(retry_ids)]) == 1
    assert retry_ids.read_text() == ("PDFAlgoProUITests/PaywallUITests/testOffer\n"
                                     "PDFAlgoProUITests/PaywallUITests/testJourney\n")
    capsys.readouterr()
    again = results(tmp_path, case("testOffer()", "Passed"),
                    case("testJourney()", "Failed", message("1 accessibility finding(s) again")), name="retry.json")
    ids = tmp_path / "failed.txt"
    assert xcresult_report.main([first, "--retries", again, "--failed-ids", str(ids), "--flaky-budget", "3"]) == 1
    out = capsys.readouterr().out
    assert ("::warning title=Flaky%3A PDFAlgoProUITests/PaywallUITests/testOffer()::Failed, then passed on retry: "
            "Contrast failed: explanation") in out
    assert "::error title=PDFAlgoProUITests/PaywallUITests/testJourney()::1 accessibility finding(s) again" in out
    assert "1 passed, 1 failed, 1 flaky" in out, "the retry's passing run is not counted as another test"
    assert ids.read_text() == "PaywallUITests/testJourney()\n"
    # Every failure retried and passed: the shard passes, with the flakes named.
    healed = results(tmp_path, case("testOffer()", "Passed"), case("testJourney()", "Passed"), name="healed.json")
    assert xcresult_report.main([first, "--retries", healed]) == 0


def test_a_failed_tests_quarantine_notes_are_not_named_as_its_failure(tmp_path, capsys):
    # As on run 37930118069: a paywall audit failed on the explanation, and the same test also recorded
    # the Close button's finding as an expected failure, which was annotated as a second error.
    quarantine = {"nodeType": "Failure Message", "name": "Quarantined flaky audit finding, issue #76",
                  "result": "Expected Failure"}
    unmarked = message("Measured while the screen was moving, gone on a second audit (issues #105, #182)")
    failed = case("testOffer()", "Failed", message("1 accessibility finding(s): explanation"), quarantine, unmarked)
    assert xcresult_report.main([results(tmp_path, failed)]) == 1
    out = capsys.readouterr().out
    assert "::error title=PDFAlgoProUITests/PaywallUITests/testOffer()::1 accessibility finding(s): explanation" in out
    assert "Quarantined flaky audit finding" not in out and "Measured while the screen" not in out
    # A quarantined test still lists its reason.
    known = case("testKnown()", "Expected Failure", message("Quarantined flaky audit finding, issue #76"))
    summary = tmp_path / "summary.md"
    assert xcresult_report.main([results(tmp_path, known, name="known.json"), "--summary", str(summary)]) == 0
    assert "Quarantined flaky audit finding, issue #76" in summary.read_text()


def test_the_flaky_tests_are_written_for_the_issue_job(tmp_path):
    flaky = case("testOffer()", "Passed", repetition(1, "Failed", message("Audit found 1 issue")),
                 repetition(2, "Passed"))
    out = tmp_path / "flaky.json"
    assert xcresult_report.main([results(tmp_path, flaky, case("testHome()", "Passed")),
                                 "--flaky-out", str(out)]) == 0
    assert json.loads(out.read_text()) == [
        {"test": "PDFAlgoProUITests/PaywallUITests/testOffer()", "message": "Audit found 1 issue"}]
