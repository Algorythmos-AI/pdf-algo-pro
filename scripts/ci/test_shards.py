#!/usr/bin/env python3
"""How the ci.yml `ios-tests` job splits the PDFAlgoPro test plan into shards. Standard library only.

    python3 scripts/ci/test_shards.py matrix [--only-testing IDS]   # the job matrix, as JSON
    python3 scripts/ci/test_shards.py names                         # unit,ui-1,ui-2
    python3 scripts/ci/test_shards.py args SHARD [--only-testing IDS]  # xcodebuild arguments, one per line
    python3 scripts/ci/test_shards.py retry-args SHARD FAILED  # the failed tests' re-run, or nothing
    python3 scripts/ci/test_shards.py verdict SHARD --xcodebuild-exit N --reporter-exit M

Every shard runs the same build (`ios-build`), each on its own runner and simulator:

  * unit: every test target except the UI tests (package tests, the app's unit and snapshot tests);
  * ui-1: the UI test classes listed under "ui-1" in test_shards.json;
  * ui-2: every other UI test class, so a new UI test class lands here without any change;
  * focused: on a manual run with `only_testing`, only the identifiers given (Target, Target/Class
    or Target/Class/method, comma-separated), instead of the three shards above.

UI shards run their failed tests once more, on their own, in a second xcodebuild run (retry-args),
and only when at most MAX_RETRIED failed: more than that fails the flaky budget even if all pass, so
the shard ends sooner without them. xcodebuild's own -retry-tests-on-failure is not used: on run
37924545633 it ran all 41 tests of ui-2 again for 3 failures, and the shard ran out of time. The unit
and focused shards never retry. To rebalance, move classes between the shards by editing
test_shards.json; the tests in test_test_shards.py check that every listed class exists.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

CONFIG = Path(__file__).resolve().with_name("test_shards.json")
SHARDS = ("unit", "ui-1", "ui-2")
FOCUSED = "focused"
# Target, Target/Class or Target/Class/method, optionally with "()": nothing else reaches xcodebuild.
IDENTIFIER = re.compile(r"^[A-Za-z0-9_]+(/[A-Za-z0-9_]+){0,2}(\(\))?$")
MAX_FOCUSED = 20
# The flaky budget ios-report enforces (xcresult_report.py --flaky-budget).
MAX_RETRIED = 3


def load_config(path: Path = CONFIG) -> dict:
    with open(path, encoding="utf-8") as f:
        config = json.load(f)
    classes = config.get("ui-1")
    if not isinstance(config.get("uiTarget"), str) or not isinstance(classes, list) or not classes:
        raise SystemExit(f"{path}: needs a uiTarget and a non-empty ui-1 list")
    if len(set(classes)) != len(classes):
        raise SystemExit(f"{path}: a class is listed twice in ui-1")
    for name in classes:
        if not isinstance(name, str) or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name):
            raise SystemExit(f"{path}: {name!r} is not a class name")
    return config


def focused_ids(only_testing: str) -> list[str]:
    """The identifiers of a focused run, validated; raises ValueError on anything unexpected."""
    ids = [part.strip() for part in only_testing.split(",")]
    if not any(ids):
        raise ValueError("only_testing is empty")
    if len(ids) > MAX_FOCUSED:
        raise ValueError(f"only_testing names {len(ids)} identifiers; at most {MAX_FOCUSED}")
    for value in ids:
        if not IDENTIFIER.fullmatch(value):
            raise ValueError(f"{value!r} is not Target, Target/Class or Target/Class/method")
    return ids


def is_focused(only_testing: str | None) -> bool:
    return bool(only_testing and only_testing.strip())


def matrix(only_testing: str | None, record: bool = False) -> dict:
    """The shards to run: one focused shard, the unit shard alone when recording snapshot references
    (they belong to the unit shard's app tests, and the UI shards would only delay publishing them),
    or every shard."""
    if record:
        if is_focused(only_testing):
            raise ValueError("record_snapshots and only_testing cannot be combined")
        return {"shard": ["unit"]}
    if is_focused(only_testing):
        focused_ids(only_testing or "")
        return {"shard": [FOCUSED]}
    return {"shard": list(SHARDS)}


def retries(shard: str) -> bool:
    return shard in ("ui-1", "ui-2")


def args_for(shard: str, only_testing: str | None = None, config: dict | None = None) -> list[str]:
    config = config or load_config()
    target, ui1 = config["uiTarget"], config["ui-1"]
    if shard == "unit":
        selectors = [f"-skip-testing:{target}"]
    elif shard == "ui-1":
        selectors = [f"-only-testing:{target}/{name}" for name in ui1]
    elif shard == "ui-2":
        selectors = [f"-only-testing:{target}"] + [f"-skip-testing:{target}/{name}" for name in ui1]
    elif shard == FOCUSED:
        selectors = [f"-only-testing:{value}" for value in focused_ids(only_testing or "")]
    else:
        raise ValueError(f"unknown shard {shard!r}; expected one of {', '.join(SHARDS + (FOCUSED,))}")
    return selectors


def retry_args(shard: str, failed: list[str]) -> tuple[list[str], str]:
    """(xcodebuild selectors for running the failed tests again, why not when empty)."""
    failed = [line.strip() for line in failed if line.strip()]
    if not retries(shard):
        return [], f"{shard} does not retry"
    if not failed:
        return [], "no test failed"
    if len(failed) > MAX_RETRIED:
        return [], (f"{len(failed)} tests failed, more than the {MAX_RETRIED} the flaky budget allows, "
                    "so they are not run again")
    for value in failed:
        if not IDENTIFIER.fullmatch(value) or value.count("/") != 2:
            return [], f"{value!r} is not Target/Class/method, so the failed tests are not run again"
    return [f"-only-testing:{value}" for value in failed], f"running {len(failed)} failed test(s) again"


def verdict(shard: str, xcodebuild_exit: int, reporter_exit: int | None) -> tuple[bool, str]:
    """Whether a shard passes, from xcodebuild's exit code and xcresult_report.py's.

    reporter_exit is None when there was no result bundle to report on.
    """
    if xcodebuild_exit == 0:
        return True, "xcodebuild passed"
    if reporter_exit is None:
        return False, f"xcodebuild failed ({xcodebuild_exit}) and left no test results: a crash or a build problem"
    if not retries(shard):
        return False, f"xcodebuild failed ({xcodebuild_exit}); this shard does not retry, so its verdict stands"
    if reporter_exit != 0:
        return False, f"xcodebuild failed ({xcodebuild_exit}) and a test failed again when re-run, or no test ran"
    return True, (f"xcodebuild exited {xcodebuild_exit}, but every failed test passed when run again: "
                  "they are reported as flaky")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="command", required=True)
    m = sub.add_parser("matrix")
    m.add_argument("--only-testing", default="")
    m.add_argument("--record", default="", help="'true' on a run that records snapshot references")
    sub.add_parser("names")
    a = sub.add_parser("args")
    a.add_argument("shard")
    a.add_argument("--only-testing", default="")
    r = sub.add_parser("retry-args")
    r.add_argument("shard")
    r.add_argument("failed", help="the failed tests as -only-testing takes them, one per line (may be missing)")
    v = sub.add_parser("verdict")
    v.add_argument("shard")
    v.add_argument("--xcodebuild-exit", type=int, required=True)
    v.add_argument("--reporter-exit", default="", help="empty when there was no result bundle")
    args = ap.parse_args(argv)

    try:
        if args.command == "matrix":
            print(json.dumps(matrix(args.only_testing, args.record == "true"), separators=(",", ":")))
        elif args.command == "names":
            print(",".join(SHARDS))
        elif args.command == "args":
            print("\n".join(args_for(args.shard, args.only_testing)))
        elif args.command == "retry-args":
            try:
                with open(args.failed, encoding="utf-8") as f:
                    failed = f.readlines()
            except OSError:
                failed = []
            selectors, reason = retry_args(args.shard, failed)
            print(f"{args.shard}: {reason}", file=sys.stderr)
            if selectors:
                print("\n".join(selectors))
        else:
            reporter = int(args.reporter_exit) if args.reporter_exit.strip() else None
            ok, reason = verdict(args.shard, args.xcodebuild_exit, reporter)
            print(f"{args.shard}: {reason}" if ok else f"::error::{args.shard}: {reason}")
            return 0 if ok else 1
    except ValueError as error:
        print(f"::error::{error}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
