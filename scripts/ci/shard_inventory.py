#!/usr/bin/env python3
"""Check that the `ios-tests` shards together ran the whole test plan, each test once. Standard library only.

    python3 scripts/ci/shard_inventory.py inventory.json shards/ios-shard-*/tests.json \
        [--expect unit,ui-1,ui-2] [--summary "$GITHUB_STEP_SUMMARY"]

inventory.json is what `ios-build` listed with `xcodebuild test-without-building -enumerate-tests
-test-enumeration-format json`: every test the plan enables (and those it disables). Each tests.json is
one shard's `xcresulttool get test-results tests` output; the shard's name is its folder's, without
the `ios-shard-` prefix. Fails (exit 1) when:

  * an expected shard has no results, or ran no test (a selector that matches nothing);
  * a test ran in two shards (the shards overlap, so the selectors are wrong);
  * a test the plan enables ran in no shard (the shards leave a gap).

A test that ran but is not in the inventory at all also fails, unless the inventory is empty: when
enumeration failed in `ios-build`, the last two checks are skipped with a warning, because
enumeration is new in the pipeline and must not by itself block a pull request.

Tests are compared by test bundle and identifier, with a trailing "()" ignored, because enumeration
and the result bundle write a method's identifier differently.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import xcresult_report  # noqa: E402

PREFIX = "ios-shard-"
SHOWN = 20


def normalise(bundle: str, identifier: str) -> str:
    if bundle and identifier.startswith(bundle + "/"):
        identifier = identifier[len(bundle) + 1:]
    if identifier.endswith("()"):
        identifier = identifier[:-2]
    return f"{bundle}/{identifier}" if bundle else identifier


def inventory(path: str) -> tuple[set[str], set[str]]:
    """(enabled, disabled) tests from an enumeration file; both empty when it is missing or unreadable."""
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError):
        return set(), set()
    enabled: set[str] = set()
    disabled: set[str] = set()
    loose: set[str] = set()

    def identifiers(items) -> set[str]:
        found = set()
        for item in items if isinstance(items, list) else []:
            value = item.get("identifier") if isinstance(item, dict) else item
            if isinstance(value, str) and value:
                bundle, _, rest = value.partition("/")
                found.add(normalise(bundle, rest) if rest else value)
        return found

    def walk(node) -> None:
        if isinstance(node, dict):
            for key, value in node.items():
                if key == "enabledTests":
                    enabled.update(identifiers(value))
                elif key == "disabledTests":
                    disabled.update(identifiers(value))
                elif key == "identifier" and isinstance(value, str):
                    loose.update(identifiers([value]))
                else:
                    walk(value)
        elif isinstance(node, list):
            for item in node:
                walk(item)

    walk(data)
    if not enabled and not disabled:
        enabled = loose or tree_tests(data)  # formats without the enabled/disabled split
    return enabled, disabled


def tree_tests(data) -> set[str]:
    """Tests from the tree `-enumerate-tests -test-enumeration-format json` writes with Xcode 26:
    {"values": [{"children": [{"kind": "target", "name": ..., "children": [{"kind": "class", ...,
    "children": [{"kind": "test", "name": "ask()"}]}]}]}]} (run 37920045109). A test's identifier is
    its target, then every suite or class it is nested in, then its name."""
    found: set[str] = set()

    def walk(node, trail: list[str]) -> None:
        if isinstance(node, list):
            for item in node:
                walk(item, trail)
            return
        if not isinstance(node, dict):
            return
        kind, name = node.get("kind"), node.get("name")
        if kind == "test" and isinstance(name, str) and trail:
            found.add(normalise(trail[0], "/".join(trail[1:] + [name])))
            return
        inner = trail + [name] if isinstance(name, str) and (kind == "target" or trail) else trail
        for key in ("children", "values"):
            walk(node.get(key), inner)

    walk(data, [])
    return found


def shard_name(path: str) -> str:
    folder = Path(path).parent.name
    return folder[len(PREFIX):] if folder.startswith(PREFIX) else folder


def shard_tests(path: str) -> list[xcresult_report.Case]:
    with open(path, encoding="utf-8") as f:
        return xcresult_report.cases(json.load(f))


def identity(case: xcresult_report.Case) -> str:
    return normalise(case.trail[0] if case.trail else "", case.identifier)


def listed(names: set[str] | list[str]) -> str:
    names = sorted(names)
    more = f" and {len(names) - SHOWN} more" if len(names) > SHOWN else ""
    return ", ".join(names[:SHOWN]) + more


def check(inventory_path: str, shard_paths: list[str], expect: list[str],
          warn_only: bool = False) -> tuple[list[str], list[str], str]:
    """(errors, warnings, markdown summary). With warn_only, tests missing from the shards or from the
    inventory are warnings, not errors."""
    errors: list[str] = []
    warnings: list[str] = []
    ran: dict[str, set[str]] = {}
    rows = ["### Shards", "", "| Shard | Tests | Seconds in tests | Failed | Flaky |", "| --- | ---: | ---: | ---: | ---: |"]
    for path in sorted(shard_paths):
        name = shard_name(path)
        try:
            tests = shard_tests(path)
        except (OSError, json.JSONDecodeError) as error:
            errors.append(f"shard {name}: cannot read its test results ({error})")
            continue
        ran[name] = {identity(c) for c in tests}
        rows.append(f"| {name} | {len(tests)} | {sum(c.seconds for c in tests):.0f} | "
                    f"{sum(c.verdict == 'failed' for c in tests)} | {sum(c.verdict == 'flaky' for c in tests)} |")
        if not tests:
            errors.append(f"shard {name} ran no test: its selectors match nothing, or it crashed before any result")
    for name in expect:
        if name not in ran and not any(e.startswith(f"shard {name}:") for e in errors):
            errors.append(f"shard {name} has no test results: its job failed before uploading them")

    seen: dict[str, str] = {}
    twice: dict[str, list[str]] = {}
    for name in sorted(ran):
        for test in ran[name]:
            if test in seen:
                twice.setdefault(test, [seen[test]]).append(name)
            else:
                seen[test] = name
    if twice:
        errors.append(f"{len(twice)} test(s) ran in more than one shard, so the shards overlap: "
                      + listed({f"{t} ({' and '.join(s)})" for t, s in twice.items()}))

    enabled, disabled = inventory(inventory_path)
    union = set(seen)
    if not enabled:
        warnings.append("the test inventory from ios-build is empty (enumeration failed or was not run), "
                        "so whether the shards ran every test is not checked")
    else:
        missing = enabled - union
        unexpected = union - enabled - disabled
        differences = warnings if warn_only else errors
        if missing:
            differences.append(f"{len(missing)} test(s) the plan enables ran in no shard: {listed(missing)}")
        if unexpected:
            differences.append(f"{len(unexpected)} test(s) ran but are not in the inventory: {listed(unexpected)}")
        rows += ["", f"Inventory: {len(enabled)} enabled tests; {len(union & enabled)} ran across the shards."]
    return errors, warnings, "\n".join(rows) + "\n\n"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("inventory")
    ap.add_argument("shards", nargs="*")
    ap.add_argument("--expect", default="", help="comma-separated shard names that must all have results")
    ap.add_argument("--summary")
    ap.add_argument("--warn-only", action="store_true",
                    help="report tests missing from the shards or the inventory as warnings")
    args = ap.parse_args(argv)
    expect = [n for n in args.expect.split(",") if n]
    errors, warnings, summary = check(args.inventory, args.shards, expect, args.warn_only)
    print(summary)
    if args.summary:
        with open(args.summary, "a", encoding="utf-8") as f:
            f.write(summary)
    for warning in warnings:
        print(f"::warning::{warning}")
    for error in errors:
        print(f"::error::{error}")
    if not errors:
        print("shard inventory: ok")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
