"""Tests for rebalance_shards.py with synthetic per-class times.

    uv run --with pytest==8.4.2 pytest -q scripts/ci
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rebalance_shards  # noqa: E402

UI = "PDFAlgoProUITests"


def results(tmp_path: Path, times: dict[str, float], name: str = "tests.json") -> str:
    suites = [{"nodeType": "Test Suite", "name": cls, "children": [
        {"nodeType": "Test Case", "name": "testA()", "nodeIdentifier": f"{cls}/testA()", "result": "Passed",
         "durationInSeconds": seconds}]} for cls, seconds in times.items()]
    tree = {"testNodes": [{"nodeType": "Test Plan", "name": "PDFAlgoPro", "children": [
        {"nodeType": "UI test bundle", "name": UI, "children": suites},
        {"nodeType": "Unit test bundle", "name": "CoreTests", "children": [
            {"nodeType": "Test Suite", "name": "Slow", "children": [
                {"nodeType": "Test Case", "name": "t()", "result": "Passed", "durationInSeconds": 9999}]}]}]}]}
    path = tmp_path / name
    path.write_text(json.dumps(tree))
    return str(path)


def config(tmp_path: Path, ui1: list[str], ui2: list[str]) -> str:
    path = tmp_path / "test_shards.json"
    path.write_text(json.dumps({"uiTarget": UI, "ui-1": ui1, "ui-2": ui2}))
    return str(path)


def test_only_ui_classes_are_counted_across_shards(tmp_path):
    a = results(tmp_path, {"A": 100, "B": 50}, "a.json")
    b = results(tmp_path, {"A": 20, "C": 30}, "b.json")
    assert rebalance_shards.class_seconds([a, b], UI) == {"A": 120, "B": 50, "C": 30}


def test_the_proposal_balances_and_the_heaviest_shard_is_the_complement():
    seconds = {"A": 500, "B": 400, "C": 300, "D": 200, "E": 100}
    proposal = rebalance_shards.propose(seconds)
    assert list(rebalance_shards.load_of(proposal, seconds).values()) == [500, 500, 500]
    assert set(sum(proposal.values(), [])) == set(seconds)
    seconds = {"A": 600, "B": 300, "C": 200, "D": 100}
    proposal = rebalance_shards.propose(seconds)
    assert proposal["ui-3"] == ["A"] and rebalance_shards.load_of(proposal, seconds)["ui-3"] == 600


def test_an_unbalanced_split_is_rewritten_and_a_balanced_one_left(tmp_path, capsys):
    tests = results(tmp_path, {"A": 500, "B": 400, "C": 300, "D": 200, "E": 100})
    path = config(tmp_path, ["E"], ["D"])  # ui-3 would carry A, B and C: 1200 s
    assert rebalance_shards.main([tests, "--config", path, "--write"]) == 0
    assert "Rebalancing would shorten" in capsys.readouterr().out
    written = json.loads(Path(path).read_text())
    assert written["uiTarget"] == UI and written["ui-1"] and written["ui-2"]
    assert rebalance_shards.main([tests, "--config", path, "--write"]) == 0
    out = capsys.readouterr().out
    assert "no change needed" in out and "wrote" not in out


def test_results_without_ui_tests_say_so(tmp_path, capsys):
    path = tmp_path / "unit.json"
    path.write_text(json.dumps({"testNodes": []}))
    assert rebalance_shards.main([str(path), "--config", config(tmp_path, ["A"], ["B"])]) == 0
    assert "no UI test times" in capsys.readouterr().out
