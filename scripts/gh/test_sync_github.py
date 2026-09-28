"""Offline tests for sync_github.py: `gh` is replaced by a fake, nothing touches GitHub.

    uv run --with pytest==8.4.2 --with pyyaml==6.0.2 pytest -q scripts/gh
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sync_github  # noqa: E402

REPO = sync_github.REPO


class FakeGh:
    """Answers `gh api` and `gh project` calls from canned responses and records every call."""

    def __init__(self, responses: dict[str, object]):
        self.responses = responses
        self.calls: list[tuple[list[str], object]] = []

    def __call__(self, cmd, input=None, capture_output=True, text=True):
        payload = json.loads(input) if input else None
        self.calls.append((cmd, payload))
        path = api_path(cmd) if cmd[:2] == ["gh", "api"] else " ".join(cmd[1:3])
        if "--slurp" in cmd and "--paginate" not in cmd:
            raise AssertionError("--slurp needs --paginate")
        if cmd[:2] == ["gh", "api"] and "-X" in cmd:
            out = {"number": 99, "html_url": f"https://github.com/{REPO}/issues/99"}
        elif cmd[:3] == ["gh", "project", "item-add"]:
            out = {"id": "PVTI_fake"}
        else:
            out = self.responses[path]
        return subprocess.CompletedProcess(cmd, 0, stdout=json.dumps(out), stderr="")

    def writes(self) -> list[tuple[str, str, object]]:
        return [(c[c.index("-X") + 1], api_path(c), p) for c, p in self.calls if c[:2] == ["gh", "api"] and "-X" in c]


def api_path(cmd: list[str]) -> str:
    args = iter(cmd[2:])
    for arg in args:
        if arg in {"-H", "-X", "--input"}:
            next(args, None)
        elif not arg.startswith("-"):
            return arg
    raise AssertionError(f"no path in {cmd}")


@pytest.fixture(autouse=True)
def no_sleep(monkeypatch):
    monkeypatch.setattr(sync_github.time, "sleep", lambda _s: None)


def install(monkeypatch, responses) -> FakeGh:
    fake = FakeGh(responses)
    monkeypatch.setattr(sync_github.subprocess, "run", fake)
    return fake


def label(name: str, color: str = "ededed", description: str = "") -> dict:
    return {"name": name, "color": color, "description": description}


def test_gh_list_flattens_slurped_pages(monkeypatch):
    page1 = [{"n": i} for i in range(100)]
    page2 = [{"n": 100}, {"n": 101}]
    fake = install(monkeypatch, {"repos/x/labels?per_page=100": [page1, page2]})
    items = sync_github.gh_list("repos/x/labels?per_page=100")
    assert [i["n"] for i in items] == list(range(102))
    cmd = fake.calls[0][0]
    assert "--paginate" in cmd and "--slurp" in cmd


def test_label_names_are_url_encoded(monkeypatch, tmp_path):
    (tmp_path / ".github").mkdir()
    (tmp_path / ".github/labels.yml").write_text(
        "labels:\n  - name: good first issue\n    color: '7057ff'\n    description: new\n")
    monkeypatch.setattr(sync_github, "ROOT", tmp_path)
    fake = install(monkeypatch, {
        f"repos/{sync_github.ORG_LABELS[0]}/contents/{sync_github.ORG_LABELS[1]}": [label("security", "b60205")],
        f"repos/{REPO}/labels?per_page=100": [[label("security", "b60205"), label("good first issue", "000000", "old")]],
    })
    assert sync_github.sync_labels(apply=True) == 1
    method, path, payload = fake.writes()[0]
    assert method == "PATCH"
    assert path == f"repos/{REPO}/labels/good%20first%20issue"
    assert payload["color"] == "7057ff"


def test_merged_labels_keeps_triage_and_replaces_stale_priority():
    current = {"priority:p2", "size:m", "status:in-progress", "blocked", "flaky", "pdf"}
    planned = {"priority:p0", "size:m", "pdf", "enhancement"}
    assert sync_github.merged_labels(current, planned) == {
        "priority:p0", "size:m", "pdf", "enhancement", "status:in-progress", "blocked", "flaky"}


def write_backlog(tmp_path: Path) -> None:
    (tmp_path / "docs/planning").mkdir(parents=True)
    (tmp_path / "docs/planning/backlog.yaml").write_text(
        "items:\n"
        "  - id: F-001\n    title: Spike\n    type: spike\n    milestone: Foundation\n    priority: p0\n"
        "    size: l\n    pillars: [PIL-1]\n    labels: [pdf]\n    acceptance: [done]\n"
        "  - id: M-001\n    title: Reader\n    type: epic\n    milestone: MVP\n    priority: p1\n"
        "    size: xl\n    pillars: [PIL-1]\n    labels: [ios]\n    acceptance: [done]\n")


def backlog_responses(extra_labels: list[str], priority: str = "p0") -> dict:
    issue = {
        "number": 7, "title": "Spike", "html_url": f"https://github.com/{REPO}/issues/7",
        "body": "<!-- backlog-id: F-001 -->\nbody", "milestone": {"number": 1},
        "labels": [{"name": n} for n in ["pdf", f"priority:{priority}", "size:l", *extra_labels]],
    }
    return {
        f"repos/{REPO}/milestones?state=all&per_page=100": [[{"title": "Foundation", "number": 1}, {"title": "MVP", "number": 2}]],
        f"repos/{REPO}/issues?state=all&per_page=100": [[issue], [{"number": 8, "pull_request": {}, "body": "<!-- backlog-id: F-001 -->"}]],
        "project item-list": {"items": [{"content": {"url": f"https://github.com/{REPO}/issues/7"}}]},
    }


def test_backlog_up_to_date_issue_with_triage_labels_is_not_patched(monkeypatch, tmp_path):
    write_backlog(tmp_path)
    monkeypatch.setattr(sync_github, "ROOT", tmp_path)
    fake = install(monkeypatch, backlog_responses(["status:blocked", "flaky"]))
    changes = sync_github.sync_backlog(apply=True)
    writes = fake.writes()
    assert changes == 1  # only M-001 is created
    assert [(m, p) for m, p, _ in writes] == [("POST", f"repos/{REPO}/issues")]
    assert writes[0][2]["labels"] == ["enhancement", "ios", "priority:p1", "size:xl"]
    assert "<!-- backlog-id: M-001 -->" in writes[0][2]["body"]


def test_backlog_priority_change_keeps_triage_labels(monkeypatch, tmp_path):
    write_backlog(tmp_path)
    monkeypatch.setattr(sync_github, "ROOT", tmp_path)
    fake = install(monkeypatch, backlog_responses(["status:blocked", "flaky"], priority="p3"))
    sync_github.sync_backlog(apply=True)
    patch = next(p for m, path, p in fake.writes() if m == "PATCH")
    assert patch == {"labels": ["flaky", "pdf", "priority:p0", "size:l", "status:blocked"]}


def test_backlog_project_adds_only_missing_issues(monkeypatch, tmp_path):
    write_backlog(tmp_path)
    monkeypatch.setattr(sync_github, "ROOT", tmp_path)
    fake = install(monkeypatch, backlog_responses([]))
    sync_github.sync_backlog(apply=True, project=3)
    adds = [c for c, _ in fake.calls if c[:3] == ["gh", "project", "item-add"]]
    assert adds == [["gh", "project", "item-add", "3", "--owner", sync_github.OWNER,
                     "--url", f"https://github.com/{REPO}/issues/99"]]


def test_backlog_dry_run_writes_nothing(monkeypatch, tmp_path):
    write_backlog(tmp_path)
    monkeypatch.setattr(sync_github, "ROOT", tmp_path)
    fake = install(monkeypatch, backlog_responses([]))
    assert sync_github.sync_backlog(apply=False, project=3) == 2  # create M-001, then add it
    assert fake.writes() == []
    assert not [c for c, _ in fake.calls if c[:3] == ["gh", "project", "item-add"]]


def test_project_flag_is_backlog_only():
    with pytest.raises(SystemExit):
        sync_github.main(["sync_github.py", "labels", "--project", "3"])
