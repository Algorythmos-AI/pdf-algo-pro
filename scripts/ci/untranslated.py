#!/usr/bin/env python3
"""List the strings the app has not translated. Standard library only.

    python3 scripts/ci/untranslated.py                # CI: every String Catalog in the repository
    xcodebuild -exportLocalizations -project PDFAlgoPro.xcodeproj -scheme PDFAlgoPro \\
      -localizationPath build/loc -exportLanguage fr
    python3 scripts/ci/untranslated.py "build/loc/fr.xcloc/Localized Contents/fr.xliff"

With no argument it reads every String Catalog (`*.xcstrings`) under App/ and Packages/, and a string
counts as translated into each language in LANGUAGES when every one of its string units there,
plurals and substitutions included, has a value and the state "translated". Not counted: a string
marked "Don't translate", and a stale one, which Xcode found no longer in the code. This needs no
build, so it runs on every pull request (the `docs` job). It sees a string once its catalog has it,
which Xcode writes when it builds.

With an export it reads the XLIFF instead. The export builds the app and its packages and lists
every user-facing string, including ones added in code since the catalogs were last updated. A
string counts as translated when its target is present and not empty. Two kinds are not counted:
  * the app's names in Info.plist, which stay untranslated so each configuration keeps its own
    (assumption A14, checked by invariants.py);
  * strings of a package without a resource bundle, which resolve from the app's catalog, when that
    catalog translates them.

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
# The languages the app is translated into besides English: CFBundleLocalizations in project.yml.
LANGUAGES = ("fr",)
# Where the catalogs are, and the build output under them that is not source.
CATALOG_FOLDERS = ("App", "Packages")
NOT_SOURCE = {".build", "build", "DerivedData"}


def app_translations(language: str, catalog: Path = APP_CATALOG) -> set[str]:
    """The keys the app's catalog translates into a language."""
    if not catalog.exists():
        return set()
    strings = json.loads(catalog.read_text(encoding="utf-8")).get("strings", {})
    return {key for key, entry in strings.items() if language in entry.get("localizations", {})}


def untranslated(xliff: Path, app_catalog: Path = APP_CATALOG) -> list[tuple[str, str]]:
    """(catalog, source) for every unit of an export without a translation."""
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


def catalogs(root: Path = ROOT) -> list[Path]:
    """Every String Catalog in the source, in a stable order."""
    found = []
    for folder in CATALOG_FOLDERS:
        for path in sorted((root / folder).rglob("*.xcstrings")):
            if not NOT_SOURCE.intersection(path.relative_to(root).parts):
                found.append(path)
    return found


def _string_units(node: object) -> list[dict]:
    """Every string unit in a localisation: its own, and those of its variations and substitutions."""
    units = []
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "stringUnit" and isinstance(value, dict):
                units.append(value)
            elif key == "stringSet" and isinstance(value, dict):
                # A Siri phrase and its spoken variants: one unit each, in AppShortcuts.xcstrings.
                state = value.get("state")
                units += [{"state": state, "value": phrase} for phrase in value.get("values") or [""]]
            else:
                units += _string_units(value)
    elif isinstance(node, list):
        for value in node:
            units += _string_units(value)
    return units


def is_translated(localization: object) -> bool:
    """Whether a localisation has string units, each with a value and the state "translated"."""
    units = _string_units(localization)
    return bool(units) and all(
        unit.get("state") == "translated" and str(unit.get("value", "")).strip() for unit in units)


def catalog_untranslated(catalog: Path, languages: tuple[str, ...] = LANGUAGES,
                         root: Path = ROOT) -> list[tuple[str, str]]:
    """(catalog, key) for every string of a catalog not translated into each language."""
    data = json.loads(catalog.read_text(encoding="utf-8"))
    try:
        name = str(catalog.relative_to(root))
    except ValueError:
        name = str(catalog)
    missing = []
    for key, entry in data.get("strings", {}).items():
        if entry.get("shouldTranslate") is False or entry.get("extractionState") == "stale":
            continue
        for language in languages:
            if language == data.get("sourceLanguage"):
                continue
            if not is_translated(entry.get("localizations", {}).get(language)):
                missing.append((f"{name} ({language})", key))
    return missing


def main(argv: list[str] | None = None) -> int:
    args = argv if argv is not None else sys.argv[1:]
    if len(args) > 1 or (args and args[0].startswith("-")):
        print(__doc__, file=sys.stderr)
        return 2
    if args:
        missing = untranslated(Path(args[0]))
    else:
        missing = [item for catalog in catalogs() for item in catalog_untranslated(catalog)]
    for catalog, source in missing:
        print(f"{catalog}: {source!r}")
    print(f"untranslated: {len(missing)}")
    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
