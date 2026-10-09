"""Tests for ci_timings.py with jobs as the GitHub API lists them.

    uv run --with pytest==8.4.2 pytest -q scripts/ci
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ci_timings  # noqa: E402

RUN = {"id": 1, "run_attempt": 1, "event": "push", "head_branch": "integration", "head_sha": "abc",
       "run_started_at": "2026-10-09T10:00:00Z"}


def job(name: str, start: str, end: str | None, conclusion: str | None = "success", created: str = "10:00:00"):
    return {"name": name, "status": "completed" if end else "in_progress", "conclusion": conclusion,
            "created_at": f"2026-10-09T{created}Z", "started_at": f"2026-10-09T{start}Z",
            "completed_at": f"2026-10-09T{end}Z" if end else None}


JOBS = [job("ios-build", "10:00:30", "10:09:30"),
        job("ios-tests (ui-2)", "10:11:00", "10:33:00", created="10:09:40"),
        job("ios-tests (unit)", "10:10:00", "10:20:00"),
        job("ios-serial", "10:00:00", "10:00:00", conclusion="skipped"),
        job("ios", "10:40:00", "10:42:00"),
        job("ci-timings", "10:42:10", None, conclusion=None)]


def test_each_finished_job_is_timed_and_ios_from_the_run_start(tmp_path, capsys):
    run, jobs, out = tmp_path / "run.json", tmp_path / "jobs.jsonl", tmp_path / "t.json"
    run.write_text(json.dumps(RUN))
    jobs.write_text("\n".join(json.dumps(j) for j in JOBS))
    assert ci_timings.main([str(run), str(jobs), "--out", str(out)]) == 0
    record = json.loads(out.read_text())
    assert record["ios_minutes"] == 42.0
    assert [(j["name"], j["minutes"]) for j in record["jobs"]] == [
        ("ios-tests (ui-2)", 22.0), ("ios-tests (unit)", 10.0), ("ios-build", 9.0), ("ios", 2.0)]
    assert record["jobs"][0]["queued_minutes"] == 1.3
    printed = capsys.readouterr().out
    assert "::warning title=Slow shard::ios-tests (ui-2) ran 22.0 minutes, more than 20" in printed
    assert "ios-tests (unit) ran" not in printed


def test_api_pages_are_read_too(tmp_path):
    path = tmp_path / "jobs.json"
    path.write_text(json.dumps({"jobs": JOBS[:2]}) + "\n" + json.dumps({"jobs": JOBS[2:3]}))
    assert [j["name"] for j in ci_timings.read_jobs(str(path))] == ["ios-build", "ios-tests (ui-2)", "ios-tests (unit)"]


def test_a_run_without_a_verdict_has_no_ios_time():
    record = ci_timings.timings(RUN, JOBS[:2])
    assert record["ios_minutes"] is None and "`ios` reported" not in ci_timings.summary(record)
