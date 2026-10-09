"""Tests for flaky_issues.py: which issues a run's flaky tests open or comment on.

    uv run --with pytest==8.4.2 pytest -q scripts/ci
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import flaky_issues  # noqa: E402

TEST = "PDFAlgoProUITests/PaywallUITests/testOffer()"


def test_an_open_issue_gets_a_comment_and_a_new_flake_an_issue():
    flaky = [{"test": TEST, "message": "Audit found 1 issue"},
             {"test": "PDFAlgoProUITests/ReaderUITests/testZoom()", "message": ""}]
    issues = [{"number": 76, "title": flaky_issues.title_for(TEST)}, {"number": 9, "title": "Unrelated"}]
    assert flaky_issues.plan(flaky, issues) == [
        ("comment", 76, f"Flaky test: {TEST}", "Audit found 1 issue"),
        ("create", None, "Flaky test: PDFAlgoProUITests/ReaderUITests/testZoom()", "")]


def test_a_test_is_handled_once_and_the_run_is_capped():
    flaky = [{"test": TEST}, {"test": TEST}, {"test": ""}, {"message": "no test"}]
    flaky += [{"test": f"T/C/t{i}()"} for i in range(30)]
    actions = flaky_issues.plan(flaky, [])
    assert len(actions) == flaky_issues.MAX_ISSUES
    assert [a[2] for a in actions].count(f"Flaky test: {TEST}") == 1


def test_a_message_cannot_break_out_of_its_block_and_is_kept_short():
    body = flaky_issues.new_issue_body(TEST, "```\n# injected\n" + "x" * 5000, "https://run", "abc123")
    block = body.split("First failure's message:\n\n", 1)[1]
    assert block.startswith("```\n'''\n# injected") and block.count("```") == 2
    assert len(body) < 2500
    assert "testing-strategy.md#flaky-tests" in body


def test_nothing_to_do_without_flaky_tests(tmp_path, capsys):
    assert flaky_issues.main([str(tmp_path / "missing.json"), "--run-url", "u", "--sha", "s"]) == 0
    empty = tmp_path / "flaky.json"
    empty.write_text("[]")
    assert flaky_issues.main([str(empty), "--run-url", "u", "--sha", "s"]) == 0
    assert "no flaky tests" in capsys.readouterr().out


def test_a_dry_run_says_what_it_would_do_without_calling_gh(tmp_path, capsys, monkeypatch):
    path = tmp_path / "flaky.json"
    path.write_text(json.dumps([{"test": TEST, "message": "m"}]))
    monkeypatch.setattr(flaky_issues, "gh", lambda *a: (_ for _ in ()).throw(AssertionError("gh called")))
    assert flaky_issues.main([str(path), "--run-url", "u", "--sha", "0123456789abcdef", "--dry-run"]) == 0
    assert f"would create: Flaky test: {TEST}" in capsys.readouterr().out


def test_issues_are_opened_with_the_policy_labels(tmp_path, monkeypatch):
    path = tmp_path / "flaky.json"
    path.write_text(json.dumps([{"test": TEST, "message": "m"}]))
    calls = []

    def fake(*args):
        calls.append(args)
        return "[]" if args[:2] == ("issue", "list") else "https://github.com/o/r/issues/1\n"
    monkeypatch.setattr(flaky_issues, "gh", fake)
    assert flaky_issues.main([str(path), "--run-url", "https://run", "--sha", "0123456789abcdef"]) == 0
    create = calls[1]
    assert create[:2] == ("issue", "create")
    assert ("--label", "bug") == create[4:6] and ("--label", "flaky") == create[6:8]
    assert "0123456789ab " in create[-1] or "0123456789ab." in create[-1]
