#!/usr/bin/env python3
"""Record how long each job of a CI run took, and warn when a test shard runs long. Standard library only.

    gh api "repos/$REPO/actions/runs/$RUN_ID" > run.json
    gh api --paginate "repos/$REPO/actions/runs/$RUN_ID/attempts/$ATTEMPT/jobs" --jq '.jobs[]' > jobs.jsonl
    python3 scripts/ci/ci_timings.py run.json jobs.jsonl --out ci-timings.json [--summary "$GITHUB_STEP_SUMMARY"]

Writes one JSON record per run attempt: the event, branch and commit, how long `ios` took from the
attempt's start to its verdict, and each finished job's minutes running and minutes queued for a
runner. A job a re-run kept from an earlier attempt has no queued time: the API dates its creation to
the re-run but its start to the earlier attempt (run 38000339542, attempt 2, showed -44 minutes). The
`ci.yml` `ci-timings` job keeps it as the `ci-timings` artifact for 90 days, the data behind the
time target (`ios` within 22 minutes at the median, docs/process/quality-gates.md#the-ios-job-graph).

Warns (never fails) when a test shard ran longer than --shard-minutes (20 by default): one shard
far slower than the others is the sign to rebalance them (rebalance_shards.py proposes how).
"""
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime

SHARD_PREFIX = "ios-tests ("
VERDICTS = ("ios", "ios-manual", "ios-focused")


def when(value) -> datetime | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def minutes(start: datetime | None, end: datetime | None) -> float | None:
    return round((end - start).total_seconds() / 60, 1) if start and end else None


def read_jobs(path: str) -> list[dict]:
    """Jobs from `gh api --paginate ... --jq '.jobs[]'` (one JSON object per line), or from pages as the
    API returns them ({"jobs": [...]}, one or more)."""
    jobs: list[dict] = []
    with open(path, encoding="utf-8") as f:
        decoder, text = json.JSONDecoder(), f.read()
    index = 0
    while True:
        while index < len(text) and text[index].isspace():
            index += 1
        if index == len(text):
            return jobs
        item, index = decoder.raw_decode(text, index)
        jobs.extend(item.get("jobs", []) if isinstance(item, dict) and "jobs" in item else [item])


def timings(run: dict, jobs: list[dict]) -> dict:
    started = when(run.get("run_started_at")) or when(run.get("created_at"))
    rows = []
    for job in jobs:
        if job.get("status") != "completed" or job.get("conclusion") == "skipped":
            continue
        job_start, created = when(job.get("started_at")), when(job.get("created_at"))
        earlier = bool(started and job_start and job_start < started)
        rows.append({"name": job.get("name", ""), "conclusion": job.get("conclusion"),
                     "minutes": minutes(job_start, when(job.get("completed_at"))),
                     "queued_minutes": None if earlier else minutes(created, job_start),
                     "earlier_attempt": earlier})
    verdict = next((j for j in jobs if j.get("name") in VERDICTS and j.get("status") == "completed"), None)
    return {
        "run_id": run.get("id"), "attempt": run.get("run_attempt"), "event": run.get("event"),
        "branch": run.get("head_branch"), "sha": run.get("head_sha"), "started_at": run.get("run_started_at"),
        "ios_minutes": minutes(started, when(verdict.get("completed_at"))) if verdict else None,
        "jobs": sorted(rows, key=lambda r: -(r["minutes"] or 0)),
    }


def long_shards(record: dict, limit: float) -> list[dict]:
    return [job for job in record["jobs"]
            if job["name"].startswith(SHARD_PREFIX) and job["minutes"] is not None and job["minutes"] > limit]


def summary(record: dict) -> str:
    lines = ["### CI timings", ""]
    if record["ios_minutes"] is not None:
        attempt = record.get("attempt") or 1
        since = "the run started" if attempt == 1 else f"attempt {attempt} started"
        lines += [f"`ios` reported {record['ios_minutes']} minutes after {since}.", ""]
    lines += ["| Job | Minutes | Queued | Result |", "| --- | ---: | ---: | --- |"]
    for job in record["jobs"]:
        result = f"{job['conclusion']} (earlier attempt)" if job.get("earlier_attempt") else job["conclusion"]
        lines.append(f"| {job['name']} | {job['minutes'] if job['minutes'] is not None else '–'} | "
                     f"{job['queued_minutes'] if job['queued_minutes'] is not None else '–'} | {result} |")
    return "\n".join(lines) + "\n\n"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("run", help="`gh api repos/O/R/actions/runs/ID` JSON")
    ap.add_argument("jobs", help="the run attempt's jobs, from `gh api --paginate ... --jq '.jobs[]'`")
    ap.add_argument("--out", required=True)
    ap.add_argument("--summary")
    ap.add_argument("--shard-minutes", type=float, default=20.0)
    args = ap.parse_args(argv)
    with open(args.run, encoding="utf-8") as f:
        run = json.load(f)
    record = timings(run, read_jobs(args.jobs))
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(record, f, indent=2)
    text = summary(record)
    print(text)
    if args.summary:
        with open(args.summary, "a", encoding="utf-8") as f:
            f.write(text)
    for job in long_shards(record, args.shard_minutes):
        # Only the UI shards are balanced by moving classes; the unit shard is one xcodebuild run.
        advice = ("rebalance the shards (scripts/ci/rebalance_shards.py on ios-report's summary)"
                  if job["name"].startswith(SHARD_PREFIX + "ui-")
                  else "its slowest test classes are in its summary")
        print(f"::warning title=Slow shard::{job['name']} ran {job['minutes']} minutes, more than "
              f"{args.shard_minutes:g}: {advice}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
