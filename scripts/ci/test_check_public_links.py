"""Tests for check_public_links.py. No network: the addresses come from the app's own AppLinks.swift.

    uv run --with pytest==8.4.2 pytest -q scripts/ci
"""
from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import check_public_links  # noqa: E402


def test_the_addresses_are_the_ones_the_app_links_to():
    urls = check_public_links.addresses(check_public_links.APP_LINKS.read_text(encoding="utf-8"))
    assert urls == [
        "https://algorythmos.com/pdf-algo-pro",
        "https://algorythmos.com/pdf-algo-pro/privacy",
        "https://algorythmos.com/pdf-algo-pro/terms",
        "https://algorythmos.com/pdf-algo-pro/support",
        "https://algorythmos.com/fr-fr/pdf-algo-pro",
        "https://algorythmos.com/fr-fr/pdf-algo-pro/privacy",
        "https://algorythmos.com/fr-fr/pdf-algo-pro/terms",
        "https://algorythmos.com/fr-fr/pdf-algo-pro/support",
        "https://algorythmos.com",
    ]


def test_a_file_that_stops_declaring_literals_fails_loudly():
    with pytest.raises(ValueError):
        check_public_links.addresses("public enum AppLinks { static let site = base }")
