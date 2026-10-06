#!/usr/bin/env python3
"""Fail a pull request that changes what the privacy policy describes without saying so. Standard library only.

    python3 scripts/ci/privacy_impact.py --base HEAD^1 --body-file pr-body.md           # CI, on the merge commit
    python3 scripts/ci/privacy_impact.py --base "$(git merge-base origin/integration HEAD)" --body-file pr-body.md

The privacy policy on algorythmos.com is a public commitment, and App Review compares it with the
privacy manifest and the App Store privacy label (docs/compliance-roadmap.md). The policy lives in
the website repository, so a change here can make it wrong without touching it. This gate looks at
what a pull request adds or removes and asks for one line in its description when the change is one
the policy describes:

  * the privacy manifest (any PrivacyInfo.xcprivacy);
  * a permission's usage description (project.yml, Info.plist, InfoPlist.strings);
  * the network allow-list in scripts/ci/invariants.py;
  * a new package dependency (a `.package(url:` line in a Package.swift);
  * a networking API in app or package code, outside tests.

The line is `Privacy policy impact: none, because <reason>` or `Privacy policy impact: <link to the
website pull request that updates the policy>`. The placeholder from the template does not count.
Exit 1 when the line is needed and missing.
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

NETWORK = re.compile(r"\b(URLSession|URLRequest|NWConnection|WKWebView)\b|^\s*import\s+(Network|CloudKit)\b")
USAGE_DESCRIPTION = re.compile(r"NS\w+UsageDescription")
ALLOW_LIST = re.compile(r"""^\s*["']network["']\s*:""")
DEPENDENCY = re.compile(r"\.package\(\s*url:")
DECLARATION = re.compile(r"^\s*(?:[-*]\s*)?\**Privacy policy impact:\**\s*(.+?)\s*$", re.I | re.M)
PLACEHOLDER = re.compile(r"^<!--.*-->$|^$", re.S)


def is_test(path: str) -> bool:
    return "/Tests/" in f"/{path}" or path.endswith("Tests.swift")


def reasons(diff: str) -> list[str]:
    """Why a unified diff touches something the privacy policy describes, one line per finding."""
    found: list[str] = []
    path = ""
    for line in diff.splitlines():
        if line.startswith("+++ ") or line.startswith("--- "):
            name = line[4:].strip()
            if name != "/dev/null":
                path = name[2:] if name[:2] in ("a/", "b/") else name
            continue
        if not line or line[0] not in "+-" or not path:
            continue
        text = line[1:]
        if path.endswith("PrivacyInfo.xcprivacy"):
            found.append(f"{path}: the privacy manifest changed")
        elif path.endswith(("project.yml", "Info.plist", "InfoPlist.strings")) and USAGE_DESCRIPTION.search(text):
            found.append(f"{path}: a permission's usage description changed")
        elif path == "scripts/ci/invariants.py" and ALLOW_LIST.search(text):
            found.append(f"{path}: the network allow-list changed")
        elif path.endswith("Package.swift") and line[0] == "+" and DEPENDENCY.search(text):
            found.append(f"{path}: a package dependency was added")
        elif path.endswith(".swift") and not is_test(path) and line[0] == "+" and NETWORK.search(text):
            found.append(f"{path}: a networking API was added")
    return list(dict.fromkeys(found))


def declaration(body: str) -> str | None:
    """The pull request's privacy impact statement, or None when it is missing or still the placeholder."""
    for match in DECLARATION.finditer(body or ""):
        value = match.group(1).strip()
        if not PLACEHOLDER.match(value):
            return value
    return None


def problems(diff: str, body: str) -> list[str]:
    found = reasons(diff)
    if not found or declaration(body):
        return []
    return found


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--base", required=True, help="the commit the pull request is compared with")
    parser.add_argument("--body-file", required=True, type=Path, help="a file holding the pull request description")
    args = parser.parse_args()
    diff = subprocess.run(
        ["git", "diff", "--unified=0", "--no-color", args.base, "HEAD"],
        cwd=ROOT, capture_output=True, text=True, check=True,
    ).stdout
    body = args.body_file.read_text(encoding="utf-8") if args.body_file.exists() else ""
    found = problems(diff, body)
    for item in found:
        print(f"::error::{item}")
    if found:
        print(
            "This pull request changes something the privacy policy describes. Add a line to its description:\n"
            "  Privacy policy impact: none, because <reason>\n"
            "or\n"
            "  Privacy policy impact: <link to the website pull request that updates the policy>\n"
            "Editing the description runs this check again.")
        return 1
    stated = declaration(body)
    print(f"privacy impact: {'stated: ' + stated if stated else 'nothing the policy describes changed'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
