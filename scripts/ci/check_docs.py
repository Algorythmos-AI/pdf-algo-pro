#!/usr/bin/env python3
"""Documentation gate for the ci.yml `docs` job. Standard library only.

Blocking (exit 1):
  * relative links in every tracked Markdown file resolve to a file or folder in the repository;
  * each Markdown file has exactly one H1, as its first heading, and heading levels never skip;
  * when docs/README.md exists, every document under docs/ (top level, product/, process/,
    planning/) is linked from it. docs/adr/ is indexed by docs/adr/README.md and docs/wiki/
    by docs/wiki/_Sidebar.md, so both are checked against their own index instead.

Warnings only (never fail the build, so nothing breaks just because time passed):
  * docs/working-memory.md not updated for more than 30 days;
  * possible unsourced numbers: a percentage or currency amount in a paragraph with no link,
    citation or "Assumption:" label.

Usage: python3 scripts/ci/check_docs.py [--strict-warnings]
"""
from __future__ import annotations

import datetime as dt
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LINK = re.compile(r"(?<!!)\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
HEADING = re.compile(r"^(#{1,6})\s+\S")
FENCE = re.compile(r"^\s*(```|~~~)")
NUMBER_CLAIM = re.compile(r"(\b\d+(?:[.,]\d+)?\s?%|[$€£]\s?\d|\bA\$\s?\d|\bUS\$\s?\d)")
INDEXED_DIRS = ("", "product", "process", "planning")


def tracked_markdown() -> list[Path]:
    out = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "*.md"],
        cwd=ROOT, capture_output=True, text=True, check=True,
    ).stdout.split()
    return sorted(ROOT / p for p in out)


def strip_code(lines: list[str]) -> list[str]:
    """Blank out fenced code blocks and inline code so they are not parsed as Markdown."""
    kept, fenced = [], False
    for line in lines:
        if FENCE.match(line):
            fenced = not fenced
            kept.append("")
            continue
        kept.append("" if fenced else re.sub(r"`[^`]*`", "", line))
    return kept


def check_links(path: Path, lines: list[str], errors: list[str]) -> None:
    for no, line in enumerate(lines, 1):
        for target in LINK.findall(line):
            if re.match(r"^(https?:|mailto:|#)", target):
                continue
            file_part = target.split("#", 1)[0]
            if not file_part:
                continue
            resolved = (path.parent / file_part).resolve()
            if not resolved.exists():
                errors.append(f"{path.relative_to(ROOT)}:{no}: broken link -> {target}")


def check_headings(path: Path, lines: list[str], errors: list[str]) -> None:
    levels = [(no, len(m.group(1))) for no, line in enumerate(lines, 1) if (m := HEADING.match(line))]
    rel = path.relative_to(ROOT)
    if rel.parts[0] == ".github" or rel.name.startswith("_"):
        return  # GitHub templates and wiki sidebar/footer need no H1
    content = [line.strip() for line in lines if line.strip()]
    if content and all(line.startswith("@") for line in content):
        return  # import-only files such as CLAUDE.md (`@AGENTS.md`)
    h1 = [no for no, lvl in levels if lvl == 1]
    if len(h1) != 1 or not levels or levels[0][1] != 1:
        errors.append(f"{rel}: needs exactly one H1, as the first heading (found {len(h1)})")
    for (_, prev), (no, lvl) in zip(levels, levels[1:]):
        if lvl > prev + 1:
            errors.append(f"{rel}:{no}: heading level jumps from H{prev} to H{lvl}")


def linked_targets(index: Path) -> set[Path]:
    text = "\n".join(strip_code(index.read_text(encoding="utf-8").splitlines()))
    return {(index.parent / t.split("#", 1)[0]).resolve() for t in LINK.findall(text) if not re.match(r"^(https?:|mailto:|#)", t)}


def check_index(errors: list[str]) -> None:
    docs = ROOT / "docs"
    readme = docs / "README.md"
    if readme.exists():
        linked = linked_targets(readme)
        for sub in INDEXED_DIRS:
            folder = docs / sub if sub else docs
            if not folder.is_dir():
                continue
            pattern = "*.md" if not sub else "**/*"
            for doc in sorted(folder.glob(pattern)):
                if doc.is_file() and doc != readme and doc.suffix in {".md", ".yaml", ".yml"}:
                    if doc.resolve() not in linked:
                        errors.append(f"docs/README.md does not link {doc.relative_to(ROOT)}")
    for index_name, sub in (("README.md", "adr"), ("_Sidebar.md", "wiki")):
        folder, index = docs / sub, docs / sub / index_name
        if folder.is_dir() and index.exists():
            linked = linked_targets(index)
            for doc in sorted(folder.glob("*.md")):
                if doc != index and not doc.name.startswith("_") and doc.resolve() not in linked:
                    wiki_ok = sub == "wiki" and f"({doc.stem})" in index.read_text(encoding="utf-8")
                    if not wiki_ok:
                        errors.append(f"{index.relative_to(ROOT)} does not link {doc.relative_to(ROOT)}")


def warn_freshness(warnings: list[str]) -> None:
    memory = ROOT / "docs" / "working-memory.md"
    if not memory.exists():
        return
    m = re.search(r"Last updated:\s*(\d{4}-\d{2}-\d{2})", memory.read_text(encoding="utf-8"))
    if not m:
        warnings.append("docs/working-memory.md has no 'Last updated: YYYY-MM-DD' line")
        return
    age = (dt.date.today() - dt.date.fromisoformat(m.group(1))).days
    if age > 30:
        warnings.append(f"docs/working-memory.md last updated {age} days ago; refresh it with the next change")


def warn_evidence(path: Path, lines: list[str], raw: list[str], warnings: list[str]) -> None:
    """Numbers are read from prose (code stripped); labels and links may sit in inline code."""
    paragraph: list[tuple[int, str]] = []

    def flush() -> None:
        text = " ".join(line for _, line in paragraph)
        source = " ".join(raw[no - 1] for no, _ in paragraph)
        if NUMBER_CLAIM.search(text) and not re.search(r"\]\(|Assumption:|Source:|\[\^|ADR-\d{4}", source):
            warnings.append(f"{path.relative_to(ROOT)}:{paragraph[0][0]}: number without a source or 'Assumption:' label")
        paragraph.clear()

    for no, line in enumerate(lines, 1):
        if line.strip():
            paragraph.append((no, line))
        elif paragraph:
            flush()
    if paragraph:
        flush()


def main() -> int:
    strict = "--strict-warnings" in sys.argv
    errors: list[str] = []
    warnings: list[str] = []
    for path in tracked_markdown():
        raw = path.read_text(encoding="utf-8").splitlines()
        lines = strip_code(raw)
        check_links(path, lines, errors)
        check_headings(path, lines, errors)
        if path.relative_to(ROOT).parts[0] == "docs":
            warn_evidence(path, lines, raw, warnings)
    check_index(errors)
    warn_freshness(warnings)

    for w in warnings:
        print(f"::warning::{w}")
    for e in errors:
        print(f"::error::{e}")
    print(f"docs check: {len(errors)} error(s), {len(warnings)} warning(s)")
    return 1 if errors or (strict and warnings) else 0


if __name__ == "__main__":
    sys.exit(main())
