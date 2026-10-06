#!/usr/bin/env python3
"""Source invariants for the ci.yml `invariants` job (gurbani-soul-ios pattern). Standard library only.

Always active:
  * no PDF is committed outside Tests/Fixtures/Synthetic/ (real documents never enter git);
  * each app icon set (App Store and Staging) has a default image that is a 1024 x 1024 PNG without
    an alpha channel or transparency, as App Store Connect requires (upload error 90717), and an
    Icon Composer document of the same name whose layer images all exist;
  * no Info.plist localisation carries an app name, and there is no InfoPlist.xcstrings (Xcode syncs
    the names into it): the names come from build settings per configuration (Staging is
    "PDF Algo β"), and a localised value would replace them (assumption A14).

Active once Swift sources exist (dormant before the first code pull request); the rules apply to the
app and its packages, not to developer tools under scripts/:
  * no `try!` and no `as!` outside tests;
  * `print(` only inside `#if DEBUG` blocks;
  * networking APIs only in the Intelligence, Commerce and Telemetry packages;
  * colour literals only in the DesignSystem package;
  * the commercial PDF SDK imported only in the PDFEngine package;
  * a PrivacyInfo.xcprivacy exists and declares every required-reason API category the code uses.

Exit 1 on any violation.
"""
from __future__ import annotations

import json
import re
import struct
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

NETWORK = re.compile(r"\b(URLSession|URLRequest|NWConnection|WKWebView)\b|^\s*import\s+(Network|CloudKit)\b", re.M)
COLOUR = re.compile(r"Color\(\s*hex:|UIColor\(\s*red:|Color\(\s*red:|#[0-9A-Fa-f]{6}\b")
VENDOR_SDK = re.compile(r"^\s*import\s+(PSPDFKit|PSPDFKitUI|Nutrient|NutrientUI|PDFNet|Tools)\b", re.M)
REQUIRED_REASON = {
    "NSPrivacyAccessedAPICategoryUserDefaults": re.compile(r"\bUserDefaults\b|@AppStorage"),
    "NSPrivacyAccessedAPICategoryFileTimestamp": re.compile(r"\.(creationDate|modificationDate|contentModificationDate)\b|attributesOfItem"),
    "NSPrivacyAccessedAPICategorySystemBootTime": re.compile(r"systemUptime|mach_absolute_time"),
    "NSPrivacyAccessedAPICategoryDiskSpace": re.compile(r"volumeAvailableCapacity|systemFreeSize|systemSize\b"),
}
ICON_CATALOG = "App/PDFAlgoPro/Resources/Assets.xcassets"
APP_ICONS = ("AppIcon", "AppIcon-Staging")
ALLOWED = {
    "network": ("Packages/Intelligence/", "Packages/Commerce/", "Packages/Telemetry/", "Packages/RemoteConfig/"),
    "colour": ("Packages/DesignSystem/",),
    "vendor": ("Packages/PDFEngine/",),
}


def tracked(*patterns: str) -> list[str]:
    return subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", *patterns],
        cwd=ROOT, capture_output=True, text=True, check=True,
    ).stdout.split()


def is_test(path: str) -> bool:
    return "/Tests/" in f"/{path}" or path.endswith("Tests.swift")


def png_problems(data: bytes, name: str) -> list[str]:
    """Why a PNG cannot be the default app icon: wrong size, an alpha channel, or transparency."""
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        return [f"{name}: not a PNG"]
    width, height, _depth, colour_type = struct.unpack(">IIBB", data[16:26])
    problems = []
    if (width, height) != (1024, 1024):
        problems.append(f"{name}: {width} x {height}, not 1024 x 1024")
    if colour_type in (4, 6):
        problems.append(f"{name}: has an alpha channel; the default app icon must be opaque")
    offset = 8
    while offset + 8 <= len(data):
        length, kind = struct.unpack(">I4s", data[offset:offset + 8])
        if kind == b"tRNS":
            problems.append(f"{name}: has transparency (tRNS); the default app icon must be opaque")
        if kind == b"IEND":
            break
        offset += 12 + length
    return problems


def icon_problems(catalog: Path = ROOT / ICON_CATALOG) -> list[str]:
    if not catalog.exists():
        return []
    problems: list[str] = []
    for icon in APP_ICONS:
        label = f"{ICON_CATALOG}/{icon}.appiconset"
        contents = catalog / f"{icon}.appiconset" / "Contents.json"
        if not contents.exists():
            problems.append(f"{label}: missing; a build configuration names this icon set")
            continue
        images = json.loads(contents.read_text(encoding="utf-8")).get("images", [])
        default = [i for i in images if not i.get("appearances") and i.get("filename")]
        if not default:
            problems.append(f"{label}: no default image; App Store Connect rejects a build without an app icon")
            continue
        name = default[0]["filename"]
        path = contents.parent / name
        if not path.exists():
            problems.append(f"{label}/{name}: listed in Contents.json but missing")
            continue
        problems.extend(png_problems(path.read_bytes(), f"{label}/{name}"))
    return problems


def icon_document_problems(resources: Path = (ROOT / ICON_CATALOG).parent) -> list[str]:
    """Each icon set has an Icon Composer document of the same name whose layers all exist."""
    if not resources.exists():
        return []
    problems: list[str] = []
    for icon in APP_ICONS:
        document = resources / f"{icon}.icon"
        if not (document / "icon.json").exists():
            problems.append(f"{icon}.icon: missing; run scripts/design/make_app_icon.swift")
            continue
        for group in json.loads((document / "icon.json").read_text(encoding="utf-8")).get("groups", []):
            for layer in group.get("layers", []):
                name = layer.get("image-name")
                if name and not (document / "Assets" / name).exists():
                    problems.append(f"{icon}.icon: layer image {name} is missing from Assets")
    return problems


APP_MARK = "Packages/DesignSystem/Sources/DesignSystem/Resources/AppMark.png"


def app_mark_problems(path: Path = ROOT / APP_MARK) -> list[str]:
    """The app mark the interface shows is written by the icon script, so it exists and is a square PNG."""
    if not path.exists():
        return [f"{APP_MARK}: missing; run scripts/design/make_app_icon.swift"]
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        return [f"{APP_MARK}: not a PNG"]
    width, height = struct.unpack(">II", data[16:24])
    return [] if width == height else [f"{APP_MARK}: {width} x {height}, not square"]


APP_SOURCES = "App/PDFAlgoPro"
APP_NAME_KEYS = ("CFBundleDisplayName", "CFBundleName")


def infoplist_name_problems(app: Path = ROOT / APP_SOURCES) -> list[str]:
    problems = []
    for catalog in sorted(app.rglob("InfoPlist.xcstrings")):
        problems.append(f"{catalog.relative_to(app.parent.parent)}: use <language>.lproj/InfoPlist.strings next "
                        "to Info.plist instead; Xcode syncs the app's names into a catalog (A14)")
    for strings in sorted(app.rglob("*.lproj/InfoPlist.strings")):
        text = strings.read_text(encoding="utf-8")
        for key in APP_NAME_KEYS:
            if re.search(rf'^\s*"?{key}"?\s*=', text, re.M):
                problems.append(f"{strings.relative_to(app.parent.parent)}: remove {key}; the app's names come "
                                "from build settings per configuration (A14)")
    return problems


def print_outside_debug(text: str) -> list[int]:
    bad, depth = [], 0
    for no, line in enumerate(text.splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith("#if") and "DEBUG" in stripped:
            depth += 1
        elif stripped.startswith("#endif") and depth:
            depth -= 1
        elif re.search(r"(?<![\w.])print\(", line) and depth == 0:
            bad.append(no)
    return bad


def main() -> int:
    errors: list[str] = []

    for pdf in tracked("*.pdf"):
        if not pdf.startswith("Tests/Fixtures/Synthetic/") and "/Tests/Fixtures/Synthetic/" not in pdf:
            errors.append(f"{pdf}: PDFs may only live in Tests/Fixtures/Synthetic/ (no real documents in git)")

    errors.extend(icon_problems())
    errors.extend(icon_document_problems())
    errors.extend(app_mark_problems())
    errors.extend(infoplist_name_problems())

    swift = [p for p in tracked("*.swift") if not p.startswith("scripts/")]
    if not swift:
        print("invariants: no Swift sources yet; Swift rules are dormant")
    else:
        used_categories: set[str] = set()
        for rel in swift:
            text = (ROOT / rel).read_text(encoding="utf-8")
            if not is_test(rel):
                if re.search(r"\btry!", text):
                    errors.append(f"{rel}: `try!` is not allowed; handle or propagate the error")
                if re.search(r"\bas!\s", text):
                    errors.append(f"{rel}: `as!` is not allowed; use a conditional cast")
                for no in print_outside_debug(text):
                    errors.append(f"{rel}:{no}: `print(` outside `#if DEBUG`; use Logger")
                for category, pattern in REQUIRED_REASON.items():
                    if pattern.search(text):
                        used_categories.add(category)
            if NETWORK.search(text) and not rel.startswith(ALLOWED["network"]) and not is_test(rel):
                errors.append(f"{rel}: networking is only allowed in Intelligence, Commerce, Telemetry and RemoteConfig")
            if COLOUR.search(text) and not rel.startswith(ALLOWED["colour"]):
                errors.append(f"{rel}: colour literals belong in DesignSystem tokens")
            if VENDOR_SDK.search(text) and not rel.startswith(ALLOWED["vendor"]):
                errors.append(f"{rel}: the PDF SDK may only be imported in PDFEngine")

        manifests = tracked("*PrivacyInfo.xcprivacy")
        if not manifests:
            errors.append("Swift sources exist but no PrivacyInfo.xcprivacy is committed")
        else:
            declared = "".join((ROOT / m).read_text(encoding="utf-8") for m in manifests)
            for category in sorted(used_categories):
                if category not in declared:
                    errors.append(f"privacy manifest does not declare {category}, which the code uses")

    for e in errors:
        print(f"::error::{e}")
    print(f"invariants: {len(errors)} violation(s)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
