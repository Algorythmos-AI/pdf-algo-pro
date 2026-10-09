"""Tests for shard_inventory.py with synthetic enumeration and test-results files.

    uv run --with pytest==8.4.2 pytest -q scripts/ci
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import shard_inventory  # noqa: E402


def case(suite: str, name: str, result: str = "Passed", seconds: float = 1.0) -> dict:
    return {"nodeType": "Test Case", "name": name, "nodeIdentifier": f"{suite}/{name}", "result": result,
            "durationInSeconds": seconds}


def shard(tmp_path: Path, name: str, bundles: dict[str, dict[str, list[dict]]]) -> str:
    """bundles: {bundle: {suite: [cases]}}, written as ios-shard-<name>/tests.json."""
    children = [{"nodeType": "UI test bundle" if b.endswith("UITests") else "Unit test bundle", "name": b,
                 "children": [{"nodeType": "Test Suite", "name": s, "children": cs} for s, cs in suites.items()]}
                for b, suites in bundles.items()]
    folder = tmp_path / f"ios-shard-{name}"
    folder.mkdir(exist_ok=True)
    path = folder / "tests.json"
    path.write_text(json.dumps({"testNodes": [{"nodeType": "Test Plan", "name": "PDFAlgoPro", "children": children}]}))
    return str(path)


def enumeration(tmp_path: Path, enabled: list[str], disabled: list[str] = ()) -> str:
    path = tmp_path / "inventory.json"
    path.write_text(json.dumps({"errors": [], "values": [{
        "testPlan": "PDFAlgoPro",
        "enabledTests": [{"identifier": i} for i in enabled],
        "disabledTests": [{"identifier": i} for i in disabled]}]}))
    return str(path)


def three_shards(tmp_path: Path) -> list[str]:
    return [
        shard(tmp_path, "unit", {"CoreTests": {"DocumentTests": [case("DocumentTests", "testOpen()")]},
                                 "PDFAlgoProTests": {"AppTests": [case("AppTests", "launches()")]}}),
        shard(tmp_path, "ui-1", {"PDFAlgoProUITests": {"ReaderUITests": [case("ReaderUITests", "testRead()")]}}),
        shard(tmp_path, "ui-2", {"PDFAlgoProUITests": {"LibraryUITests": [case("LibraryUITests", "testOpen()", seconds=30)]}}),
    ]


ENABLED = ["CoreTests/DocumentTests/testOpen", "PDFAlgoProTests/AppTests/launches()",
           "PDFAlgoProUITests/ReaderUITests/testRead", "PDFAlgoProUITests/LibraryUITests/testOpen"]
EXPECT = ["unit", "ui-1", "ui-2"]


def test_complete_disjoint_shards_pass(tmp_path, capsys):
    summary = tmp_path / "summary.md"
    code = shard_inventory.main([enumeration(tmp_path, ENABLED), *three_shards(tmp_path),
                                 "--expect", ",".join(EXPECT), "--summary", str(summary)])
    out = capsys.readouterr().out
    assert code == 0, out
    assert "| ui-2 | 1 | 30 | 0 | 0 |" in summary.read_text()
    assert "4 enabled tests; 4 ran" in summary.read_text()


def test_a_test_in_two_shards_fails(tmp_path):
    paths = three_shards(tmp_path)
    paths.append(shard(tmp_path, "extra", {"PDFAlgoProUITests": {"ReaderUITests": [case("ReaderUITests", "testRead()")]}}))
    errors, _, _ = shard_inventory.check(enumeration(tmp_path, ENABLED), paths, EXPECT)
    assert any("more than one shard" in e and "(extra and ui-1)" in e for e in errors)


def test_a_test_in_no_shard_fails(tmp_path):
    errors, _, _ = shard_inventory.check(
        enumeration(tmp_path, ENABLED + ["PDFAlgoProUITests/ScanUITests/testScan"]), three_shards(tmp_path), EXPECT)
    assert any("ran in no shard" in e and "ScanUITests/testScan" in e for e in errors)


def test_a_test_outside_the_inventory_fails_but_a_disabled_one_does_not(tmp_path):
    errors, _, _ = shard_inventory.check(enumeration(tmp_path, ENABLED[:3]), three_shards(tmp_path), EXPECT)
    assert any("not in the inventory" in e for e in errors)
    errors, _, _ = shard_inventory.check(
        enumeration(tmp_path, ENABLED[:3], disabled=ENABLED[3:]), three_shards(tmp_path), EXPECT)
    assert errors == []


def test_an_empty_shard_and_a_missing_shard_fail(tmp_path):
    paths = three_shards(tmp_path)[:2] + [shard(tmp_path, "ui-2", {"PDFAlgoProUITests": {"LibraryUITests": []}})]
    errors, _, _ = shard_inventory.check(enumeration(tmp_path, ENABLED[:3]), paths, EXPECT)
    assert any("shard ui-2 ran no test" in e for e in errors)
    errors, _, _ = shard_inventory.check(enumeration(tmp_path, ENABLED[:3]), [], EXPECT)
    assert {e.split(" has ")[0] for e in errors if "has no test results" in e} == {"shard unit", "shard ui-1", "shard ui-2"}


def test_an_unreadable_shard_fails(tmp_path):
    folder = tmp_path / "ios-shard-unit"
    folder.mkdir()
    (folder / "tests.json").write_text("{not json")
    errors, _, _ = shard_inventory.check(enumeration(tmp_path, []), [str(folder / "tests.json")], ["unit"])
    assert any("shard unit: cannot read" in e for e in errors)
    assert not any("has no test results" in e for e in errors)


def test_an_empty_or_missing_inventory_only_warns(tmp_path):
    paths = three_shards(tmp_path)
    for inventory in (str(tmp_path / "absent.json"), enumeration(tmp_path, [])):
        errors, warnings, _ = shard_inventory.check(inventory, paths, EXPECT)
        assert errors == []
        assert any("inventory" in w and "empty" in w for w in warnings)


def test_identifiers_match_with_or_without_the_bundle_and_parentheses():
    assert shard_inventory.normalise("CoreTests", "CoreTests/DocumentTests/testOpen()") == "CoreTests/DocumentTests/testOpen"
    assert shard_inventory.normalise("CoreTests", "DocumentTests/testOpen()") == "CoreTests/DocumentTests/testOpen"
    assert shard_inventory.normalise("CoreTests", "DocumentTests/open(_:)") == "CoreTests/DocumentTests/open(_:)"


def test_an_enumeration_without_the_enabled_split_is_read_from_its_identifiers(tmp_path):
    path = tmp_path / "flat.json"
    path.write_text(json.dumps({"tests": [{"identifier": "CoreTests/DocumentTests/testOpen()"}]}))
    assert shard_inventory.inventory(str(path)) == ({"CoreTests/DocumentTests/testOpen"}, set())


def test_the_xcode_26_tree_is_read_and_its_differences_can_be_warnings(tmp_path):
    # The shape run 37920045109 wrote: targets, classes (or suites, nested) and tests, by name only.
    path = tmp_path / "tree.json"
    path.write_text(json.dumps({"errors": [], "values": [{"kind": "plan", "name": "PDFAlgoPro", "children": [
        {"kind": "target", "name": "AssistantFeatureTests", "children": [
            {"kind": "class", "name": "AssistantModelTests", "children": [
                {"kind": "test", "name": "ask()"}, {"kind": "test", "name": "unavailable(reason:)"}]},
            {"kind": "suite", "name": "Outer", "children": [
                {"kind": "suite", "name": "Inner", "children": [{"kind": "test", "name": "nested()"}]}]}]}]}]}))
    enabled, disabled = shard_inventory.inventory(str(path))
    assert enabled == {"AssistantFeatureTests/AssistantModelTests/ask",
                       "AssistantFeatureTests/AssistantModelTests/unavailable(reason:)",
                       "AssistantFeatureTests/Outer/Inner/nested"}
    assert disabled == set()
    # Run on CI as warnings until a run shows none: an identifier written differently by the two tools
    # must not fail a pull request whose shards, by construction, leave no test out.
    errors, warnings, _ = shard_inventory.check(str(path), three_shards(tmp_path), EXPECT, warn_only=True)
    assert not any("ran in no shard" in e or "not in the inventory" in e for e in errors)
    assert any("ran in no shard" in w for w in warnings) and any("not in the inventory" in w for w in warnings)


def test_the_plans_skipped_classes_are_not_expected_in_any_shard(tmp_path):
    # Xcode 26 lists the performance classes the plan skips as if enabled (run 37957530086: 10 tests,
    # IntelligenceTests/RetrievalPerformanceTests and two more classes); the plan says they are skipped.
    listed = ENABLED + ["PDFAlgoProTests/EnginePerformanceTests/testOpen500Pages",
                        "PDFAlgoProUITests/LaunchPerformanceTests/testColdLaunch"]
    plan = tmp_path / "PDFAlgoPro.xctestplan"
    plan.write_text(json.dumps({"testTargets": [
        {"target": {"name": "PDFAlgoProTests"}, "skippedTests": ["EnginePerformanceTests"]},
        {"target": {"name": "PDFAlgoProUITests"}, "skippedTests": ["LaunchPerformanceTests"]},
        {"target": {"name": "CoreTests"}}]}))
    skips = shard_inventory.plan_skips(str(plan))
    assert skips == {"PDFAlgoProTests/EnginePerformanceTests", "PDFAlgoProUITests/LaunchPerformanceTests"}
    errors, warnings, _ = shard_inventory.check(enumeration(tmp_path, listed), three_shards(tmp_path), EXPECT,
                                                skips=skips)
    assert errors == [] and warnings == []
    # Without the plan they would count as left out, which is an error once the check is enforced.
    errors, _, _ = shard_inventory.check(enumeration(tmp_path, listed), three_shards(tmp_path), EXPECT)
    assert any("ran in no shard" in e and "EnginePerformanceTests" in e for e in errors)
    # A class only shares a prefix with a skipped one: still expected.
    assert not shard_inventory.skipped_by("PDFAlgoProTests/EnginePerformanceTestsMore/testX", skips)
