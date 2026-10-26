#!/usr/bin/env python3
"""Runs on after a test runner that stopped: the device test run's resume helpers. Standard library only.

    python3 scripts/dev/device_resume.py next enumerated.json tests.json [more.json ...] \
        [--retries retry-tests.json] [--with-failed]
    python3 scripts/dev/device_resume.py report enumerated.json tests.json [more.json ...] \
        [--retries retry-tests.json] --summary summary.md --failed-ids failed.txt --counts counts.txt

On an iPhone reached over Wi-Fi the UI test runner can lose the phone partway ("An error occurred while
communicating with a remote process"). xcodebuild then ends the run: the tests the runner had not reached
never run, and the result bundle holds only the ones it had. Its one crash entry ("System Failures/…
encountered an error") is not a test, so the usual retry of failed tests (test_shards.py retry-args)
declines to run anything again.

`next` compares the plan's enabled tests (`xcodebuild -enumerate-tests -test-enumeration-format json`)
with every result file so far, and prints `-only-testing` selectors for the tests no result file holds,
one per line; with --with-failed, also the tests that failed (not the runner's crash entries), so a
test the dying runner was in the middle of runs again. It prints nothing when every test has run: an
ordinary failure, with no test missing, has had its one retry already.

`report` gives the run's verdict over the first run, its retry and every resumed run, in that order: a test
that failed and later passed is flaky, one that failed again stays failed with both messages, and a
test that never ran in any of them is failed ("never ran"). The runner's crash entries are not tests:
the summary says how often the runner stopped, and only the tests decide the verdict. It writes the summary, the failed tests' selectors and "passed / failed / flaky" for the
record, and exits 1 when any test failed or never ran.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "ci"))
import xcresult_report  # noqa: E402
from xcresult_report import Case  # noqa: E402

# The trail of the entry xcodebuild records when the test runner stops.
RUNNER_STOP = "System Failures"


def selector(identifier: str) -> str:
    """A test as `-only-testing` names it, the way xcresult_report.Case.selector does: without "()"."""
    return identifier[:-2] if identifier.endswith("()") else identifier


def enabled(path: Path) -> list[str]:
    """The selectors of the plan's enabled tests, in the order xcodebuild lists them.

    Only Target/Class/test entries: xcodebuild also lists a test class with no tests of its own, such as
    UITestCase, the UI tests' base class, as Target/Class, and no result ever holds it.
    """
    data = json.loads(path.read_text(encoding="utf-8"))
    found: list[str] = []
    for value in data.get("values", []):
        for test in value.get("enabledTests", []):
            ident = selector(test.get("identifier", ""))
            if ident.count("/") >= 2 and ident not in found:
                found.append(ident)
    return found


def is_runner_stop(case: Case) -> bool:
    return RUNNER_STOP in case.trail


def merged(results: list[Path], retries: Path | None) -> list[Case]:
    """Every test's case across the runs, a later run's verdict deciding a test that failed before."""
    first, _ = xcresult_report.load([str(results[0])])
    if retries is not None and retries.exists():
        retried, _ = xcresult_report.load([str(retries)])
        xcresult_report.apply_retries(first, retried)
    by_selector = {case.selector: case for case in first}
    order = list(first)
    for path in results[1:]:
        later, _ = xcresult_report.load([str(path)])
        for case in later:
            if is_runner_stop(case):
                order.append(case)
                continue
            known = by_selector.get(case.selector)
            if known is None:
                by_selector[case.selector] = case
                order.append(case)
            elif known.verdict == "failed":
                if case.verdict == "passed":
                    known.verdict = "flaky"
                elif case.verdict == "failed":
                    known.messages += [m for m in case.messages if m not in known.messages]
    return order


def missing(plan: list[str], cases: list[Case]) -> list[str]:
    ran = {case.selector for case in cases if not is_runner_stop(case)}
    return [test for test in plan if test not in ran]


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="command", required=True)
    for name in ("next", "report"):
        p = sub.add_parser(name)
        p.add_argument("enumerated", type=Path, help="`xcodebuild -enumerate-tests` JSON")
        p.add_argument("results", type=Path, nargs="+", help="`xcresulttool get test-results tests` JSON, in order")
        p.add_argument("--retries", type=Path, help="the failed tests' second run, as xcb_test_with_retry wrote it")
        if name == "next":
            p.add_argument("--with-failed", action="store_true", help="also the tests that failed")
        else:
            p.add_argument("--summary", type=Path, required=True)
            p.add_argument("--failed-ids", type=Path, required=True)
            p.add_argument("--counts", type=Path, required=True)
    args = ap.parse_args(argv)

    plan = enabled(args.enumerated)
    cases = merged(args.results, args.retries)
    absent = missing(plan, cases)

    if args.command == "next":
        # Only after a runner that stopped: an ordinary failure already had its one retry.
        selectors = list(absent)
        if absent and args.with_failed:
            selectors += [c.selector for c in cases if c.verdict == "failed" and not is_runner_stop(c)
                          and c.selector not in selectors]
        print("\n".join(f"-only-testing:{s}" for s in selectors))
        return 0

    stops = [c for c in cases if is_runner_stop(c)]
    tests = [c for c in cases if not is_runner_stop(c)]
    for test in absent:
        bundle, _, rest = test.partition("/")
        tests.append(Case(test, rest, [bundle], "failed",
                          ["never ran: the test runner stopped before it, every time it was run"]))
    summary = xcresult_report.summary(tests, None)
    if stops:
        summary += (f"The test runner stopped {len(stops)} time(s) (a dropped connection to the phone); "
                    + (f"{len(absent)} test(s) never ran.\n" if absent
                       else "every test it had not reached was run again.\n"))
    args.summary.write_text(summary, encoding="utf-8")
    failed = [c for c in tests if c.verdict == "failed"]
    args.failed_ids.write_text("".join(f"{c.selector}\n" for c in failed), encoding="utf-8")
    by = {v: sum(c.verdict == v for c in tests if not is_runner_stop(c)) for v in ("passed", "failed", "flaky")}
    args.counts.write_text(f"{by['passed']} / {by['failed']} / {by['flaky']}\n", encoding="utf-8")
    print(f"tests: {by['passed']} passed, {by['failed']} failed, {by['flaky']} flaky"
          f"{f', {len(absent)} never ran' if absent else ''}"
          f"{f'; the runner stopped {len(stops)} time(s)' if stops else ''}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
