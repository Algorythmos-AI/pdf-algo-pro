#!/usr/bin/env python3
"""Open or update one issue per flaky test, so no flake seen on `integration` goes untracked.

    python3 scripts/ci/flaky_issues.py flaky.json --run-url URL --sha SHA [--dry-run]

Reads the flaky tests xcresult_report.py --flaky-out wrote for a run (tests that failed, then passed
when run again on their own) and, through the `gh` CLI (GH_TOKEN and GH_REPO set by the job):

  * comments on the open issue titled "Flaky test: <test>" with the run, commit and message, or
  * opens that issue, labelled `bug` and `flaky` as the flaky test policy asks
    (docs/testing-strategy.md#flaky-tests), when none is open.

It never closes an issue: a flake that stopped showing is closed by the fix that removed its cause.
At most MAX_ISSUES tests are handled per run, so a run with many flakes (which already fails the
flake budget) cannot flood the tracker. The `ci.yml` `flaky-issues` job runs it on pushes and the
nightly only, never on a pull request, whose flakes may be the change's own. Standard library only.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys

LABELS = ("bug", "flaky")
PREFIX = "Flaky test: "
MAX_ISSUES = 10
MAX_MESSAGE = 1500


def title_for(test: str) -> str:
    return f"{PREFIX}{test}"


def quoted(message: str) -> str:
    """The failure message as a fenced block that the message itself cannot close."""
    text = (message or "no message recorded").replace("```", "'''")
    if len(text) > MAX_MESSAGE:
        text = text[:MAX_MESSAGE] + " …"
    return f"```\n{text}\n```"


def new_issue_body(test: str, message: str, run_url: str, sha: str) -> str:
    return "\n".join([
        f"`{test}` failed, then passed when run again on its own, in [this run]({run_url}) on {sha}.",
        "",
        "First failure's message:",
        "",
        quoted(message),
        "",
        "Per the [flaky test policy](../blob/integration/docs/testing-strategy.md#flaky-tests): quarantine "
        "it the same day, then fix the cause or delete the test within five business days. Each later run "
        "that sees it flaky adds a comment here.",
        "",
        "Opened by the `flaky-issues` job of `ci.yml` (scripts/ci/flaky_issues.py).",
    ])


def comment_body(message: str, run_url: str, sha: str) -> str:
    return "\n".join([f"Flaky again in [this run]({run_url}) on {sha}:", "", quoted(message)])


def plan(flaky: list[dict], open_issues: list[dict]) -> list[tuple[str, int | None, str, str]]:
    """(action, issue number or None, title, message) per distinct flaky test, at most MAX_ISSUES:
    action is "comment" when an open issue has the test's title, otherwise "create"."""
    by_title = {issue.get("title"): issue.get("number") for issue in open_issues}
    seen: set[str] = set()
    actions = []
    for entry in flaky:
        test = entry.get("test")
        if not isinstance(test, str) or not test or test in seen:
            continue
        seen.add(test)
        title = title_for(test)
        number = by_title.get(title)
        actions.append(("comment" if number else "create", number, title, entry.get("message") or ""))
        if len(actions) == MAX_ISSUES:
            break
    return actions


def gh(*args: str) -> str:
    return subprocess.run(["gh", *args], check=True, capture_output=True, text=True).stdout


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("flaky", help="the JSON xcresult_report.py --flaky-out wrote")
    ap.add_argument("--run-url", required=True)
    ap.add_argument("--sha", required=True)
    ap.add_argument("--dry-run", action="store_true", help="print what would be done, change nothing")
    args = ap.parse_args(argv)
    try:
        with open(args.flaky, encoding="utf-8") as f:
            flaky = json.load(f)
    except FileNotFoundError:
        print("no flaky tests were recorded for this run")
        return 0
    if not isinstance(flaky, list) or not flaky:
        print("no flaky tests in this run")
        return 0
    sha = args.sha[:12]
    open_issues = [] if args.dry_run else json.loads(gh(
        "issue", "list", "--label", "flaky", "--state", "open", "--limit", "500", "--json", "number,title"))
    for action, number, title, message in plan(flaky, open_issues):
        test = title[len(PREFIX):]
        if args.dry_run:
            print(f"would {action}{f' #{number}' if number else ''}: {title}")
        elif action == "comment":
            gh("issue", "comment", str(number), "--body", comment_body(message, args.run_url, sha))
            print(f"commented on #{number}: {title}")
        else:
            label_args = [part for label in LABELS for part in ("--label", label)]
            url = gh("issue", "create", "--title", title, *label_args,
                     "--body", new_issue_body(test, message, args.run_url, sha)).strip()
            print(f"opened {url}: {title}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
