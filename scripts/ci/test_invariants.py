"""Tests for the app-icon check in invariants.py, with synthetic PNG headers.

    uv run --with pytest==8.4.2 pytest -q scripts/ci
"""
from __future__ import annotations

import struct
import sys
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import invariants  # noqa: E402


def chunk(kind: bytes, payload: bytes) -> bytes:
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload))


def png(width: int, height: int, colour_type: int, extra: bytes = b"") -> bytes:
    header = struct.pack(">IIBBBBB", width, height, 8, colour_type, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + extra + chunk(b"IEND", b"")


def test_an_opaque_1024_rgb_png_passes():
    assert invariants.png_problems(png(1024, 1024, 2), "icon") == []


def test_alpha_transparency_size_and_format_are_reported():
    assert "alpha channel" in invariants.png_problems(png(1024, 1024, 6), "icon")[0]
    assert "transparency" in invariants.png_problems(png(1024, 1024, 2, chunk(b"tRNS", b"\x00" * 6)), "icon")[0]
    assert "not 1024 x 1024" in invariants.png_problems(png(512, 512, 2), "icon")[0]
    assert invariants.png_problems(b"GIF89a", "icon") == ["icon: not a PNG"]


def test_the_committed_icon_passes():
    assert invariants.icon_problems() == []
