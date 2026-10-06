"""Tests for privacy_impact.py with synthetic diffs.

    uv run --with pytest==8.4.2 pytest -q scripts/ci
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import privacy_impact  # noqa: E402


def diff(path: str, *lines: str) -> str:
    return f"diff --git a/{path} b/{path}\n--- a/{path}\n+++ b/{path}\n@@ -1 +1 @@\n" + "\n".join(lines) + "\n"


def test_ordinary_changes_need_no_statement():
    changes = (
        diff("Packages/Features/Reader/Sources/ReaderFeature/ReaderView.swift", "+    Text(\"Edit\")")
        + diff("project.yml", "+    MARKETING_VERSION: 0.2.0")
        + diff("Packages/Intelligence/Package.swift", "+      .target(name: \"Intelligence\"),")
        + diff("docs/prd.md", "+URLSession is not used.")
    )
    assert privacy_impact.reasons(changes) == []
    assert privacy_impact.problems(changes, "") == []


def test_each_kind_of_privacy_change_is_found():
    cases = {
        "App/PDFAlgoPro/Resources/PrivacyInfo.xcprivacy": ("+<string>35F9.1</string>", "privacy manifest"),
        "project.yml": ("+        NSMicrophoneUsageDescription: Dictate a note.", "usage description"),
        "App/PDFAlgoPro/fr.lproj/InfoPlist.strings": ("-\"NSCameraUsageDescription\" = \"…\";", "usage description"),
        "scripts/ci/invariants.py": ("+    \"network\": (\"Packages/Intelligence/\", \"Packages/Sync/\"),", "allow-list"),
        "Packages/Telemetry/Package.swift": ("+    .package(url: \"https://example.com/sdk\", from: \"1.0.0\"),", "dependency"),
        "Packages/Intelligence/Sources/Intelligence/Relay.swift": ("+    let session = URLSession.shared", "networking"),
    }
    for path, (line, expected) in cases.items():
        found = privacy_impact.reasons(diff(path, line))
        assert len(found) == 1 and expected in found[0] and found[0].startswith(path), (path, found)


def test_removed_networking_and_test_code_are_not_flagged():
    assert privacy_impact.reasons(diff("Packages/A/Sources/A/A.swift", "-    let session = URLSession.shared")) == []
    assert privacy_impact.reasons(diff("Packages/A/Tests/ATests/ATests.swift", "+    let session = URLSession.shared")) == []
    # A removed dependency needs no statement; a removed manifest entry does.
    assert privacy_impact.reasons(diff("Packages/A/Package.swift", "-    .package(url: \"https://example.com/sdk\", from: \"1.0.0\"),")) == []
    assert privacy_impact.reasons(diff("App/PDFAlgoPro/Resources/PrivacyInfo.xcprivacy", "-<string>E174.1</string>"))


def test_one_finding_per_file_and_kind():
    changes = diff("App/PDFAlgoPro/Resources/PrivacyInfo.xcprivacy", "-<string>a</string>", "+<string>b</string>")
    assert len(privacy_impact.reasons(changes)) == 1


def test_a_statement_in_the_description_satisfies_the_gate():
    changes = diff("App/PDFAlgoPro/Resources/PrivacyInfo.xcprivacy", "+<string>35F9.1</string>")
    assert privacy_impact.problems(changes, "## What and why\n\nAdds a reason code.\n")
    for body in (
        "Privacy policy impact: none, because the reason code covers an API the policy does not describe.",
        "## Privacy\n\n- **Privacy policy impact:** https://github.com/Algorythmos-AI/algorythmos-website/pull/99\n",
        "privacy policy impact: none, because nothing leaves the device\r\n",
    ):
        assert privacy_impact.problems(changes, body) == [], body


def test_the_template_placeholder_is_not_a_statement():
    changes = diff("project.yml", "+        NSCameraUsageDescription: Scan a page.")
    for body in ("Privacy policy impact: <!-- none, because …, or a link -->", "Privacy policy impact:   ", ""):
        assert privacy_impact.declaration(body) is None
        assert privacy_impact.problems(changes, body)
