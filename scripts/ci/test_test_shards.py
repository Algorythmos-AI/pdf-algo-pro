"""Tests for test_shards.py and test_shards.json against the UI test sources.

    uv run --with pytest==8.4.2 pytest -q scripts/ci
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_shards  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
UI_SOURCES = ROOT / "App" / "UITests"
CLASS = re.compile(r"^\s*(?:final\s+)?class\s+(\w+)\s*:\s*(\w+)", re.M)


def ui_classes() -> dict[str, str]:
    """Each class declared in the UI test sources, with its superclass."""
    found: dict[str, str] = {}
    for source in sorted(UI_SOURCES.glob("*.swift")):
        found.update(CLASS.findall(source.read_text(encoding="utf-8")))
    return found


def test_the_ui_target_is_the_one_the_test_plan_writer_uses():
    import write_testplan

    assert test_shards.load_config()["uiTarget"] == write_testplan.UI_TESTS


def test_every_listed_class_exists_and_is_a_ui_test_case():
    classes = ui_classes()
    config = test_shards.load_config()
    for name in [n for shard in test_shards.LISTED for n in config[shard]]:
        assert name in classes, f"{name} in test_shards.json is not a class in App/UITests"
        assert classes[name] == "UITestCase", f"{name} is not a UITestCase"
        assert not name.endswith("PerformanceTests"), "performance classes run in the Performance plan"


def test_ui_3_keeps_at_least_one_class_of_its_own():
    runnable = {n for n, base in ui_classes().items() if base == "UITestCase"}
    config = test_shards.load_config()
    assert runnable - {n for shard in test_shards.LISTED for n in config[shard]}, "ui-3 would run nothing"


def test_a_duplicate_or_malformed_class_is_refused(tmp_path):
    path = tmp_path / "shards.json"
    def write(ui1: list[str], ui2: list[str]) -> None:
        path.write_text(json.dumps({"uiTarget": "PDFAlgoProUITests", "ui-1": ui1, "ui-2": ui2}))

    write(["ReaderUITests", "ReaderUITests"], ["PaywallUITests"])
    with pytest.raises(SystemExit, match="twice"):
        test_shards.load_config(path)
    write(["ReaderUITests"], ["ReaderUITests"])  # in two shards
    with pytest.raises(SystemExit, match="twice"):
        test_shards.load_config(path)
    write(["Reader UITests"], ["PaywallUITests"])
    with pytest.raises(SystemExit, match="not a class name"):
        test_shards.load_config(path)
    write(["ReaderUITests"], [])
    with pytest.raises(SystemExit, match="non-empty ui-2"):
        test_shards.load_config(path)


CONFIG = {"uiTarget": "UI", "ui-1": ["A", "B"], "ui-2": ["C"]}


def test_unit_skips_only_the_ui_target():
    assert test_shards.args_for("unit", config=CONFIG) == ["-skip-testing:UI"]


def test_ui_1_runs_its_classes_without_xcodebuilds_own_retry():
    # -retry-tests-on-failure ran all of ui-2 again for 3 failures on run 37924545633.
    assert test_shards.args_for("ui-1", config=CONFIG) == ["-only-testing:UI/A", "-only-testing:UI/B"]


def test_ui_2_runs_its_classes_and_ui_3_is_the_complement_of_both():
    assert test_shards.args_for("ui-2", config=CONFIG) == ["-only-testing:UI/C"]
    args = test_shards.args_for("ui-3", config=CONFIG)
    assert args[0] == "-only-testing:UI"
    assert [a for a in args if a.startswith("-skip-testing:")] == [
        "-skip-testing:UI/A", "-skip-testing:UI/B", "-skip-testing:UI/C"]
    assert "-retry-tests-on-failure" not in args
    assert test_shards.retries("ui-3") and not test_shards.retries("unit")


def test_the_real_ui_shards_cover_every_ui_class_once():
    config = test_shards.load_config()
    target = config["uiTarget"]
    runnable = {n for n, base in ui_classes().items() if base == "UITestCase"}
    listed = [a.split("/", 1)[1] for shard in test_shards.LISTED for a in test_shards.args_for(shard)
              if a.startswith("-only-testing:")]
    skipped_in_ui3 = {a.split("/", 1)[1] for a in test_shards.args_for("ui-3") if a.startswith("-skip-testing:")}
    assert len(listed) == len(set(listed)), "a class is in two listed shards"
    assert set(listed) == skipped_in_ui3
    assert f"-only-testing:{target}" in test_shards.args_for("ui-3")
    assert set(listed) <= runnable


def test_focused_runs_exactly_what_was_asked_without_retries():
    assert test_shards.args_for("focused", "PDFAlgoProUITests/ReaderUITests, CoreTests/DocTests/testOpen()",
                                config=CONFIG) == [
        "-only-testing:PDFAlgoProUITests/ReaderUITests", "-only-testing:CoreTests/DocTests/testOpen()"]


@pytest.mark.parametrize("value", [
    "Target/Class; rm -rf /", "Target/Class -destination id=x", "$(id)", "`id`", "Target/../x",
    "A/B/C/D", "Target/Class/", "/Class", "Target//x", ",", "Target,,Other", "Target/Class()()",
    "Target/Class\nother", "Tárget", "Target/Class/test(x:)",
])
def test_focused_rejects_anything_but_plain_identifiers(value):
    with pytest.raises(ValueError):
        test_shards.focused_ids(value)


def test_focused_rejects_too_many_identifiers():
    with pytest.raises(ValueError, match="at most"):
        test_shards.focused_ids(",".join(f"T{i}" for i in range(test_shards.MAX_FOCUSED + 1)))


def test_matrix_is_three_shards_or_one_focused():
    assert test_shards.matrix("") == {"shard": ["unit", "ui-1", "ui-2", "ui-3"]}
    assert test_shards.matrix(None) == {"shard": ["unit", "ui-1", "ui-2", "ui-3"]}
    assert test_shards.matrix("   ") == {"shard": ["unit", "ui-1", "ui-2", "ui-3"]}
    assert test_shards.matrix("CoreTests") == {"shard": ["focused"]}
    with pytest.raises(ValueError):
        test_shards.matrix("CoreTests; echo")


def test_a_recording_run_is_the_unit_shard_alone():
    assert test_shards.matrix("", record=True) == {"shard": ["unit"]}
    with pytest.raises(ValueError):
        test_shards.matrix("CoreTests", record=True)
    assert test_shards.main(["matrix", "--record", "true"]) == 0
    assert test_shards.main(["matrix", "--record", "false"]) == 0


def test_cli_prints_matrix_args_and_refuses_bad_input(capsys):
    assert test_shards.main(["matrix"]) == 0
    assert json.loads(capsys.readouterr().out) == {"shard": ["unit", "ui-1", "ui-2", "ui-3"]}
    assert test_shards.main(["names"]) == 0
    assert capsys.readouterr().out.strip() == "unit,ui-1,ui-2,ui-3"
    assert test_shards.main(["args", "unit"]) == 0
    assert capsys.readouterr().out.splitlines() == ["-skip-testing:PDFAlgoProUITests"]
    assert test_shards.main(["matrix", "--only-testing", "x y"]) == 1
    assert "::error::" in capsys.readouterr().out
    assert test_shards.main(["args", "nightly"]) == 1


@pytest.mark.parametrize("shard,xcodebuild,reporter,passes", [
    ("unit", 0, 0, True),
    ("unit", 0, None, True),
    ("unit", 65, 0, False),          # no retries: xcodebuild's verdict stands
    ("unit", 65, 1, False),
    ("unit", 65, None, False),       # crashed before writing results
    ("ui-1", 65, 0, True),           # failed, then passed on retry
    ("ui-1", 65, 1, False),          # last repetition failed
    ("ui-2", 65, None, False),
    ("ui-2", 0, 1, True),            # xcodebuild passed; the flake budget is ios-report's
    ("focused", 65, 0, False),
])
def test_verdict(shard, xcodebuild, reporter, passes):
    assert test_shards.verdict(shard, xcodebuild, reporter)[0] is passes


def test_a_ui_shard_runs_only_its_failed_tests_again(tmp_path, capsys):
    failed = ["PDFAlgoProUITests/PaywallUITests/testOffer\n", "PDFAlgoProUITests/PaywallUITests/testJourney\n"]
    assert test_shards.retry_args("ui-2", failed)[0] == [
        "-only-testing:PDFAlgoProUITests/PaywallUITests/testOffer",
        "-only-testing:PDFAlgoProUITests/PaywallUITests/testJourney"]
    path = tmp_path / "retry.txt"
    path.write_text("".join(failed))
    assert test_shards.main(["retry-args", "ui-1", str(path)]) == 0
    assert capsys.readouterr().out.splitlines() == [
        "-only-testing:PDFAlgoProUITests/PaywallUITests/testOffer",
        "-only-testing:PDFAlgoProUITests/PaywallUITests/testJourney"]


@pytest.mark.parametrize("shard,failed,why", [
    ("unit", ["CoreTests/DocTests/testOpen"], "does not retry"),
    ("focused", ["UI/A/testX"], "does not retry"),
    ("ui-1", [], "no test failed"),
    ("ui-1", [f"UI/A/test{n}" for n in range(4)], "more than the 3"),
    ("ui-2", ["UI/A/testX; rm -rf /"], "is not Target/Class/method"),
    ("ui-2", ["UI/A"], "is not Target/Class/method"),
])
def test_no_retry_when_it_cannot_help(shard, failed, why):
    selectors, reason = test_shards.retry_args(shard, failed)
    assert selectors == [] and why in reason


def test_a_missing_list_of_failed_tests_runs_nothing_again(tmp_path, capsys):
    assert test_shards.main(["retry-args", "ui-2", str(tmp_path / "absent.txt")]) == 0
    assert capsys.readouterr().out == ""


def test_verdict_cli_reads_an_empty_reporter_exit_as_no_results(capsys):
    assert test_shards.main(["verdict", "ui-1", "--xcodebuild-exit", "65", "--reporter-exit", ""]) == 1
    assert "no test results" in capsys.readouterr().out
    assert test_shards.main(["verdict", "ui-1", "--xcodebuild-exit", "65", "--reporter-exit", "0"]) == 0
