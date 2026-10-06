"""Tests for the app-icon, app-name and network checks in invariants.py, with synthetic inputs.

    uv run --with pytest==8.4.2 pytest -q scripts/ci
"""
from __future__ import annotations

import json
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


def test_the_committed_icons_pass():
    assert invariants.icon_problems() == []


def test_the_app_mark_is_a_square_png_from_the_icon_script(tmp_path):
    assert invariants.app_mark_problems() == []
    assert "missing; run scripts/design/make_app_icon.swift" in invariants.app_mark_problems(tmp_path / "AppMark.png")[0]
    wide = tmp_path / "wide.png"
    wide.write_bytes(png(360, 180, 2))
    assert "not square" in invariants.app_mark_problems(wide)[0]
    wide.write_bytes(b"GIF89a")
    assert "not a PNG" in invariants.app_mark_problems(wide)[0]


def test_every_icon_set_needs_an_opaque_default_image(tmp_path):
    app_store = tmp_path / "AppIcon.appiconset"
    app_store.mkdir()
    (app_store / "Contents.json").write_text(json.dumps({"images": [{"filename": "AppIcon.png"}]}), encoding="utf-8")
    (app_store / "AppIcon.png").write_bytes(png(1024, 1024, 6))
    problems = invariants.icon_problems(tmp_path)
    assert len(problems) == 2
    assert "alpha channel" in problems[0]
    assert "AppIcon-Staging.appiconset: missing" in problems[1]


def test_every_icon_set_needs_an_icon_composer_document_with_its_layers(tmp_path):
    assert invariants.icon_document_problems() == []
    document = tmp_path / "AppIcon.icon"
    document.mkdir()
    layers = {"groups": [{"layers": [{"image-name": "page.png"}]}]}
    (document / "icon.json").write_text(json.dumps(layers), encoding="utf-8")
    problems = invariants.icon_document_problems(tmp_path)
    assert problems == [
        "AppIcon.icon: layer image page.png is missing from Assets",
        "AppIcon-Staging.icon: missing; run scripts/design/make_app_icon.swift",
    ]


def test_info_plist_localisations_never_carry_the_app_names(tmp_path):
    assert invariants.infoplist_name_problems() == []
    app = tmp_path / "App" / "PDFAlgoPro"
    (app / "fr.lproj").mkdir(parents=True)
    (app / "fr.lproj" / "InfoPlist.strings").write_text(
        '"NSCameraUsageDescription" = "Appareil photo";\n"CFBundleDisplayName" = "PDF Algo Pro";\n', encoding="utf-8")
    (app / "Resources").mkdir()
    (app / "Resources" / "InfoPlist.xcstrings").write_text(json.dumps({"strings": {}}))
    problems = invariants.infoplist_name_problems(app)
    assert len(problems) == 2
    assert "InfoPlist.xcstrings" in problems[0] and "CFBundleDisplayName" in problems[1]


def test_network_pattern_covers_cloudkit_and_the_allow_list_names_remote_config():
    assert invariants.NETWORK.search("import CloudKit\n")
    assert invariants.NETWORK.search("let s = URLSession.shared")
    assert not invariants.NETWORK.search("import CloudKitten\n")
    assert "Packages/RemoteConfig/" in invariants.ALLOWED["network"]
