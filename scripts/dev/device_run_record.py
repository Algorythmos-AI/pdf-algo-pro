#!/usr/bin/env python3
"""The device test run's helpers for scripts/dev/device_tests.sh. Standard library only.

    xcrun devicectl list devices --json-output devices.json
    python3 scripts/dev/device_run_record.py device devices.json --id "$DEVICE_ID"
    python3 scripts/dev/device_run_record.py record --tests tests.json [--retries retry-tests.json] \
        --commit abc1234 --xcode "27.0 (27A266a)" --device "iPhone 17 Pro" --ios 27.0.1 \
        --flags "Device" --bundle .build/device-tests/<stamp>/Device.xcresult --ci-ios success
    python3 scripts/dev/device_run_record.py checklist

`device` finds the iPhone named by --id (its UDID, its CoreDevice identifier or its name) in
devicectl's JSON and says whether a test run can use it. It prints udid=, model= and ios= lines for the
shell on success, and every problem with its fix on stderr; it exits 1 when the run cannot start. A phone
reached over Wi-Fi ("available (paired)" rather than "connected") is a warning, not a failure: the run
works, but can drop.

`record` appends a row to the runs table in docs/process/device-test-run.md: the date, the commit, Xcode,
the device's model and iOS, the plan and flags, the counts of passed, failed and flaky tests (a failed
test that passed when run again is flaky, as in CI), where the result bundle is, CI's `ios` conclusion
on the commit, the manual checklist (pending until done) and the issues filed. Never a device's UDID,
name or anything else that identifies the phone or its owner: the repository is public (AGENTS.md rule 4).

`checklist` prints the manual checklist from that document, so it has one source.

`commit SHA` reads `git status --porcelain --untracked-files=normal` on stdin and prints SHA, or
SHA-dirty when what is built differs from the commit, so a row never claims a clean commit it did not
test.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DOC = ROOT / "docs" / "process" / "device-test-run.md"
RUNS_HEADING = "## Runs"
CHECKLIST_HEADING = "## Manual checklist"
COLUMNS = ("Date", "Commit", "Xcode", "Device", "iOS", "Plan and flags", "Passed / failed / flaky",
           "Result bundle", "CI `ios`", "Manual checklist", "Issues")

sys.path.insert(0, str(ROOT / "scripts" / "ci"))
import xcresult_report  # noqa: E402


# --- device ---------------------------------------------------------------------------------------

def _get(node: dict, *path: str):
    for key in path:
        if not isinstance(node, dict):
            return None
        node = node.get(key)
    return node


def describe(device: dict) -> dict:
    """What a run needs to know about one device in devicectl's JSON (`properties`, falling back to the
    fields devicectl has deprecated)."""
    developer_mode = _get(device, "properties", "state", "developerModeStatus")
    if isinstance(developer_mode, dict):
        developer_mode = next(iter(developer_mode), None)
    if developer_mode is None:
        developer_mode = _get(device, "deviceProperties", "developerModeStatus")
    return {
        "identifier": device.get("identifier"),
        "udid": _get(device, "properties", "hardware", "udid") or _get(device, "hardwareProperties", "udid"),
        "name": _get(device, "properties", "state", "name") or _get(device, "deviceProperties", "name"),
        "model": (_get(device, "properties", "hardware", "marketingName")
                  or _get(device, "hardwareProperties", "marketingName") or "unknown model"),
        "platform": _get(device, "properties", "hardware", "platform") or _get(device, "hardwareProperties", "platform"),
        "reality": _get(device, "properties", "hardware", "reality") or _get(device, "hardwareProperties", "reality"),
        "ios": (_get(device, "properties", "software", "osVersionNumber", "stringValue")
                or _get(device, "deviceProperties", "osVersionNumber") or "unknown"),
        "pairing": _get(device, "properties", "connection", "pairingState") or _get(device, "connectionProperties", "pairingState"),
        "state": (_get(device, "properties", "connection", "state")
                  or _get(device, "connectionProperties", "tunnelState") or "unknown"),
        "transport": (_get(device, "properties", "connection", "transportType")
                      or _get(device, "connectionProperties", "transportType")),
        "developer_mode": developer_mode,
    }


def state_label(device: dict) -> str:
    """The state as `xcrun devicectl list devices` shows it in its table."""
    if device["state"] in ("connected", "unavailable"):
        return device["state"]
    return "available (paired)" if device["pairing"] == "paired" else device["state"]


def check_device(listing: dict, wanted: str) -> tuple[dict | None, list[str], list[str]]:
    """(the device, problems that stop the run, warnings) for the device `wanted` names."""
    devices = [describe(d) for d in _get(listing, "result", "devices") or []]
    found = [d for d in devices if wanted and wanted in (d["udid"], d["identifier"], d["name"])]
    if not found:
        phones = [f"{d['model']} ({state_label(d)})" for d in devices if d["platform"] == "iOS"]
        return None, [
            "The device named by --device or DEVICE_ID is not one Xcode knows. Connect the iPhone with a "
            "cable, unlock it and tap Trust, then take its Identifier from `xcrun devicectl list devices`. "
            "iOS devices Xcode knows now: " + (", ".join(phones) or "none")], []
    device = found[0]
    problems, warnings = [], []
    if device["platform"] != "iOS" or device["reality"] not in (None, "physical"):
        problems.append(f"The device is a {device['model']} ({device['platform']}), not an iPhone: name the iPhone.")
    if device["developer_mode"] != "enabled":
        problems.append("Developer Mode is off on the phone: Settings > Privacy & Security > Developer Mode, "
                        "turn it on, restart the phone and confirm after it starts.")
    if device["pairing"] != "paired":
        problems.append("The phone is not paired with this Mac: connect the cable, unlock the phone and tap "
                        "Trust This Computer.")
    elif device["state"] == "unavailable":
        problems.append("The phone is paired but unavailable: connect the cable and unlock it (or put it on "
                        "the Mac's Wi-Fi network), then run again.")
    elif device["state"] != "connected":
        warnings.append("The phone shows as available (paired), not connected: it is reached over Wi-Fi or "
                        "is locked. The run connects to it and works, but can drop; connect the cable and "
                        "unlock it for a full run.")
    elif device["transport"] and device["transport"] != "wired":
        warnings.append("The phone is connected over Wi-Fi: the run works but can drop; connect the cable for "
                        "a full run.")
    return device, problems, warnings


# --- commit ---------------------------------------------------------------------------------------

# What a build of the app and its tests reads: an untracked file here is built too (XcodeGen takes every
# source in these folders), so it changes what was tested even though git does not track it.
BUILD_INPUTS = ("App/", "Packages/", "Config/", "project.yml")


def commit_label(sha: str, porcelain: list[str]) -> str:
    """The commit as the record names it: `sha`, or `sha-dirty` when the tree differs from it.

    `porcelain` is `git status --porcelain --untracked-files=normal`: any change to a tracked file makes
    it dirty, and so does an untracked file or folder among BUILD_INPUTS or ending in .xctestplan.
    Untracked files elsewhere (notes, results) are not built, and ignored ones are not listed at all.
    """
    for line in porcelain:
        line = line.rstrip("\n")
        if len(line) < 4:
            continue
        status, path = line[:2], line[3:].strip('"')
        if status != "??":
            return f"{sha}-dirty"
        if path.startswith(BUILD_INPUTS) or path.endswith(".xctestplan"):
            return f"{sha}-dirty"
    return sha


# --- record ---------------------------------------------------------------------------------------

def counts(tests: Path | None, retries: Path | None) -> str:
    if tests is None or not tests.exists():
        return "no results"
    found, problems = xcresult_report.load([str(tests)])
    if problems or not found:
        return "no results"
    if retries is not None and retries.exists():
        retried, _ = xcresult_report.load([str(retries)])
        xcresult_report.apply_retries(found, retried)
    by = {v: sum(c.verdict == v for c in found) for v in ("passed", "failed", "flaky")}
    return f"{by['passed']} / {by['failed']} / {by['flaky']}"


def cell(value: str) -> str:
    return " ".join(str(value).split()).replace("|", "\\|") or "—"


def append_row(doc: Path, row: list[str]) -> None:
    """Adds `row` as the last line of the table under RUNS_HEADING."""
    lines = doc.read_text(encoding="utf-8").splitlines()
    try:
        start = lines.index(RUNS_HEADING)
    except ValueError:
        raise SystemExit(f"{doc} has no '{RUNS_HEADING}' section")
    header = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("|")), None)
    if header is None or lines[header] != "| " + " | ".join(COLUMNS) + " |":
        raise SystemExit(f"{doc}: the table under '{RUNS_HEADING}' does not have the columns {', '.join(COLUMNS)}")
    end = header
    while end + 1 < len(lines) and lines[end + 1].startswith("|"):
        end += 1
    lines.insert(end + 1, "| " + " | ".join(cell(v) for v in row) + " |")
    doc.write_text("\n".join(lines) + "\n", encoding="utf-8")


def public_path(path: str) -> str:
    """The result bundle's path without the home folder (and so the account name) in it."""
    resolved = Path(path).expanduser().resolve()
    for base, shown in ((ROOT, ""), (Path.home(), "~/")):
        try:
            return shown + resolved.relative_to(base).as_posix()
        except ValueError:
            continue
    return resolved.as_posix()


def checklist(doc: Path) -> str:
    lines = doc.read_text(encoding="utf-8").splitlines()
    try:
        start = lines.index(CHECKLIST_HEADING)
    except ValueError:
        raise SystemExit(f"{doc} has no '{CHECKLIST_HEADING}' section")
    end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("## ")), len(lines))
    return "\n".join(lines[start:end]).strip() + "\n"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="command", required=True)
    d = sub.add_parser("device", help="check the device a run will use")
    d.add_argument("listing", help="`xcrun devicectl list devices --json-output` file")
    d.add_argument("--id", required=True, help="UDID, CoreDevice identifier or name")
    r = sub.add_parser("record", help="append a row to the runs table")
    r.add_argument("--doc", type=Path, default=DOC)
    r.add_argument("--tests", type=Path, help="`xcresulttool get test-results tests` JSON of the run")
    r.add_argument("--retries", type=Path, help="the same for the failed tests' second run")
    r.add_argument("--date", default=dt.date.today().isoformat())
    for name in ("commit", "xcode", "device", "ios", "flags", "bundle"):
        r.add_argument(f"--{name}", required=True)
    r.add_argument("--ci-ios", default="unknown", help="the `ios` check's conclusion on the commit")
    r.add_argument("--checklist", default="pending")
    r.add_argument("--issues", default="none yet")
    c = sub.add_parser("checklist", help="print the manual checklist")
    c.add_argument("--doc", type=Path, default=DOC)
    k = sub.add_parser("commit", help="the commit as recorded, from `git status --porcelain` on stdin")
    k.add_argument("sha")
    args = ap.parse_args(argv)

    if args.command == "commit":
        if not re.fullmatch(r"[0-9a-f]{7,40}", args.sha):
            raise SystemExit(f"{args.sha!r} is not a commit hash")
        print(commit_label(args.sha, sys.stdin.readlines()))
        return 0

    if args.command == "device":
        try:
            listing = json.loads(Path(args.listing).read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            print(f"Cannot read devicectl's list of devices: {error}", file=sys.stderr)
            return 1
        device, problems, warnings = check_device(listing, args.id)
        for warning in warnings:
            print(f"warning: {warning}", file=sys.stderr)
        for problem in problems:
            print(f"error: {problem}", file=sys.stderr)
        if problems or device is None:
            return 1
        print(f"udid={device['udid']}\nmodel={device['model']}\nios={device['ios']}")
        return 0
    if args.command == "record":
        if not re.fullmatch(r"[0-9a-f]{7,40}(-dirty)?", args.commit):
            raise SystemExit(f"--commit {args.commit!r} is not a commit hash")
        row = [args.date, args.commit, args.xcode, args.device, args.ios, args.flags,
               counts(args.tests, args.retries), f"`{public_path(args.bundle)}`", args.ci_ios,
               args.checklist, args.issues]
        append_row(args.doc, row)
        print(f"Added the run to {args.doc.relative_to(ROOT) if args.doc.is_relative_to(ROOT) else args.doc}: "
              f"{row[6]} (passed / failed / flaky). Commit the row in a docs: pull request once the manual "
              "checklist is done.")
        return 0
    print(checklist(args.doc), end="")
    return 0


if __name__ == "__main__":
    sys.exit(main())
