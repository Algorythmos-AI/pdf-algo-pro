#!/usr/bin/env python3
"""Source invariants for the ci.yml `invariants` job (gurbani-soul-ios pattern). Standard library only.

Always active:
  * no PDF is committed outside Tests/Fixtures/Synthetic/ (real documents never enter git).

Active once Swift sources exist (dormant before the first code pull request):
  * no `try!` and no `as!` outside tests;
  * `print(` only inside `#if DEBUG` blocks;
  * networking APIs only in the Intelligence, Commerce and Telemetry packages;
  * colour literals only in the DesignSystem package;
  * the commercial PDF SDK imported only in the PDFEngine package;
  * a PrivacyInfo.xcprivacy exists and declares every required-reason API category the code uses.

Exit 1 on any violation.
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

NETWORK = re.compile(r"\b(URLSession|URLRequest|NWConnection|WKWebView)\b|^\s*import\s+Network\b", re.M)
COLOUR = re.compile(r"Color\(\s*hex:|UIColor\(\s*red:|Color\(\s*red:|#[0-9A-Fa-f]{6}\b")
VENDOR_SDK = re.compile(r"^\s*import\s+(PSPDFKit|PSPDFKitUI|Nutrient|NutrientUI|PDFNet|Tools)\b", re.M)
REQUIRED_REASON = {
    "NSPrivacyAccessedAPICategoryUserDefaults": re.compile(r"\bUserDefaults\b|@AppStorage"),
    "NSPrivacyAccessedAPICategoryFileTimestamp": re.compile(r"\.(creationDate|modificationDate|contentModificationDate)\b|attributesOfItem"),
    "NSPrivacyAccessedAPICategorySystemBootTime": re.compile(r"systemUptime|mach_absolute_time"),
    "NSPrivacyAccessedAPICategoryDiskSpace": re.compile(r"volumeAvailableCapacity|systemFreeSize|systemSize\b"),
}
ALLOWED = {
    "network": ("Packages/Intelligence/", "Packages/Commerce/", "Packages/Telemetry/"),
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

    swift = [p for p in tracked("*.swift")]
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
                errors.append(f"{rel}: networking is only allowed in Intelligence, Commerce and Telemetry")
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
