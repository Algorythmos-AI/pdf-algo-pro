"""Tests for check_tester_notes.py with synthetic notes.

    uv run --with pytest==8.4.2 pytest -q scripts/ci
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_tester_notes  # noqa: E402

ENGLISH = "Please try:\n\nNew\n- One thing.\n- Another.\n\nReport problems in Settings.\n"
FRENCH = "À essayer :\n\nNouveau\n- Une chose.\n- Une autre.\n\nSignalez les problèmes dans Réglages.\n"


def notes(folder: Path, **texts: str) -> Path:
    """Writes notes into a folder; a locale is given as `en_US="…"`."""
    for locale, text in texts.items():
        (folder / f"WhatToTest.{locale.replace('_', '-')}.txt").write_text(text, encoding="utf-8")
    return folder


def test_notes_for_every_locale_alike_in_shape_pass(tmp_path):
    assert check_tester_notes.problems(notes(tmp_path, en_US=ENGLISH, en_AU=ENGLISH, fr_FR=FRENCH)) == []


def test_the_repository_notes_pass():
    assert check_tester_notes.problems(check_tester_notes.FOLDER) == []


def test_a_locale_with_no_file_is_found(tmp_path):
    found = check_tester_notes.problems(notes(tmp_path, en_US=ENGLISH, fr_FR=FRENCH))
    assert len(found) == 1 and "WhatToTest.en-AU.txt is missing" in found[0]


def test_the_primary_language_file_must_be_the_copy(tmp_path):
    found = check_tester_notes.problems(
        notes(tmp_path, en_US=ENGLISH, en_AU=ENGLISH.replace("One", "A"), fr_FR=FRENCH))
    assert len(found) == 1 and "differs from WhatToTest.en-US.txt" in found[0]


def test_an_empty_file_is_found(tmp_path):
    found = check_tester_notes.problems(notes(tmp_path, en_US=ENGLISH, en_AU=ENGLISH, fr_FR="\n"))
    assert any("WhatToTest.fr-FR.txt is empty" in item for item in found)


def test_too_many_characters_or_too_many_bytes_is_found(tmp_path):
    long = ENGLISH + "- " + "x" * check_tester_notes.LIMIT + "\n"
    found = check_tester_notes.problems(notes(tmp_path, en_US=long, en_AU=long, fr_FR=FRENCH))
    assert sum("the limit is" in item for item in found) == 2

    # Within the limit in characters, past it in bytes: accented letters take two bytes each.
    accented = "À essayer :\n\nNouveau\n- " + "é" * 2100 + "\n- Une autre.\n\nSignalez les problèmes.\n"
    assert len(accented) < check_tester_notes.LIMIT < len(accented.encode("utf-8"))
    found = check_tester_notes.problems(notes(tmp_path, en_US=ENGLISH, en_AU=ENGLISH, fr_FR=accented))
    assert len(found) == 1 and "WhatToTest.fr-FR.txt" in found[0] and "bytes" in found[0]


def test_locales_that_drift_apart_are_found(tmp_path):
    one_line_short = FRENCH.replace("- Une autre.\n", "")
    found = check_tester_notes.problems(notes(tmp_path, en_US=ENGLISH, en_AU=ENGLISH, fr_FR=one_line_short))
    assert len(found) == 1 and "same blocks and lines" in found[0]

    one_block_more = FRENCH + "\nProblèmes connus\n- Aucun.\n"
    found = check_tester_notes.problems(notes(tmp_path, en_US=ENGLISH, en_AU=ENGLISH, fr_FR=one_block_more))
    assert len(found) == 1 and "same blocks and lines" in found[0]


def test_a_file_for_another_locale_is_held_to_the_same_shape(tmp_path):
    found = check_tester_notes.problems(
        notes(tmp_path, en_US=ENGLISH, en_AU=ENGLISH, fr_FR=FRENCH, de_DE="Bitte testen:\n"))
    assert len(found) == 1 and "de-DE" in found[0]
