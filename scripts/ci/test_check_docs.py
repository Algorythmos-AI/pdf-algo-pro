"""Probe tests for check_docs.py rules that are easy to break silently.

    uv run --with pytest==8.4.2 pytest -q scripts/ci
"""
from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_docs  # noqa: E402

GOOD = "Owner: Architecture and Security · Reviewed: each milestone"


@pytest.mark.parametrize("rel", ["docs/prd.md", "docs/process/branching.md", "docs/process/runbooks/kill-switch.md"])
def test_owned_document_passes(rel):
    assert check_docs.owner_errors(Path(rel), ["# Title", "", GOOD]) == []


@pytest.mark.parametrize("line, fragment", [
    ("Owner: QA · Reviewed: monthly", "unknown hat"),
    ("Owner: Product (growth) · Reviewed: monthly", "unknown hat"),
    ("Owner: Maintainer. Reviewed: monthly", "must read"),
    ("Owner: Maintainer", "must read"),
])
def test_bad_owner_line_fails(line, fragment):
    errors = check_docs.owner_errors(Path("docs/prd.md"), ["# Title", line])
    assert len(errors) == 1 and fragment in errors[0]


def test_missing_or_duplicate_owner_line_fails():
    assert "found 0" in check_docs.owner_errors(Path("docs/prd.md"), ["# Title"])[0]
    assert "found 2" in check_docs.owner_errors(Path("docs/prd.md"), [GOOD, GOOD])[0]


@pytest.mark.parametrize("rel", ["docs/adr/0001-platform.md", "docs/wiki/Home.md", "README.md", ".github/SUPERVISION.md"])
def test_unowned_locations_are_skipped(rel):
    assert check_docs.owner_errors(Path(rel), ["# Title"]) == []


def test_every_allowed_hat_is_in_the_supervision_or_governance_tables():
    tables = (check_docs.ROOT / ".github/SUPERVISION.md").read_text() + (check_docs.ROOT / "docs/github-governance.md").read_text()
    missing = [hat for hat in check_docs.ALLOWED_HATS if f"| {hat} |" not in tables]
    assert missing == []
