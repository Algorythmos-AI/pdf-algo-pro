#!/usr/bin/env python3
"""Sync labels, milestones and the planned backlog to GitHub.

    uv run --with pyyaml==6.0.2 python scripts/gh/sync_github.py labels            # dry run
    uv run --with pyyaml==6.0.2 python scripts/gh/sync_github.py labels --apply
    uv run --with pyyaml==6.0.2 python scripts/gh/sync_github.py milestones --apply
    uv run --with pyyaml==6.0.2 python scripts/gh/sync_github.py backlog --apply
    uv run --with pyyaml==6.0.2 python scripts/gh/sync_github.py backlog --project 3 --apply

Sources: .github/labels.yml, .github/milestones.yml and docs/planning/backlog.yaml.
Backlog items are matched to issues by a hidden marker (<!-- backlog-id: F-001 -->) in the issue
body, so re-running never duplicates. Existing issues get their title, milestone and planned labels
updated; the body is only written on creation, so discussion edits are never overwritten.

Backlog labels: the planned labels (item labels, `priority:*`, `size:*`, and `enhancement` for epics
and tasks) are added when missing, and a stale `priority:*` or `size:*` label is replaced. Every other
label on the issue (triage labels such as `status:*`, `blocked` or `flaky`) is kept.

`--project N` also adds each backlog issue to organisation project N (only the ones not already on
it), so issues appear on the board before the project's auto-add workflow is switched on.

Labels: the organisation's shared labels (Algorythmos-AI/.github labels.json) are applied first,
then this repository's product labels. A product label that redefines an org label is an error.
Nothing is ever deleted: labels and milestones that exist on GitHub but not in the files are
reported, not removed. With --apply, each write is followed by a one-second pause to stay clear of
GitHub's secondary rate limits. Requires `gh` authenticated with write access to the repository.
"""
from __future__ import annotations

import json
import subprocess
import sys
import time
from pathlib import Path
from urllib.parse import quote

import yaml

ROOT = Path(__file__).resolve().parents[2]
OWNER = "Algorythmos-AI"
REPO = f"{OWNER}/pdf-algo-pro"
ORG_LABELS = (f"{OWNER}/.github", "labels.json")
MANAGED_PREFIXES = ("priority:", "size:")
WRITE_PAUSE_SECONDS = 1.0


def run(cmd: list[str], stdin: str | None = None) -> str:
    r = subprocess.run(cmd, input=stdin, capture_output=True, text=True)
    if r.returncode != 0:
        raise SystemExit(f"{' '.join(cmd)} failed: {r.stderr.strip()}")
    return r.stdout


def gh(*args: str, payload: dict | None = None) -> str:
    cmd = ["gh", "api", *args]
    if payload is not None:
        cmd += ["--input", "-"]
    return run(cmd, json.dumps(payload) if payload is not None else None)


def gh_list(path: str) -> list[dict]:
    """Every item of a paginated list endpoint. `--slurp` wraps the pages in one JSON array; plain
    `--paginate` would print the page arrays back to back, which is not valid JSON after 100 items."""
    pages = json.loads(gh(path, "--paginate", "--slurp"))
    return [item for page in pages for item in page]


def write(*args: str, payload: dict | None = None) -> str:
    out = gh(*args, payload=payload)
    time.sleep(WRITE_PAUSE_SECONDS)
    return out


def desired_labels() -> list[dict]:
    org = json.loads(gh("-H", "Accept: application/vnd.github.raw", f"repos/{ORG_LABELS[0]}/contents/{ORG_LABELS[1]}"))
    product = yaml.safe_load((ROOT / ".github/labels.yml").read_text())["labels"]
    org_names = {label["name"] for label in org}
    clash = org_names & {label["name"] for label in product}
    if clash:
        raise SystemExit(f"product labels redefine org labels: {sorted(clash)}")
    return [*org, *product]


def sync_labels(apply: bool) -> int:
    changes = 0
    live = {label["name"]: label for label in gh_list(f"repos/{REPO}/labels?per_page=100")}
    wanted = desired_labels()
    for want in wanted:
        body = {"name": want["name"], "color": str(want["color"]).lstrip("#"), "description": want.get("description", "")}
        have = live.get(want["name"])
        if have is None:
            print(f"create  {want['name']}")
            changes += 1
            if apply:
                write(f"repos/{REPO}/labels", "-X", "POST", payload=body)
        elif (have["color"].lower(), have.get("description") or "") != (body["color"].lower(), body["description"]):
            print(f"update  {want['name']}")
            changes += 1
            if apply:
                write(f"repos/{REPO}/labels/{quote(want['name'], safe='')}", "-X", "PATCH", payload=body)
    for name in sorted(set(live) - {label["name"] for label in wanted}):
        print(f"keep    {name} (on GitHub, not in the files; not deleted)")
    return changes


def sync_milestones(apply: bool) -> int:
    changes = 0
    live = {m["title"]: m for m in gh_list(f"repos/{REPO}/milestones?state=all&per_page=100")}
    for want in yaml.safe_load((ROOT / ".github/milestones.yml").read_text())["milestones"]:
        have = live.get(want["title"])
        if have is None:
            print(f"create  {want['title']}")
            changes += 1
            if apply:
                write(f"repos/{REPO}/milestones", "-X", "POST", payload={"title": want["title"], "description": want["description"]})
        elif (have.get("description") or "") != want["description"]:
            print(f"update  {want['title']}")
            changes += 1
            if apply:
                write(f"repos/{REPO}/milestones/{have['number']}", "-X", "PATCH", payload={"description": want["description"]})
    return changes


def issue_body(item: dict) -> str:
    lines = [f"<!-- backlog-id: {item['id']} -->", f"**Backlog item {item['id']}** ({item['type']})", ""]
    lines.append(f"Pillars: {', '.join(item['pillars'])}")
    if item.get("refs"):
        lines.append(f"References: {', '.join(item['refs'])}")
    lines += ["", "### Acceptance", ""] + [f"- [ ] {a}" for a in item["acceptance"]]
    lines += ["", "Planned in `docs/planning/backlog.yaml`; change the plan there, not here."]
    return "\n".join(lines)


def planned_labels(item: dict) -> set[str]:
    labels = {*item.get("labels", []), f"priority:{item['priority']}", f"size:{item['size']}"}
    if item["type"] in {"epic", "task"}:
        labels.add("enhancement")
    return labels


def merged_labels(current: set[str], planned: set[str]) -> set[str]:
    """Planned labels win; a stale priority or size label is dropped; every other label is kept."""
    stale = {name for name in current if name.startswith(MANAGED_PREFIXES) and name not in planned}
    return (current - stale) | planned


def backlog_issues() -> dict[str, dict]:
    by_id = {}
    for issue in gh_list(f"repos/{REPO}/issues?state=all&per_page=100"):
        body = issue.get("body") or ""
        if "pull_request" not in issue and "<!-- backlog-id: " in body:
            by_id[body.split("<!-- backlog-id: ", 1)[1].split(" -->", 1)[0]] = issue
    return by_id


def project_issue_urls(project: int) -> set[str]:
    listing = json.loads(run(["gh", "project", "item-list", str(project), "--owner", OWNER,
                              "--format", "json", "--limit", "1000"]))
    return {(item.get("content") or {}).get("url", "") for item in listing.get("items", [])}


def sync_backlog(apply: bool, project: int | None = None) -> int:
    changes = 0
    items = yaml.safe_load((ROOT / "docs/planning/backlog.yaml").read_text())["items"]
    ids = [item["id"] for item in items]
    if len(ids) != len(set(ids)):
        raise SystemExit("duplicate backlog ids")
    milestones = {m["title"]: m["number"] for m in gh_list(f"repos/{REPO}/milestones?state=all&per_page=100")}
    by_id = backlog_issues()
    urls: dict[str, str] = {}
    for item in items:
        if item["milestone"] not in milestones:
            raise SystemExit(f"{item['id']}: milestone {item['milestone']!r} missing; sync milestones first")
        planned = planned_labels(item)
        have = by_id.get(item["id"])
        if have is None:
            print(f"create  {item['id']}  {item['title']}")
            changes += 1
            if apply:
                created = json.loads(write(f"repos/{REPO}/issues", "-X", "POST", payload={
                    "title": item["title"], "labels": sorted(planned),
                    "milestone": milestones[item["milestone"]], "body": issue_body(item)}))
                urls[item["id"]] = created["html_url"]
            continue
        urls[item["id"]] = have["html_url"]
        current = {label["name"] for label in have["labels"]}
        patch: dict = {}
        if have["title"] != item["title"]:
            patch["title"] = item["title"]
        if (have.get("milestone") or {}).get("number") != milestones[item["milestone"]]:
            patch["milestone"] = milestones[item["milestone"]]
        labels = merged_labels(current, planned)
        if labels != current:
            patch["labels"] = sorted(labels)
        if patch:
            print(f"update  {item['id']}  {item['title']}  ({', '.join(sorted(patch))})")
            changes += 1
            if apply:
                write(f"repos/{REPO}/issues/{have['number']}", "-X", "PATCH", payload=patch)
    if project is not None:
        on_board = project_issue_urls(project)
        for item_id, url in urls.items():
            if url not in on_board:
                print(f"project {item_id}  add to project {project}")
                changes += 1
                if apply:
                    run(["gh", "project", "item-add", str(project), "--owner", OWNER, "--url", url])
                    time.sleep(WRITE_PAUSE_SECONDS)
        missing = [item["id"] for item in items if item["id"] not in urls]
        for item_id in missing:
            print(f"project {item_id}  add to project {project} (after the issue is created)")
            changes += 1
    return changes


def main(argv: list[str]) -> None:
    commands = {"labels": sync_labels, "milestones": sync_milestones, "backlog": sync_backlog}
    if len(argv) < 2 or argv[1] not in commands:
        raise SystemExit(__doc__)
    apply = "--apply" in argv
    project = None
    if "--project" in argv:
        if argv[1] != "backlog":
            raise SystemExit("--project only applies to the backlog command")
        try:
            project = int(argv[argv.index("--project") + 1])
        except (IndexError, ValueError):
            raise SystemExit("--project needs a project number, e.g. --project 3")
    print(f"{argv[1]} for {REPO}{'' if apply else ' (dry run: nothing changed)'}")
    changes = commands[argv[1]](apply, project) if project is not None else commands[argv[1]](apply)
    print(f"{changes} change(s){' applied' if apply else ' planned'}")


if __name__ == "__main__":
    main(sys.argv)
