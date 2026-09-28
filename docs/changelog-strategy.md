# Changelog and release notes

How one source of truth, the CHANGELOG, becomes every piece of release text PDF Algo Pro publishes:
the CHANGELOG itself, TestFlight "What to Test" notes, the App Store's "What's New" in English and
French, and the release notes on the wiki. It sets out who writes what and when, the tone for each
audience, and what must never appear in any of them.

Owner: Release · Reviewed: each release

## One source, four audiences

```text
pull request (conventional-commit title + CHANGELOG [Unreleased] entry)
        │   squash-merged into integration
        ▼
CHANGELOG.md  [Unreleased]  ──── release prep: becomes ## [X.Y.Z] - date
        │
        ├── TestFlight "What to Test"  (every Staging and Release build)
        ├── App Store "What's New"     (EN + FR, each release)
        ├── GitHub Release notes       (release.yml copies the section verbatim)
        └── wiki release notes page    (a curated page under docs/wiki/, mirrored by release.yml)
```

- **Conventional-commit titles** give every squash commit on `integration` a type and scope, enforced by
  the `pr-title` check ([branching](process/branching.md#pull-request-titles),
  [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/)). They are written for
  developers and are the raw material, not the published text.
- **The CHANGELOG entry** is written by the pull request's author, in the same pull request, whenever
  users will notice the change ([CONTRIBUTING](../.github/CONTRIBUTING.md)). The file follows
  [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) ([CHANGELOG.md](../CHANGELOG.md)).
- Everything else is derived from the CHANGELOG section for the version, rewritten for its audience.

### From commit type to CHANGELOG section

| Pull request type | CHANGELOG section | Note |
|---|---|---|
| `feat` | Added (new capability) or Changed (changed behaviour) | Always, if users can see it |
| `fix` | Fixed | Always, if users could have hit the bug |
| `perf` | Changed | When the difference is noticeable, and only with a measured number |
| `feat!` / `fix!` (breaking) | Changed, plus Removed or Deprecated as needed | Explain what users must do |
| Security fix | Security | General wording until the fix is released everywhere |
| `refactor`, `test`, `ci`, `build`, `chore`, `docs` | None, usually | Unless users notice, for example a new help page |
| `revert` | Removes the reverted entry | The entry disappears rather than being contradicted |
| `release` | None | Version preparation itself |

## The four artefacts

| Artefact | Audience | Source | Written when | Written by (hat) | Limits |
|---|---|---|---|---|---|
| [CHANGELOG.md](../CHANGELOG.md) | Everyone, including the maintainer later | The pull request | In each pull request; curated at release preparation | Author; Release curates | None |
| TestFlight "What to Test" | Testers | CHANGELOG `[Unreleased]` (Staging) or the version section (Release) plus known issues | Every build | Release | Keep it short. Xcode Cloud reads `TestFlight/WhatToTest.<locale>.txt` from the repository ([Including notes for testers](https://developer.apple.com/documentation/xcode/including-notes-for-testers-with-a-beta-release-of-your-app)) |
| App Store "What's New" | Users updating the app | The version section | Release preparation | Release (EN), Release with a French reviewer (FR) | At most 4000 characters per locale ([Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)) |
| GitHub Release and wiki release notes | Readers of the repository and wiki | The version section | GitHub Release: by `release.yml`; wiki page: in the release preparation pull request | Release | None |

The GitHub Release body is the CHANGELOG section verbatim: `release.yml` extracts it and fails on an
empty section ([release management](release-management.md#the-release-workflow)). The wiki release
notes page lives under `docs/wiki/` (it arrives with the wiki plan, `docs/wiki-plan.md`), so it is
written in the release preparation pull request and mirrored when `release.yml` publishes the wiki.

## Tone and examples

Across all four: plain words, the outcome for the person first, no marketing adjectives, no "AI" hype
(say what it does, not what it is), no internal names or issue numbers outside the CHANGELOG, and every
number measured, never estimated.

### CHANGELOG

Precise and complete, one line per change, present tense for what the product now does, issue number at
the end.

```markdown
## [1.2.0] - 2026-11-03

### Added
- Scanned documents in French are recognised and become searchable. (#142)

### Fixed
- Highlights no longer disappear after rotating a page on iPad. (#156)

### Security
- Hardened the handling of malformed PDF files. (#161)
```

### TestFlight "What to Test"

Addressed to testers: what changed, what to try, what is known to be broken, how to send feedback.

```text
New in this build
- French scanning: scan a French letter or invoice and search for a word in it.
- iPad: rotate pages that have highlights and check the highlights stay put.

Known issues
- Summaries of very long documents can take a while on older iPhones.

Send feedback with a screenshot from TestFlight. Please don't include real personal documents.
```

### App Store "What's New"

For people deciding whether to update: short, benefit first, no jargon. The French text is written for
French readers, not translated word for word, and follows French typography (a space before a colon).

```text
EN
- Scan documents in French: the text in your scans is now searchable in French as well as English.
- Fixed: highlights could disappear after rotating a page on iPad.

FR
- Numérisez vos documents en français : vous pouvez désormais rechercher du texte dans vos numérisations, en français comme en anglais.
- Correction : les surlignages pouvaient disparaître après la rotation d'une page sur iPad.
```

When a release adds or changes a cloud AI tier, What's New names the provider and says it is optional,
in line with the consent screen (ADR-0009).

### GitHub Release and wiki release notes

The GitHub Release is the CHANGELOG section as is. The wiki page adds one or two sentences of context
per release for a reader who does not follow the repository, and links to the GitHub Release.

## Who writes what, when

| When | Who (hat) | Writes |
|---|---|---|
| Each pull request | Author | A CHANGELOG `[Unreleased]` entry if users will notice |
| Each Staging build | Release | What to Test from `[Unreleased]`, in `TestFlight/WhatToTest.en-US.txt` once the file exists |
| Release preparation (`release: prepare X.Y.Z`) | Release | The dated version section; What's New EN and FR (in the pull request description); the wiki release notes page |
| External TestFlight build | Release | What to Test for the Release build |
| App Store submission | Release | Pastes What's New into App Store Connect for EN and FR |
| After approval | `release.yml` | The GitHub Release and the wiki mirror |

Open question: who reviews the French text before each release (a native French reviewer is assumed;
how they are engaged is not decided).

## What never appears

- Personal data, document content, customer names or support correspondence.
- Details of a vulnerability before its fix is released everywhere.
- Prices, revenue, targets, or anything else from the redaction rules in
  [repository standards](repository-standards.md#public-and-private-redaction-rules).
- Promises about future releases or dates.
- Claims about competitors.
