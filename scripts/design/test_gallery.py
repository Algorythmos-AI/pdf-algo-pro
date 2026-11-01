"""Tests for the snapshot gallery (scripts/design/gallery.py)."""
from __future__ import annotations

import importlib.util
import re
import sys
from pathlib import Path

SPEC = importlib.util.spec_from_file_location("gallery", Path(__file__).with_name("gallery.py"))
assert SPEC and SPEC.loader
gallery = importlib.util.module_from_spec(SPEC)
# Registered first: a dataclass looks its module up while the module is still loading.
sys.modules[SPEC.name] = gallery
SPEC.loader.exec_module(gallery)


def make_references(root: Path, names: list[str], suite: str = "SnapshotTests") -> Path:
    folder = root / "__Snapshots__"
    (folder / suite).mkdir(parents=True)
    for name in names:
        (folder / suite / name).write_bytes(b"\x89PNG")
    return folder


def test_names_become_sentence_case_words():
    assert gallery.words("paywallWithoutTrial") == "Paywall without trial"
    assert gallery.words("home") == "Home"
    assert gallery.words("largeText") == "Large text"


def test_references_are_read_by_test_and_variant(tmp_path):
    folder = make_references(tmp_path, ["home.light.png", "home.dark.png", "notes.txt"])
    found, unnamed = gallery.references(folder)
    assert sorted((r.suite, r.test, r.variant) for r in found) == [
        ("SnapshotTests", "home", "dark"),
        ("SnapshotTests", "home", "light"),
    ]
    assert unnamed == ["SnapshotTests/notes.txt"]


def test_a_missing_folder_gives_an_empty_gallery(tmp_path):
    found, unnamed = gallery.references(tmp_path / "absent")
    assert (found, unnamed) == ([], [])
    assert "No snapshot references are recorded yet." in gallery.render([], tmp_path / "docs" / "gallery.md")


def test_one_table_per_screen_and_known_variants_in_order(tmp_path):
    folder = make_references(
        tmp_path, ["home.largeText.png", "home.dark.png", "home.light.png", "home.rightToLeft.png", "about.light.png"]
    )
    found, _ = gallery.references(folder)
    text = gallery.render(found, tmp_path / "docs" / "design" / "gallery.md")
    headings = re.findall(r"^## (.+)$", text, re.M)
    assert headings == ["About", "Home"]
    home = text.split("## Home", 1)[1]
    assert "| Light | Dark | Accessibility XL text | Right to left |" in home
    assert home.index("home.light.png") < home.index("home.dark.png") < home.index("home.largeText.png")


def test_image_links_are_relative_to_the_gallery_and_resolve(tmp_path):
    folder = make_references(tmp_path, ["scan.light.png"])
    output = tmp_path / "docs" / "design" / "gallery.md"
    found, _ = gallery.references(folder)
    links = re.findall(r'<img src="([^"]+)"', gallery.render(found, output))
    assert links == ["../../__Snapshots__/SnapshotTests/scan.light.png"]
    assert all((output.parent / link).resolve().is_file() for link in links)


def test_the_gallery_has_one_h1_and_one_owner_line(tmp_path):
    folder = make_references(tmp_path, ["home.light.png"])
    found, _ = gallery.references(folder)
    text = gallery.render(found, tmp_path / "gallery.md")
    assert len(re.findall(r"^# ", text, re.M)) == 1
    assert len([line for line in text.splitlines() if line.startswith("Owner:")]) == 1


def test_the_committed_gallery_matches_the_references():
    found, _ = gallery.references()
    assert gallery.OUTPUT.read_text(encoding="utf-8") == gallery.render(found), (
        "docs/design/gallery.md is stale; run python3 scripts/design/gallery.py and commit it"
    )
