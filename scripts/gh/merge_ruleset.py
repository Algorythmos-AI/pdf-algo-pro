#!/usr/bin/env python3
"""merge_ruleset.py LIVE.json COMMITTED.json — the ruleset to PUT: the live one, overlaid with what
the committed file states, keeping every key the file does not mention.

GitHub grows rulesets over time (pull_request gained required_reviewers, dismissal_restriction,
require_extra_approval_for_unattributed_changes, allowed_merge_methods; required_status_checks
gained do_not_enforce_on_create). PUTting the committed file as-is resets such keys to their
defaults — silently weakening protection (require_extra_approval… is true on both trunks). So:
top-level fields from the file win; each rule type in the file replaces the live rule's parameters
key by key (lists, such as required_status_checks, are taken whole from the file); live-only rules
are kept. Prints the JSON to stdout; `--diff` prints only what would change.
"""
import json, sys

WRITABLE = ("name", "target", "enforcement", "conditions", "bypass_actors", "rules")


def merge(live: dict, committed: dict) -> dict:
    out = {k: live[k] for k in WRITABLE if k in live}
    for k in WRITABLE:
        if k in committed and k != "rules":
            out[k] = committed[k]
    rules = {r["type"]: dict(r) for r in live.get("rules", [])}
    for r in committed.get("rules", []):
        cur = rules.get(r["type"], {"type": r["type"]})
        if "parameters" in r:
            cur["parameters"] = {**cur.get("parameters", {}), **r["parameters"]}
        rules[r["type"]] = cur
    out["rules"] = list(rules.values())
    return out


def diff(live: dict, merged: dict) -> list[str]:
    changes = []
    for k in WRITABLE:
        if k != "rules" and live.get(k) != merged.get(k):
            changes.append(f"{k}: {json.dumps(live.get(k))} -> {json.dumps(merged.get(k))}")
    L = {r["type"]: r.get("parameters") for r in live.get("rules", [])}
    for r in merged["rules"]:
        before, after = L.get(r["type"]), r.get("parameters")
        if before != after:
            keys = sorted(set(before or {}) | set(after or {}))
            for key in keys:
                if (before or {}).get(key) != (after or {}).get(key):
                    changes.append(f"{r['type']}.{key}: {json.dumps((before or {}).get(key))} -> {json.dumps((after or {}).get(key))}")
    return changes


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    live, committed = (json.load(open(p, encoding="utf-8")) for p in args[:2])
    merged = merge(live, committed)
    if "--diff" in sys.argv:
        print("\n".join(diff(live, merged)) or "no change")
    else:
        print(json.dumps(merged))
