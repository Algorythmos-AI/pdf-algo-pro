"""Tests for untranslated.py with a synthetic XLIFF export.

    uv run --with pytest==8.4.2 pytest -q scripts/ci
"""
from __future__ import annotations

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
