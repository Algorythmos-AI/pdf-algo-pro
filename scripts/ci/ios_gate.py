#!/usr/bin/env python3
"""The verdict of the required `ios` check, from the results of the jobs it stands for. Standard library only.

    NEEDS_JSON='${{ toJSON(needs) }}' ONLY_TESTING='${{ inputs.only_testing }}' python3 scripts/ci/ios_gate.py

`ios` is the one check the rulesets require for the iOS gates, so it must be green only when every
gate it stands for ran and passed, or when none had to run. GitHub reports a job skipped by its
condition as successful, and skips every job after a failed one, so each job's own result is not
enough. The rules:

  * `changes` must have succeeded and said `ios` is "true" or "false"; anything else fails, because
    it is then unknown whether the gates had to run.
  * ios "false" (no Swift or project input changed): every other job must have been skipped.
  * ios "true": ios-build, ios-device, ios-tests and ios-report must all have succeeded.
  * A focused run (a manual run with `only_testing`, reported as `ios-focused`, never as `ios`):
    ios-build and ios-tests must have succeeded; ios-report and ios-device are skipped on purpose.

A cancelled run never reaches this job, so it never turns green.
"""
from __future__ import annotations

import json
import os
import sys

JOBS = ("changes", "ios-build", "ios-device", "ios-tests", "ios-report")


def verdict(needs: dict, only_testing: str | None) -> tuple[bool, list[str]]:
    """(passes, reasons it does not)."""
    problems: list[str] = []
    results = {job: (needs.get(job) or {}).get("result", "missing") for job in JOBS}
    if results["changes"] != "success":
        return False, [f"changes ended with '{results['changes']}', so it is unknown whether the iOS gates had to run"]
    ios = ((needs.get("changes") or {}).get("outputs") or {}).get("ios")
    if ios not in ("true", "false"):
        return False, [f"changes succeeded but its ios output is {ios!r}, not 'true' or 'false'"]
    others = [job for job in JOBS if job != "changes"]
    if ios == "false":
        for job in others:
            if results[job] != "skipped":
                problems.append(f"{job} ended with '{results[job]}' although no Swift or project input changed")
        return not problems, problems
    focused = bool(only_testing and only_testing.strip())
    required = ("ios-build", "ios-tests") if focused else ("ios-build", "ios-device", "ios-tests", "ios-report")
    for job in required:
        if results[job] != "success":
            problems.append(f"{job} ended with '{results[job]}'")
    if focused:
        if results["ios-report"] != "skipped":
            problems.append(f"ios-report ended with '{results['ios-report']}'; a focused run must skip it")
        if results["ios-device"] not in ("skipped", "success"):
            problems.append(f"ios-device ended with '{results['ios-device']}'")
    return not problems, problems


def table(needs: dict) -> str:
    lines = ["| Job | Result |", "| --- | --- |"]
    for job in JOBS:
        lines.append(f"| {job} | {(needs.get(job) or {}).get('result', 'missing')} |")
    ios = ((needs.get("changes") or {}).get("outputs") or {}).get("ios")
    return "\n".join(lines) + f"\n\nchanges says ios = {ios!r}\n"


def main(environ: dict | None = None) -> int:
    environ = os.environ if environ is None else environ
    try:
        needs = json.loads(environ.get("NEEDS_JSON") or "{}")
    except json.JSONDecodeError as error:
        print(f"::error::NEEDS_JSON is not JSON: {error}")
        return 1
    only_testing = environ.get("ONLY_TESTING", "")
    report = table(needs)
    print(report)
    summary = environ.get("GITHUB_STEP_SUMMARY")
    ok, problems = verdict(needs, only_testing)
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write("### iOS gate\n\n" + report + ("\nPassed.\n" if ok else "\n" + "\n".join(f"- {p}" for p in problems) + "\n"))
    for problem in problems:
        print(f"::error::{problem}")
    print("ios gate: passed" if ok else "ios gate: failed")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
