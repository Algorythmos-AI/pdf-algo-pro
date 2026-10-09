#!/usr/bin/env python3
"""Say which tests failed and why, which were flaky, and where the time went. Standard library only.

    xcrun xcresulttool get test-results tests --path Tests.xcresult > tests.json
    python3 scripts/ci/xcresult_report.py tests.json [more.json ...] [--retries retry-tests.json ...] \
        [--failed-ids failed.txt] [--retry-ids retry.txt] [--flaky-budget 3] [--summary "$GITHUB_STEP_SUMMARY"]

Reads the JSON that `xcresulttool get test-results tests` writes, from one result bundle or one per
shard. A test's verdict is its last repetition when the run repeated it, its result in a --retries
file when it failed and was run again on its own (a UI shard re-runs only its failed tests, in a
second result bundle), and its own result otherwise:

- failed: the last repetition failed. Printed as an ::error annotation with every failure message,
  so the run's summary says why without opening the log or the result bundle.
- flaky: an earlier repetition or run failed and the last one passed. Printed as a ::warning with the
  first failure's message, so a retry never hides a problem from the person reading the run.
- quarantined: an expected failure (XCTExpectFailure), listed so the quarantine stays visible.

--failed-ids writes the failed tests' identifiers, one per line, for `xcresulttool export
attachments --test-id`; --retry-ids writes them as `-only-testing` takes them (Target/Class/method).
Exits 1 when a test failed, when more distinct tests were flaky than --flaky-budget allows, or when the input holds no test at all (a crash before any result).
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, field

GROUPS = ("Unit test bundle", "UI test bundle", "Test Suite")
MESSAGE = "Failure Message"
REPETITION = re.compile(r"(\d+)")
# The reasons UITestCase.recordQuarantined gives an expected failure (XCTExpectFailure). Inside a test
# that failed for another reason they are not why it failed: on run 37930118069 each paywall failure was
# annotated a second time as "Quarantined flaky audit finding, issue #76".
QUARANTINE = re.compile(r"^(Quarantined |Measured while the screen was moving)")


@dataclass
class Case:
    identifier: str
    name: str
    trail: list[str]
    verdict: str  # "passed", "failed", "flaky", "skipped" or "quarantined"
    messages: list[str] = field(default_factory=list)
    seconds: float = 0.0

    @property
    def title(self) -> str:
        return "/".join(self.trail + [self.name])

    @property
    def suite(self) -> str:
        return "/".join(self.trail) or "(no suite)"

    @property
    def selector(self) -> str:
        """The test as `-only-testing` names it: its bundle, then its identifier, without "()"."""
        bundle = self.trail[0] if self.trail else ""
        identifier = self.identifier
        if bundle and identifier.startswith(bundle + "/"):
            identifier = identifier[len(bundle) + 1:]
        if identifier.endswith("()"):
            identifier = identifier[:-2]
        return f"{bundle}/{identifier}" if bundle else identifier


def is_expected(node: dict) -> bool:
    return node.get("result") == "Expected Failure" or bool(QUARANTINE.match(node.get("name", "")))


def messages_under(node: dict, expected: bool = True) -> list[str]:
    """Every failure message in a node's subtree, in order, without repeats; without the expected failures'
    (quarantines') when `expected` is false."""
    found: list[str] = []

    def walk(n: dict) -> None:
        if not expected and n.get("nodeType") == MESSAGE and is_expected(n):
            return
        if n.get("nodeType") == MESSAGE and n.get("name") and n["name"] not in found:
            found.append(n["name"])
        for child in n.get("children", []):
            walk(child)

    walk(node)
    return found


def seconds_of(node: dict) -> float:
    value = node.get("durationInSeconds")
    if isinstance(value, (int, float)):
        return float(value)
    match = re.fullmatch(r"\s*([\d.]+)\s*s\s*", str(node.get("duration", "")))
    return float(match.group(1)) if match else 0.0


def verdict_of(node: dict) -> tuple[str, list[str]]:
    repetitions = [c for c in node.get("children", []) if c.get("nodeType") == "Repetition"]
    if repetitions:
        repetitions.sort(key=lambda r: int(m.group(1)) if (m := REPETITION.search(r.get("name", ""))) else 0)
        last = repetitions[-1].get("result")
        failed_before = [r for r in repetitions[:-1] if r.get("result") == "Failed"]
        if last == "Failed":
            return "failed", messages_under(repetitions[-1], expected=False) or messages_under(node, expected=False)
        if last == "Passed" and failed_before:
            return "flaky", messages_under(failed_before[0])
        result = last
    else:
        result = node.get("result")
    if result == "Failed":
        return "failed", messages_under(node, expected=False)
    if result == "Expected Failure":
        return "quarantined", messages_under(node)
    if result == "Skipped":
        return "skipped", []
    return "passed", []


def cases(report: dict) -> list[Case]:
    found: list[Case] = []

    def walk(node: dict, trail: list[str]) -> None:
        kind, name = node.get("nodeType"), node.get("name", "")
        if kind == "Test Case":
            verdict, messages = verdict_of(node)
            identifier = node.get("nodeIdentifier") or "/".join(trail[-1:] + [name])
            found.append(Case(identifier, name, trail, verdict, messages, seconds_of(node)))
            return
        for child in node.get("children", []):
            walk(child, trail + [name] if kind in GROUPS else trail)

    for root in report.get("testNodes", []):
        walk(root, [])
    return found


def test_identifiers(path: str) -> list[str]:
    """The identifiers of every test case in one `get test-results tests` JSON file."""
    with open(path, encoding="utf-8") as f:
        return [case.identifier for case in cases(json.load(f))]


def escape(text: str, title: bool = False) -> str:
    text = text.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    return text.replace(":", "%3A").replace(",", "%2C") if title else text


def load(paths: list[str]) -> tuple[list[Case], list[str]]:
    found, problems = [], []
    for path in paths:
        try:
            with open(path, encoding="utf-8") as f:
                found.extend(cases(json.load(f)))
        except (OSError, json.JSONDecodeError) as error:
            problems.append(f"{path}: {error}")
    return found, problems


def apply_retries(found: list[Case], retried: list[Case]) -> None:
    """A failed test that passed when run again on its own is flaky; one that failed again stays failed,
    with the messages of both runs. Tests that did not fail first are left as they were."""
    again = {case.selector: case for case in retried}
    for case in found:
        second = again.get(case.selector)
        if case.verdict != "failed" or second is None:
            continue
        if second.verdict == "passed":
            case.verdict = "flaky"
        else:
            case.messages += [m for m in second.messages if m not in case.messages]


def summary(all_cases: list[Case], flaky_budget: int | None) -> str:
    by_verdict = {v: [c for c in all_cases if c.verdict == v]
                  for v in ("failed", "flaky", "quarantined", "skipped", "passed")}
    lines = ["### Tests", "",
             " · ".join(f"{len(cs)} {v}" for v, cs in by_verdict.items() if cs) or "No tests ran.", ""]
    for verdict, heading in (("failed", "Failed"), ("flaky", "Flaky (failed, then passed on retry)"),
                             ("quarantined", "Quarantined (expected failures)")):
        if by_verdict[verdict]:
            lines += [f"#### {heading}", "", "| Test | Message |", "| --- | --- |"]
            for case in by_verdict[verdict]:
                message = (case.messages[0] if case.messages else "no message recorded").replace("|", "\\|")
                lines.append(f"| `{case.title}` | {' '.join(message.split())[:300]} |")
            lines.append("")
    if flaky_budget is not None and by_verdict["flaky"]:
        lines += [f"Flaky budget: {len(by_verdict['flaky'])} of {flaky_budget} allowed.", ""]
    suites: dict[str, list[float]] = {}
    for case in all_cases:
        suites.setdefault(case.suite, []).append(case.seconds)
    if suites:
        lines += ["#### Slowest suites", "", "| Suite | Tests | Seconds |", "| --- | ---: | ---: |"]
        for suite, times in sorted(suites.items(), key=lambda s: -sum(s[1]))[:10]:
            lines.append(f"| `{suite}` | {len(times)} | {sum(times):.0f} |")
        lines.append("")
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("results", nargs="+", help="`xcresulttool get test-results tests` JSON files")
    ap.add_argument("--retries", nargs="*", default=[],
                    help="results of the failed tests run again on their own, one file per shard that retried")
    ap.add_argument("--failed-ids", help="write the failed tests' identifiers here, one per line")
    ap.add_argument("--retry-ids", help="write the failed tests here as -only-testing takes them, one per line")
    ap.add_argument("--flaky-budget", type=int, help="fail when more distinct tests than this were flaky")
    ap.add_argument("--summary", help="append a markdown summary here (e.g. $GITHUB_STEP_SUMMARY)")
    args = ap.parse_args(argv)

    all_cases, problems = load(args.results)
    retried, retry_problems = load(args.retries)
    problems += retry_problems
    apply_retries(all_cases, retried)
    for problem in problems:
        print(f"::error::Cannot read test results: {escape(problem)}")
    for case in all_cases:
        title = escape(case.title, title=True)
        if case.verdict == "failed":
            for message in case.messages or ["no message recorded"]:
                print(f"::error title={title}::{escape(message)}")
        elif case.verdict == "flaky":
            first = case.messages[0] if case.messages else "no message recorded"
            print(f"::warning title=Flaky%3A {title}::Failed, then passed on retry: {escape(first)}")
    if args.failed_ids:
        with open(args.failed_ids, "w", encoding="utf-8") as f:
            f.writelines(f"{case.identifier}\n" for case in all_cases if case.verdict == "failed")
    if args.retry_ids:
        with open(args.retry_ids, "w", encoding="utf-8") as f:
            f.writelines(f"{case.selector}\n" for case in all_cases if case.verdict == "failed")
    if args.summary:
        with open(args.summary, "a", encoding="utf-8") as f:
            f.write(summary(all_cases, args.flaky_budget))

    failed = [c for c in all_cases if c.verdict == "failed"]
    flaky = {c.identifier for c in all_cases if c.verdict == "flaky"}
    counts = {v: sum(c.verdict == v for c in all_cases) for v in ("passed", "failed", "flaky", "quarantined", "skipped")}
    print("tests: " + ", ".join(f"{n} {v}" for v, n in counts.items()))
    verdict = 0
    if problems or not all_cases:
        print("::error::No test results to report: the test run ended before recording any")
        verdict = 1
    if failed:
        verdict = 1
    if args.flaky_budget is not None and len(flaky) > args.flaky_budget:
        print(f"::error::{len(flaky)} tests were flaky in this run, more than the budget of "
              f"{args.flaky_budget}: retries may be hiding a real problem")
        verdict = 1
    return verdict


if __name__ == "__main__":
    sys.exit(main())
