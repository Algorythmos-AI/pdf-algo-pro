"""Tests for the accessibility identifier generator (scripts/design/generate_accessibility_ids.py)."""
from __future__ import annotations

import importlib.util
from pathlib import Path

SPEC = importlib.util.spec_from_file_location(
    "generate_accessibility_ids", Path(__file__).with_name("generate_accessibility_ids.py")
)
assert SPEC and SPEC.loader
gen = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(gen)


def test_a_sound_list_has_no_errors():
    assert gen.validate(["library.list", "reader.markup", "reader.markup.paste", "reader.pageStrip.{page:Int}"]) == []


def test_an_unsorted_list_is_refused():
    assert "the identifiers are not sorted" in gen.validate(["reader.more", "library.list"])


def test_a_duplicate_is_refused():
    assert any("appears twice" in e for e in gen.validate(["reader.more", "reader.more"]))


def test_a_part_that_is_not_lower_camel_case_is_refused():
    assert any("lower camel case" in e for e in gen.validate(["reader.Markup"]))
    assert any("lower camel case" in e for e in gen.validate(["reader.text-edit"]))


def test_a_value_in_braces_must_come_last():
    assert any("last part" in e for e in gen.validate(["library.{title}.row"]))


def test_a_single_part_is_refused():
    assert any("screen and a name" in e for e in gen.validate(["more"]))


def test_a_value_needs_a_screen_and_a_name_before_it():
    assert any("before it" in e for e in gen.validate(["library.{title}"]))


def test_dots_become_nested_enums_and_a_leaf_beside_its_enum():
    text = gen.render(["reader.markup", "reader.markup.paste"])
    assert "public enum Reader {" in text
    assert 'public static let markup = "reader.markup"' in text
    assert "public enum Markup {" in text
    assert 'public static let paste = "reader.markup.paste"' in text


def test_a_value_in_braces_becomes_a_function_in_the_parent():
    text = gen.render(["library.document.{title}", "reader.pageStrip", "reader.pageStrip.{page:Int}"])
    assert "public static func document(_ title: String) -> String {" in text
    assert '"library.document.\\(title)"' in text
    assert "public static func pageStrip(_ page: Int) -> String {" in text
    assert 'public static let pageStrip = "reader.pageStrip"' in text
    assert "enum Document" not in text and "enum PageStrip" not in text


def test_a_keyword_is_declared_in_backticks():
    text = gen.render(["onboarding.continue", "library.import"])
    assert 'public static let `continue` = "onboarding.continue"' in text
    assert 'public static let `import` = "library.import"' in text


def test_every_declaration_has_a_one_line_summary():
    lines = gen.render(["library.document.{title}", "reader.markup", "reader.markup.paste"]).splitlines()
    for index, line in enumerate(lines):
        if line.strip().startswith("public "):
            assert lines[index - 1].strip().startswith("///"), line


def test_the_generated_lines_fit_the_formatters_width():
    text = gen.render(gen.load())
    assert all(len(line) <= 120 for line in text.splitlines())


def test_the_committed_list_is_sound_and_the_file_is_current():
    ids = gen.load()
    assert gen.validate(ids) == []
    assert gen.OUTPUT.read_text(encoding="utf-8") == gen.render(ids)
