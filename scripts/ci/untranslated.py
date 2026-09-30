#!/usr/bin/env python3
"""List the strings an Xcode localisation export has not translated. Standard library only.

    xcodebuild -exportLocalizations -project PDFAlgoPro.xcodeproj -scheme PDFAlgoPro \\
      -localizationPath build/loc -exportLanguage fr
    python3 scripts/ci/untranslated.py "build/loc/fr.xcloc/Localized Contents/fr.xliff"

The export builds the app and its packages and lists every user-facing string, including ones added
in code since the catalogs were last updated. A string counts as translated when its target is
present and not empty. Two kinds are not counted:
  * the app's names in Info.plist, which stay untranslated so each configuration keeps its own
    (assumption A14, checked by invariants.py);
  * strings of a package without a resource bundle (PDFEngine), which resolve from the app's
    catalog, when that catalog translates them.
Exits 1 when any string is untranslated, listing each with its catalog.
"""
from __future__ import annotations

import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

NS = {"x": "urn:oasis:names:tc:xliff:document:1.2"}
ROOT = Path(__file__).resolve().parents[2]
APP_CATALOG = ROOT / "App" / "PDFAlgoPro" / "Resources" / "Localizable.xcstrings"
APP_NAMES = {"CFBundleDisplayName", "CFBundleName"}


def app_translations(language: str, catalog: Path = APP_CATALOG) -> set[str]:
    """The keys the app's catalog translates into a language."""
    if not catalog.exists():
        return set()
    strings = json.loads(catalog.read_text(encoding="utf-8")).get("strings", {})
    return {key for key, entry in strings.items() if language in entry.get("localizations", {})}


def untranslated(xliff: Path, app_catalog: Path = APP_CATALOG) -> list[tuple[str, str]]:
    """(catalog, source) for every unit without a translation."""
    missing = []
    for file in ET.parse(xliff).getroot().findall("x:file", NS):
        original = file.get("original", "?")
        from_app = app_translations(file.get("target-language", ""), app_catalog) if original.endswith(".strings") else set()
        for unit in file.iter(f"{{{NS['x']}}}trans-unit"):
            target = unit.find("x:target", NS)
            if target is not None and (target.text or "").strip():
                continue
            if "InfoPlist" in original and unit.get("id") in APP_NAMES:
                continue
            source = unit.findtext("x:source", "", NS)
            if source in from_app:
                continue
            missing.append((original, source))
    return missing


def main(argv: list[str] | None = None) -> int:
    args = argv if argv is not None else sys.argv[1:]
    if len(args) != 1:
        print(__doc__, file=sys.stderr)
        return 2
    missing = untranslated(Path(args[0]))
    for catalog, source in missing:
        print(f"{catalog}: {source!r}")
    print(f"untranslated: {len(missing)}")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
