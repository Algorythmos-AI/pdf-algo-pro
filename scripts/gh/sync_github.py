#!/usr/bin/env python3
"""Sync labels and milestones from .github/labels.yml and .github/milestones.yml to GitHub.

    uv run --with pyyaml==6.0.2 python scripts/gh/sync_github.py labels            # dry run
    uv run --with pyyaml==6.0.2 python scripts/gh/sync_github.py labels --apply
    uv run --with pyyaml==6.0.2 python scripts/gh/sync_github.py milestones --apply

Labels: the organisation's shared labels (Algorythmos-AI/.github labels.json) are applied first,
then this repository's product labels. A product label that redefines an org label is an error.
Nothing is ever deleted: labels and milestones that exist on GitHub but not in the files are
reported, not removed. Requires `gh` authenticated with write access to the repository.
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
REPO = "Algorythmos-AI/pdf-algo-pro"
ORG_LABELS = ("Algorythmos-AI/.github", "labels.json")


def gh(*args: str, payload: dict | None = None) -> str:
    cmd = ["gh", "api", *args]
    if payload is not None:
        cmd += ["--input", "-"]
    r = subprocess.run(cmd, input=json.dumps(payload) if payload is not None else None,
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(f"gh api {' '.join(args)} failed: {r.stderr.strip()}")
    return r.stdout


def desired_labels() -> list[dict]:
    org = json.loads(gh("-H", "Accept: application/vnd.github.raw", f"repos/{ORG_LABELS[0]}/contents/{ORG_LABELS[1]}"))
    product = yaml.safe_load((ROOT / ".github/labels.yml").read_text())["labels"]
    org_names = {label["name"] for label in org}
    clash = org_names & {label["name"] for label in product}
    if clash:
        raise SystemExit(f"product labels redefine org labels: {sorted(clash)}")
    return [*org, *product]


def sync_labels(apply: bool) -> None:
    live = {label["name"]: label for label in json.loads(gh(f"repos/{REPO}/labels?per_page=100", "--paginate"))}
    for want in desired_labels():
        body = {"name": want["name"], "color": str(want["color"]).lstrip("#"), "description": want.get("description", "")}
        have = live.get(want["name"])
        if have is None:
            print(f"create  {want['name']}")
            if apply:
                gh(f"repos/{REPO}/labels", "-X", "POST", payload=body)
        elif (have["color"].lower(), have.get("description") or "") != (body["color"].lower(), body["description"]):
            print(f"update  {want['name']}")
            if apply:
                gh(f"repos/{REPO}/labels/{want['name']}", "-X", "PATCH", payload=body)
    extra = set(live) - {label["name"] for label in desired_labels()}
    for name in sorted(extra):
        print(f"keep    {name} (on GitHub, not in the files; not deleted)")


def sync_milestones(apply: bool) -> None:
    live = {m["title"]: m for m in json.loads(gh(f"repos/{REPO}/milestones?state=all&per_page=100", "--paginate"))}
    for want in yaml.safe_load((ROOT / ".github/milestones.yml").read_text())["milestones"]:
        have = live.get(want["title"])
        if have is None:
            print(f"create  {want['title']}")
            if apply:
                gh(f"repos/{REPO}/milestones", "-X", "POST", payload={"title": want["title"], "description": want["description"]})
        elif (have.get("description") or "") != want["description"]:
            print(f"update  {want['title']}")
            if apply:
                gh(f"repos/{REPO}/milestones/{have['number']}", "-X", "PATCH", payload={"description": want["description"]})


def main() -> None:
    if len(sys.argv) < 2 or sys.argv[1] not in {"labels", "milestones"}:
        raise SystemExit(__doc__)
    apply = "--apply" in sys.argv
    print(f"{sys.argv[1]} for {REPO}{'' if apply else ' (dry run: nothing changed)'}")
    (sync_labels if sys.argv[1] == "labels" else sync_milestones)(apply)


if __name__ == "__main__":
    main()
