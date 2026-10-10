#!/usr/bin/env python3
"""Propose a split of the UI test classes over the UI shards from the times a run measured.

    python3 scripts/ci/rebalance_shards.py shards/ios-shard-*/tests.json [--summary "$GITHUB_STEP_SUMMARY"] [--write]

Reads each shard's `xcresulttool get test-results tests` JSON, adds up the seconds of every UI test
class, and splits the classes over the UI shards (test_shards.py: the listed shards, then the
complement) by longest class first, each to the shard with the least time so far. It prints the
current split's time per shard next to the proposal's, and the test_shards.json that would give it.
With --write it rewrites test_shards.json (locally, in a pull request of its own). A class the
proposal leaves in the complement needs no entry. Never fails a run: the summary is advice.

Times are the tests' own durations, without the app's install and the simulator's start, so a shard's
job takes a few minutes longer than its sum.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_shards  # noqa: E402
import xcresult_report  # noqa: E402

# Propose a change only when it shortens the slowest UI shard by at least this share.
WORTH = 0.10


def class_seconds(paths: list[str], ui_target: str) -> dict[str, float]:
    found, _ = xcresult_report.load(paths)
    seconds: dict[str, float] = {}
    for case in found:
        if len(case.trail) >= 2 and case.trail[0] == ui_target:
            seconds[case.trail[1]] = seconds.get(case.trail[1], 0.0) + case.seconds
    return seconds


def current(config: dict, seconds: dict[str, float]) -> dict[str, list[str]]:
    listed = {name: shard for shard in test_shards.LISTED for name in config.get(shard, [])}
    split: dict[str, list[str]] = {shard: [] for shard in test_shards.LISTED + (test_shards.COMPLEMENT,)}
    for name in seconds:
        split[listed.get(name, test_shards.COMPLEMENT)].append(name)
    return split


def propose(seconds: dict[str, float]) -> dict[str, list[str]]:
    """Longest class first, each to the least loaded shard; the shard that ends with the most time is
    the complement, so the classes new tests are added to are the ones already measured."""
    shards = test_shards.LISTED + (test_shards.COMPLEMENT,)
    bins: list[list[str]] = [[] for _ in shards]
    totals = [0.0 for _ in shards]
    for name in sorted(seconds, key=lambda n: (-seconds[n], n)):
        index = min(range(len(bins)), key=lambda i: (totals[i], i))
        bins[index].append(name)
        totals[index] += seconds[name]
    order = sorted(range(len(bins)), key=lambda i: totals[i])
    return {shard: sorted(bins[i]) for shard, i in zip(shards, order)}


def load_of(split: dict[str, list[str]], seconds: dict[str, float]) -> dict[str, float]:
    return {shard: sum(seconds.get(n, 0.0) for n in names) for shard, names in split.items()}


def report(config: dict, seconds: dict[str, float]) -> tuple[str, dict | None]:
    """(markdown, the proposed test_shards.json or None when the current split is good enough)."""
    now, proposal = current(config, seconds), propose(seconds)
    now_load, new_load = load_of(now, seconds), load_of(proposal, seconds)
    worth = max(now_load.values(), default=0) * (1 - WORTH) > max(new_load.values(), default=0)
    lines = ["### UI shard balance", "", "| Shard | Now (s) | Proposed (s) | Proposed classes |",
             "| --- | ---: | ---: | --- |"]
    for shard in proposal:
        lines.append(f"| {shard} | {now_load[shard]:.0f} | {new_load[shard]:.0f} | "
                     f"{', '.join(proposal[shard])} |")
    new_config = {"uiTarget": config["uiTarget"], **{shard: proposal[shard] for shard in test_shards.LISTED}}
    if worth:
        lines += ["", "Rebalancing would shorten the slowest UI shard by more than "
                  f"{WORTH:.0%}: `python3 scripts/ci/rebalance_shards.py <tests.json files> --write`, "
                  "in a pull request of its own.", "", "```json", json.dumps(new_config, indent=2), "```"]
    else:
        lines += ["", f"The current split is within {WORTH:.0%} of the proposal's slowest shard; no change needed."]
    return "\n".join(lines) + "\n\n", new_config if worth else None


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("results", nargs="+", help="each shard's tests.json")
    ap.add_argument("--config", default=str(test_shards.CONFIG))
    ap.add_argument("--summary")
    ap.add_argument("--write", action="store_true", help="rewrite the config with the proposal when worth it")
    args = ap.parse_args(argv)
    config = test_shards.load_config(Path(args.config))
    seconds = class_seconds(args.results, config["uiTarget"])
    if not seconds:
        print("no UI test times in these results")
        return 0
    text, new_config = report(config, seconds)
    print(text)
    if args.summary:
        with open(args.summary, "a", encoding="utf-8") as f:
            f.write(text)
    if args.write and new_config:
        with open(args.config, "w", encoding="utf-8") as f:
            f.write(json.dumps(new_config, indent=2) + "\n")
        print(f"wrote {args.config}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
