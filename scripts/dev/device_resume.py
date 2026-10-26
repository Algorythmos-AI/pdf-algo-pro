#!/usr/bin/env python3
"""Runs on after a test runner that stopped: the device test run's resume helpers. Standard library only.

    python3 scripts/dev/device_resume.py next enumerated.json tests.json [more.json ...] \
        [--retries retry-tests.json] [--with-failed]
    python3 scripts/dev/device_resume.py report enumerated.json tests.json [more.json ...] \
        [--retries retry-tests.json] --summary summary.md --failed-ids failed.txt --counts counts.txt
    python3 scripts/dev/device_resume.py attachments failed.txt attachments/ failed-attachments/
    python3 scripts/dev/device_resume.py unlisted enumerated.json summary.md

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

`attachments` copies each failed test's attachments out of every result bundle's export, the first run's,
its retry's and each resumed run's, into a folder per test, as CI's failed-attachments/ holds them.

`unlisted` adds to the summary what kept xcodebuild from listing the plan's tests, and exits 1 when
anything did. A target whose runner cannot start is left out of the listing, so its tests are not
counted as missing: on 2026-10-26 the UI test runner timed out "while enabling automation mode", the
listing held only the 70 unit tests, and the summary showed a single runner error for the whole of the
UI tests.
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "ci"))
import xcresult_report  # noqa: E402
from xcresult_report import Case  # noqa: E402

# The trail of the entry xcodebuild records when the test runner stops.
RUNNER_STOP = "System Failures"


def selector(identifier: str) -> str:
    """A test as the results name it, the way xcresult_report.Case.selector does: without "()"."""
    return identifier[:-2] if identifier.endswith("()") else identifier


def enabled(path: Path) -> dict[str, str]:
    """The plan's enabled tests, in the order xcodebuild lists them: each one's selector, and the
    identifier `-only-testing` needs for it.

    That is the identifier as listed, "()" and all: a Swift Testing test is found only with it (on the
    iPhone run of 2026-10-26, `PDFAlgoProTests/AppLockTests/off` matched nothing and 65 unit tests never
    ran), and an XCTest test is found with it or without.

    Only Target/Class/test entries: xcodebuild also lists a test class with no tests of its own, such as
    UITestCase, the UI tests' base class, as Target/Class, and no result ever holds it.
    """
    data = json.loads(path.read_text(encoding="utf-8"))
    found: dict[str, str] = {}
    for value in data.get("values", []):
        for test in value.get("enabledTests", []):
            identifier = test.get("identifier", "")
            ident = selector(identifier)
            if ident.count("/") >= 2 and ident not in found:
                found[ident] = identifier
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
                if case.verdict in ("passed", "quarantined"):
                    known.verdict = "flaky"
                elif case.verdict == "failed":
                    known.messages += [m for m in case.messages if m not in known.messages]
    return order


def failed_attachments(failed_ids: Path, exported: Path, out: Path) -> int:
    """Copies each failed test's attachments, from every bundle exported under `exported`, into
    out/<test>/; returns how many files it copied.

    A test can fail in a resumed run as well as the first, so every bundle's export is read. An export's
    manifest names a test Class/method(), without its bundle; the folder is named as CI names it.
    """
    failed = [line.strip() for line in failed_ids.read_text(encoding="utf-8").splitlines() if line.strip()]
    wanted = {selector(test.partition("/")[2]): test for test in failed}
    copied = 0
    for manifest in sorted(exported.glob("*/manifest.json")):
        for entry in json.loads(manifest.read_text(encoding="utf-8")):
            test = wanted.get(selector(entry.get("testIdentifier", "")))
            if test is None:
                continue
            folder = out / re.sub(r"[^A-Za-z0-9._-]", "_", test)
            folder.mkdir(parents=True, exist_ok=True)
            for attachment in entry.get("attachments", []):
                source = manifest.parent / attachment.get("exportedFileName", "")
                if source.is_file():
                    shutil.copy2(source, folder / f"{manifest.parent.name}-{source.name}")
                    copied += 1
    return copied


def listing_errors(path: Path) -> list[str]:
    """What xcodebuild said kept it from listing the plan's tests, if anything."""
    data = json.loads(path.read_text(encoding="utf-8"))
    return [str(error) for error in data.get("errors", []) if str(error).strip()]


def missing(plan: dict[str, str], cases: list[Case]) -> list[str]:
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
    p = sub.add_parser("unlisted")
    p.add_argument("enumerated", type=Path, help="`xcodebuild -enumerate-tests` JSON")
    p.add_argument("summary", type=Path, help="the run's summary, added to")
    p = sub.add_parser("attachments")
    p.add_argument("failed_ids", type=Path, help="the failed tests' selectors, one per line")
    p.add_argument("exported", type=Path, help="a folder of `xcresulttool export attachments` folders, one per bundle")
    p.add_argument("out", type=Path, help="where each failed test's folder goes")
    args = ap.parse_args(argv)

    if args.command == "unlisted":
        errors = listing_errors(args.enumerated)
        if not errors:
            return 0
        note = ("\n#### Not listed\n\nxcodebuild could not list every test of the plan, so the tests of a "
                "target whose runner did not start are in no count above and did not run:\n\n"
                + "".join(f"- {error}\n" for error in errors))
        with args.summary.open("a", encoding="utf-8") as summary:
            summary.write(note)
        print(f"xcodebuild could not list every test ({len(errors)} error(s)); see the summary")
        return 1

    if args.command == "attachments":
        print(f"{failed_attachments(args.failed_ids, args.exported, args.out)} attachment(s) of failed tests")
        return 0

    plan = enabled(args.enumerated)
    cases = merged(args.results, args.retries)
    absent = missing(plan, cases)

    if args.command == "next":
        # Only after a runner that stopped: an ordinary failure already had its one retry.
        selectors = list(absent)
        if absent and args.with_failed:
            selectors += [c.selector for c in cases if c.verdict == "failed" and not is_runner_stop(c)
                          and c.selector not in selectors]
        print("\n".join(f"-only-testing:{plan.get(s, s)}" for s in selectors))
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
