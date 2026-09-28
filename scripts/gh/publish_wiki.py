#!/usr/bin/env python3
"""Mirror docs/ to the GitHub Wiki tab. docs/ stays the source of truth (adapted from trading-lab).

    python3 scripts/gh/publish_wiki.py --out build/wiki   # render locally, nothing pushed
    python3 scripts/gh/publish_wiki.py --push             # render, commit and push to the wiki

The curated pages in docs/wiki/ keep their own names (Home.md → Home, Product-Vision.md →
Product-Vision) and head the sidebar (docs/wiki/_Sidebar.md when present). Every other
docs/**/*.md becomes a reference page with a flattened, unique name (README.md → Docs-Index,
process/runbooks/ios-hotfix.md → Process-Runbooks-iOS-Hotfix). Links between docs are rewritten to wiki
pages; links to other repository files point at the exact commit on GitHub. Each page opens with
a banner saying it is a mirror, and a sidebar lists every page. The wiki is fully replaced on each
publish, so edits made in the Wiki tab are overwritten.

The wiki's git repository only exists after its first page is saved once in the GitHub UI.
Stdlib only. Exit codes: 0 success, 1 render error, 2 wiki repository unavailable.
"""
from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DOCS = ROOT / "docs"
REPO_URL = "https://github.com/Algorythmos-AI/pdf-algo-pro"
WIKI_GIT = f"{REPO_URL}.wiki.git"
ACRONYMS = {"adr": "ADR", "ai": "AI", "api": "API", "ios": "iOS", "ocr": "OCR", "prd": "PRD", "ux": "UX", "github": "GitHub"}
WIKI_DIR = "wiki"
LINK = re.compile(r"(!?\[[^\]]*\])\(([^)\s]+)\)")


def git(*args: str, cwd: Path | None = None) -> str:
    r = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"git {' '.join(args)} failed: {r.stderr.strip()}")
    return r.stdout.strip()


def page_name(rel: Path) -> str:
    parts = list(rel.with_suffix("").parts)
    if parts[0] == WIKI_DIR and len(parts) == 2:
        return parts[1]
    if parts == ["README"]:
        return "Docs-Index"
    if parts[-1] == "README":
        parts[-1] = "index"
    words = [ACRONYMS.get(w.lower(), w.capitalize()) for seg in parts for w in re.split(r"[-_]", seg) if w]
    return "-".join(words)


def title_of(text: str, fallback: str) -> str:
    m = re.search(r"^#\s+(.+)$", text, flags=re.M)
    return m.group(1).strip() if m else fallback


def rewrite_links(text: str, src: Path, sha: str) -> str:
    def repl(m: re.Match) -> str:
        label, target = m.group(1), m.group(2)
        if re.match(r"^(https?:|mailto:|#)", target):
            return m.group(0)
        path, _, anchor = target.partition("#")
        resolved = (src.parent / path).resolve()
        try:
            rel_docs = resolved.relative_to(DOCS)
        except ValueError:
            rel_docs = None
        if rel_docs is not None and resolved.suffix == ".md" and resolved.is_file():
            return f"{label}({page_name(rel_docs)}{'#' + anchor if anchor else ''})"
        try:
            rel_repo = resolved.relative_to(ROOT).as_posix()
        except ValueError:
            return m.group(0)
        if not resolved.exists():
            raise ValueError(f"{src.relative_to(ROOT)}: broken link {target!r}")
        kind = "tree" if resolved.is_dir() else "blob"
        return f"{label}({REPO_URL}/{kind}/{sha}/{rel_repo}{'#' + anchor if anchor else ''})"
    return LINK.sub(repl, text)


def render(out: Path) -> int:
    sha = git("rev-parse", "HEAD", cwd=ROOT)
    short = sha[:7]
    sources = sorted(p for p in DOCS.rglob("*.md") if not (p.parent == DOCS / WIKI_DIR and p.name.startswith("_")))
    pages: dict[str, tuple[Path, str]] = {}
    for src in sources:
        rel = src.relative_to(DOCS)
        name = page_name(rel)
        if name in pages:
            raise ValueError(f"page name collision: {rel} and {pages[name][0]} → {name}")
        text = src.read_text(encoding="utf-8")
        banner = (f"> Mirror of [`docs/{rel.as_posix()}`]({REPO_URL}/blob/{sha}/docs/{rel.as_posix()}) "
                  f"at [`{short}`]({REPO_URL}/commit/{sha}). Edit it through a pull request; "
                  f"changes made in this wiki are overwritten on the next publish.\n\n")
        pages[name] = (rel, banner + rewrite_links(text, src, sha))

    out.mkdir(parents=True, exist_ok=True)
    for old in out.glob("*.md"):
        old.unlink()
    for name, (_, body) in pages.items():
        (out / f"{name}.md").write_text(body, encoding="utf-8")

    def entry(rel: Path) -> str:
        return f"- [{title_of((DOCS / rel).read_text(encoding='utf-8'), rel.stem)}]({page_name(rel)})"

    curated = DOCS / WIKI_DIR / "_Sidebar.md"
    wiki_pages = sorted((r for r, _ in pages.values() if r.parts[0] == WIKI_DIR), key=lambda r: (r.stem != "Home", r.stem))
    sidebar = [curated.read_text(encoding="utf-8").rstrip()] if curated.exists() else [entry(r) for r in wiki_pages]
    groups: dict[str, list[Path]] = {}
    for rel, _ in pages.values():
        if rel.parts[0] != WIKI_DIR:
            groups.setdefault(rel.parts[0] if len(rel.parts) > 1 else "Documents", []).append(rel)
    sidebar += ["", "---", "", "**Reference library**"]
    for group in sorted(groups, key=lambda g: (g != "Documents", g)):
        rels = sorted(groups[group], key=lambda r: (r.name != "README.md", r.as_posix()))
        sidebar += ["", f"**{ACRONYMS.get(group, group.capitalize())}**", *[entry(r) for r in rels]]
    (out / "_Sidebar.md").write_text("\n".join(sidebar) + "\n", encoding="utf-8")
    (out / "_Footer.md").write_text(
        f"Mirror of [`docs/`]({REPO_URL}/tree/{sha}/docs) at `{short}` · source of truth is the repository\n",
        encoding="utf-8")
    print(f"rendered {len(pages)} pages from docs/ @ {short} → {out}")
    return 0


def push() -> int:
    # The mirror links to docs at the current commit, so it must be committed and on GitHub.
    if git("status", "--porcelain", "--", "docs", cwd=ROOT):
        raise RuntimeError("docs/ has uncommitted changes; publish only committed docs")
    if not git("branch", "-r", "--contains", "HEAD", cwd=ROOT):
        raise RuntimeError("HEAD is not on the remote yet; push it (or publish from main) first")
    with tempfile.TemporaryDirectory() as tmp:
        wiki = Path(tmp) / "wiki"
        r = subprocess.run(["git", "clone", "-q", WIKI_GIT, str(wiki)], capture_output=True, text=True)
        if r.returncode != 0:
            print("error: wiki repository not available. Create the first wiki page once in the GitHub UI "
                  f"({REPO_URL}/wiki), then re-run.\n" + r.stderr.strip(), file=sys.stderr)
            return 2
        render(wiki)
        git("add", "-A", cwd=wiki)
        if not git("status", "--porcelain", cwd=wiki):
            print("wiki already up to date")
            return 0
        short = git("rev-parse", "--short", "HEAD", cwd=ROOT)
        git("commit", "-q", "-m", f"Mirror docs/ at {short}", cwd=wiki)
        git("push", "-q", "origin", "HEAD", cwd=wiki)
        print(f"published wiki from docs/ @ {short}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--out", type=Path, help="render into this directory only")
    mode.add_argument("--push", action="store_true", help="render and push to the wiki")
    a = ap.parse_args()
    try:
        if a.out:
            out = a.out if a.out.is_absolute() else ROOT / a.out
            if out.resolve() == ROOT or DOCS in out.resolve().parents or out.resolve() == DOCS:
                raise ValueError("--out must not be the repository root or inside docs/")
            return render(out)
        return push()
    except (ValueError, RuntimeError) as e:
        print(f"error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
