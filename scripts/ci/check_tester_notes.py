#!/usr/bin/env python3
"""Check the notes testers see in TestFlight. Standard library only.

    python3 scripts/ci/check_tester_notes.py

Xcode Cloud reads `TestFlight/WhatToTest.<locale>.txt` at the commit it builds
(docs/changelog-strategy.md, docs/process/runbooks/staging-build.md). Nothing else looked at these
files, and three things could go wrong unseen:

  * a locale with no file arrives empty: the app record's primary language had none, so its testers
    saw no notes until a file was added on 2026-10-10;
  * a file past the field's limit would be cut off or dropped, and the French one was near it;
  * the locales can drift apart, one telling testers about something another does not.

So every required locale has a file with text in it, the primary language's file is the same as the
one it copies, each file is within the limit in characters and in bytes, and all files have the same
blocks with the same number of lines in each. Exit 1 on any problem.
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FOLDER = ROOT / "TestFlight"
PREFIX = "WhatToTest."
SUFFIX = ".txt"
# The locales testers use, and the app record's primary language.
REQUIRED = ("en-AU", "en-US", "fr-FR")
# The primary language has no wording of its own: it is the file beside it, byte for byte.
COPIES = {"en-AU": "en-US"}
# Assumption: the field holds 4,000. Its unit is not documented where Xcode Cloud describes these
# files, so characters and bytes are both held under it. Validated only as far as this: notes of 3,251
# characters and 3,363 bytes arrived whole on the Staging build of 2026-10-10.
LIMIT = 4000


def shape(text: str) -> list[int]:
    """The number of lines in each block of the notes; blocks are separated by a blank line."""
    return [len(block.splitlines()) for block in text.strip().split("\n\n") if block.strip()]


def problems(folder: Path) -> list[str]:
    """What is wrong with the tester notes in a folder, one line per finding."""
    found: list[str] = []
    files = {path.name[len(PREFIX) : -len(SUFFIX)]: path for path in sorted(folder.glob(f"{PREFIX}*{SUFFIX}"))}
    for locale in REQUIRED:
        if locale not in files:
            found.append(f"{PREFIX}{locale}{SUFFIX} is missing: testers in that locale would see no notes")
    texts: dict[str, bytes] = {locale: path.read_bytes() for locale, path in files.items()}
    for locale, data in texts.items():
        name = files[locale].name
        try:
            text = data.decode("utf-8")
        except UnicodeDecodeError:
            found.append(f"{name} is not UTF-8")
            continue
        if not text.strip():
            found.append(f"{name} is empty")
        if len(text) > LIMIT or len(data) > LIMIT:
            found.append(f"{name} is {len(text)} characters and {len(data)} bytes; the limit is {LIMIT} of each")
    for locale, original in COPIES.items():
        if locale in texts and original in texts and texts[locale] != texts[original]:
            found.append(f"{PREFIX}{locale}{SUFFIX} differs from {PREFIX}{original}{SUFFIX}; it is kept as a copy of it")
    shapes = {
        locale: shape(data.decode("utf-8", errors="replace")) for locale, data in texts.items() if data.strip()
    }
    if len({tuple(lines) for lines in shapes.values()}) > 1:
        listed = "; ".join(f"{locale}: {lines}" for locale, lines in sorted(shapes.items()))
        found.append(f"the files do not have the same blocks and lines (lines in each block: {listed})")
    return found


def main() -> int:
    found = problems(FOLDER)
    for item in found:
        print(f"::error::{item}")
    print(f"tester notes check: {len(found)} error(s)")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
