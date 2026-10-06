#!/usr/bin/env python3
"""Check that the app's public pages answer: privacy policy, terms of use, support, the product page and the website.

    python3 scripts/ci/check_public_links.py            # request each page
    python3 scripts/ci/check_public_links.py --list     # print the addresses, no network

The App Store record and every shipped build link to these pages (docs/release-management.md:
"Privacy policy and support URLs open and current"). The paths are read from the app's own
`AppLinks.swift`, so this checks what the build links to, in English (the short address, which the
website redirects) and in French. A page passes when it answers 200 on algorythmos.com over HTTPS
after redirects. Standard library only. Exit 1 when any page fails.
"""
from __future__ import annotations

import re
import sys
import urllib.error
import urllib.request
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[2]
APP_LINKS = ROOT / "Packages" / "Features" / "Settings" / "Sources" / "SettingsFeature" / "AppLinks.swift"
SITE = re.compile(r'static let site = "(https://[^"]+)"')
PAGE = re.compile(r'case \w+ = "(/[^"]+)"')
FRENCH = "/fr-fr"


def addresses(source: str) -> list[str]:
    """Every address the app and the App Store record link to, from the text of AppLinks.swift."""
    site = SITE.search(source)
    pages = PAGE.findall(source)
    if not site or not pages:
        raise ValueError("AppLinks.swift no longer declares `site` and its pages as string literals")
    product = pages[0].rsplit("/", 1)[0]
    paths = [product, *pages]
    # The website itself is last: About's "Built by Algorythmos" opens it.
    return [site.group(1) + prefix + path for prefix in ("", FRENCH) for path in paths] + [site.group(1)]


def problem(url: str, timeout: float = 20) -> str | None:
    """Why a page fails, or None when it answers."""
    host = urlsplit(url).netloc
    request = urllib.request.Request(url, headers={"User-Agent": "pdf-algo-pro-release-check"})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:  # noqa: S310 - https literals from AppLinks.swift
            final = urlsplit(response.geturl())
            if response.status != 200:
                return f"{url}: answered {response.status}"
            if final.scheme != "https" or final.netloc != host:
                return f"{url}: ended at {response.geturl()}, not on https://{host}"
            if url.split(host, 1)[1].startswith(FRENCH) and not final.path.startswith(FRENCH):
                return f"{url}: the French address ended at {final.path}"
    except urllib.error.HTTPError as error:
        return f"{url}: answered {error.code}"
    except (urllib.error.URLError, TimeoutError) as error:
        return f"{url}: {error}"
    return None


def main(argv: list[str]) -> int:
    urls = addresses(APP_LINKS.read_text(encoding="utf-8"))
    if "--list" in argv:
        print("\n".join(urls))
        return 0
    failures = [found for url in urls if (found := problem(url))]
    for failure in failures:
        print(f"::error::{failure}")
    print(f"public pages: {len(urls) - len(failures)} of {len(urls)} answer")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
