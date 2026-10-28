"""Tests for untranslated.py with a synthetic XLIFF export and synthetic String Catalogs.

    uv run --with pytest==8.4.2 pytest -q scripts/ci
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import untranslated  # noqa: E402

XLIFF = """<?xml version="1.0" encoding="UTF-8"?>
<xliff xmlns="urn:oasis:names:tc:xliff:document:1.2" version="1.2">
  <file original="Packages/A/Localizable.xcstrings" source-language="en" target-language="fr" datatype="plaintext">
    <body>
      <trans-unit id="Done"><source>Done</source><target state="translated">OK</target></trans-unit>
      <trans-unit id="Scan"><source>Scan</source></trans-unit>
      <trans-unit id="Empty"><source>Empty</source><target> </target></trans-unit>
    </body>
  </file>
</xliff>
"""


def test_units_without_a_translation_are_listed_and_fail(tmp_path, capsys):
    path = tmp_path / "fr.xliff"
    path.write_text(XLIFF, encoding="utf-8")
    assert untranslated.untranslated(path) == [
        ("Packages/A/Localizable.xcstrings", "Scan"), ("Packages/A/Localizable.xcstrings", "Empty")]
    assert untranslated.main([str(path)]) == 1
    assert "untranslated: 2" in capsys.readouterr().out


def test_app_names_and_strings_the_app_catalog_translates_are_not_counted(tmp_path):
    export = """<?xml version="1.0" encoding="UTF-8"?>
<xliff xmlns="urn:oasis:names:tc:xliff:document:1.2" version="1.2">
  <file original="App/PDFAlgoPro/Resources/InfoPlist.xcstrings" target-language="fr">
    <body><trans-unit id="CFBundleDisplayName"><source>PDF Algo Pro</source></trans-unit></body>
  </file>
  <file original="Packages/PDFEngine/Sources/PDFEngine/Resources/en.lproj/Localizable.strings" target-language="fr">
    <body>
      <trans-unit id="Drawing area"><source>Drawing area</source></trans-unit>
      <trans-unit id="Other"><source>Other</source></trans-unit>
    </body>
  </file>
</xliff>
"""
    path = tmp_path / "fr.xliff"
    path.write_text(export, encoding="utf-8")
    catalog = tmp_path / "Localizable.xcstrings"
    catalog.write_text('{"strings": {"Drawing area": {"localizations": {"fr": {}}}, "Other": {}}}', encoding="utf-8")
    assert untranslated.untranslated(path, catalog) == [
        ("Packages/PDFEngine/Sources/PDFEngine/Resources/en.lproj/Localizable.strings", "Other")]


def test_a_complete_export_passes(tmp_path):
    path = tmp_path / "fr.xliff"
    path.write_text(XLIFF.replace('<trans-unit id="Scan"><source>Scan</source></trans-unit>', "")
                    .replace("<target> </target>", "<target>Vide</target>"), encoding="utf-8")
    assert untranslated.main([str(path)]) == 0


def _unit(value: str, state: str = "translated") -> dict:
    return {"stringUnit": {"state": state, "value": value}}


CATALOG = {
    "sourceLanguage": "en",
    "strings": {
        "Done": {"localizations": {"fr": _unit("OK")}},
        "Scan": {},
        "Share": {"localizations": {"fr": _unit("Partager", state="needs_review")}},
        "Empty": {"localizations": {"fr": _unit(" ")}},
        "%lld pages": {"localizations": {"fr": {"variations": {"plural": {
            "one": _unit("%lld page"), "other": _unit("%lld pages")}}}}},
        "%lld files": {"localizations": {"fr": {"variations": {"plural": {
            "one": _unit("%lld fichier"), "other": _unit("")}}}}},
        "%#@pages@ in %@": {"localizations": {"fr": {
            "stringUnit": {"state": "translated", "value": "%#@pages@ dans %@"},
            "substitutions": {"pages": {"variations": {"plural": {"other": _unit("%arg pages", state="new")}}}}}}},
        "PDF Algo Pro": {"shouldTranslate": False},
        "Gone": {"extractionState": "stale"},
    },
    "version": "1.0",
}


def test_catalog_strings_without_a_finished_french_translation_are_listed(tmp_path):
    path = tmp_path / "Localizable.xcstrings"
    path.write_text(json.dumps(CATALOG), encoding="utf-8")
    missing = untranslated.catalog_untranslated(path, root=tmp_path)
    assert [key for _, key in missing] == ["Scan", "Share", "Empty", "%lld files", "%#@pages@ in %@"]
    assert {name for name, _ in missing} == {"Localizable.xcstrings (fr)"}


def test_catalogs_are_found_in_the_source_and_not_in_build_output(tmp_path):
    for relative in ["App/A/Localizable.xcstrings", "Packages/B/Resources/Localizable.xcstrings",
                     "Packages/B/.build/out/Localizable.xcstrings", "Docs/Localizable.xcstrings"]:
        (tmp_path / relative).parent.mkdir(parents=True, exist_ok=True)
        (tmp_path / relative).write_text("{}", encoding="utf-8")
    assert [str(path.relative_to(tmp_path)) for path in untranslated.catalogs(tmp_path)] == [
        "App/A/Localizable.xcstrings", "Packages/B/Resources/Localizable.xcstrings"]


def test_without_an_export_every_catalog_is_checked(tmp_path, monkeypatch, capsys):
    path = tmp_path / "Localizable.xcstrings"
    path.write_text(json.dumps(CATALOG), encoding="utf-8")
    monkeypatch.setattr(untranslated, "catalogs", lambda root=untranslated.ROOT: [path])
    assert untranslated.main([]) == 1
    assert "untranslated: 5" in capsys.readouterr().out
    done = {"sourceLanguage": "en", "strings": {"Done": CATALOG["strings"]["Done"]}}
    path.write_text(json.dumps(done), encoding="utf-8")
    assert untranslated.main([]) == 0
    assert untranslated.main(["--catalogs"]) == 2


def test_the_repository_catalogs_are_translated():
    assert untranslated.main([]) == 0
