# Release management

How PDF Algo Pro gets from merged code to users: the two release trains, how versions and build
numbers are set, the release pull request and its checklist, TestFlight cohorts, phased release,
hotfixes, what "rolling back" means on iOS, and what the `release` workflow does. The step-by-step
procedure is the [App Store submission runbook](process/runbooks/app-store-submission.md); this page is
the policy it follows.

Owner: Release · Reviewed: each release, and each milestone

## Release trains

| Train | Source | Cadence | Destination |
|---|---|---|---|
| Staging | Every merge into `integration` | Continuous | Xcode Cloud Staging workflow → TestFlight internal (the `.staging` app) |
| App Store | The release pull request `integration` → `main` | Roughly monthly | Xcode Cloud Release workflow → TestFlight external → App Store, phased release |
| Hotfix | `hotfix/*` → `main` | When an incident needs it | As the App Store train, with an expedited review |

The roughly monthly App Store cadence is an intent, not a promise. Assumption: a monthly train balances
review overhead against the size of each release for a solo maintainer; it is revisited after the
first three App Store releases. A train is skipped rather than shipped with a failing gate.

Environments and build configurations are described in [environments](process/environments.md).

## Versions and build numbers

- **Marketing version** (`MARKETING_VERSION` in `project.yml`, the app's `CFBundleShortVersionString`):
  SemVer `MAJOR.MINOR.PATCH` ([Semantic Versioning](https://semver.org/spec/v2.0.0.html)). Apple
  requires this value to be period-separated integers
  ([CFBundleShortVersionString](https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundleshortversionstring)),
  so pre-release suffixes never appear in the app.
  - MAJOR: a change users must adapt to, such as a document or library format change or a raised
    minimum OS.
  - MINOR: new capabilities.
  - PATCH: fixes only; every hotfix is a PATCH.
- **Build number** (`CFBundleVersion`): Xcode Cloud's `CI_BUILD_NUMBER`, the number of the current
  build ([Environment variable reference](https://developer.apple.com/documentation/xcode/environment-variable-reference)).
  Nobody edits it. App Store Connect needs each version to use a unique combination of version and
  build number; Xcode Cloud starts at 1 for a new app, and an App Store Connect admin can set the next
  build number if a collision ever needs avoiding
  ([Setting the next build number](https://developer.apple.com/documentation/xcode/setting-the-next-build-number-for-xcode-cloud-builds)).
- **Tags:** `vX.Y.Z` on `main` after App Store approval. The workflow also accepts `X.Y.Z-rc.N`, which
  it publishes as a GitHub pre-release; it needs its own `## [X.Y.Z-rc.N]` CHANGELOG section. When to
  cut an `-rc` tag is an open question (a candidate use: marking the build sent to external TestFlight).

## The release pull request

A release is prepared on `integration` by a `release: prepare X.Y.Z` pull request (branch
`chore/release-X.Y.Z`) that sets `MARKETING_VERSION`, moves `[Unreleased]` into a dated `## [X.Y.Z]`
section and drafts the store text. Then the release pull request is opened from `integration` into
`main`, titled `release: X.Y.Z`, and merged with a **merge commit**. The body carries this checklist:

```markdown
## Release X.Y.Z

### Before merging
- [ ] MARKETING_VERSION is X.Y.Z; CHANGELOG has "## [X.Y.Z] - YYYY-MM-DD" and an empty [Unreleased]
- [ ] Every required check is green, including promotion-guard
- [ ] No open priority:p0 / priority:p1 issue in the milestone, or each is deferred here with a reason
- [ ] Staging build of this commit used on a real iPhone (and iPad if touched)
- [ ] Performance budgets: results linked
- [ ] Golden PDF corpus: no regressions (results linked)
- [ ] OCR accuracy (EN, FR): within thresholds (results linked)
- [ ] AI evaluation suite: within thresholds (results linked)
- [ ] Manual VoiceOver and Dynamic Type pass on the key flows
- [ ] What's New drafted in EN and FR (each at most 4000 characters)
- [ ] App Privacy answers and privacy manifest reviewed if data practices changed
- [ ] Privacy policy and support URLs open and current
- [ ] Merge method: "Create a merge commit"; head branch not deleted

### After merging (before App Store submission)
- [ ] Release build is the merge commit; build number noted
- [ ] External TestFlight for at least 3 days; crash-free sessions at least 99.8%
- [ ] Screenshots and store listing current in EN and FR
- [ ] App Review notes written (consent screens for cloud AI tiers, how to reach new features)
- [ ] Submitted; approved; release.yml run; phased release started
- [ ] integration brought level with main
```

The gates behind each line, and which are automated, are in [quality gates](process/quality-gates.md).
Assumption: the stability line (99.8% crash-free sessions over at least 3 days) is a starting
threshold set by this project, reviewed after the first three releases.

## TestFlight cohorts

| Cohort | Build | Who | Apple limits |
|---|---|---|---|
| Internal | Staging (`.staging` app) | App Store Connect users; today the maintainer | Up to 100 internal testers ([TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview)) |
| External | Release build from `main` | Invited testers in groups | Up to 10,000 external testers; the first build in a group is reviewed by Apple; builds can be tested for up to 90 days ([TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview)) |

Proposed external groups, created when recruiting starts: an early-access group, an accessibility group
(VoiceOver and Switch Control users), and a French-language group for the EN + FR launch. Testers
receive What to Test notes with every build ([changelog strategy](changelog-strategy.md)).

## Phased release

Every App Store release uses phased release unless the Release hat decides otherwise for a SEV1 fix.
Apple releases the update over seven days to users who have automatic updates turned on
([Release a version update in phases](https://developer.apple.com/help/app-store-connect/update-your-app/release-a-version-update-in-phases)):

| Day | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|
| Share of users with automatic updates ([source](https://developer.apple.com/help/app-store-connect/update-your-app/release-a-version-update-in-phases)) | 1% | 2% | 5% | 10% | 20% | 50% | 100% |

Anyone can still update manually from the App Store during the rollout, the release can be paused for
up to 30 days in total, and **Release to All Users** ends the phasing at any time (same source).

During the rollout the Release hat checks crash reports, diagnostics, support email and reviews daily
and pauses at once on any report of data loss, a privacy failure or a new crash affecting many users,
then opens an incident ([incident response](process/runbooks/incident-response.md)).

## Hotfixes

A production problem that cannot wait for the next train is fixed on a `hotfix/*` branch from `main`,
squash-merged into `main`, shipped with an expedited review, tagged as a PATCH, and back-merged into
`integration`. See the [iOS hotfix runbook](process/runbooks/ios-hotfix.md) and
[branching](process/branching.md#hotfix-flow).

## Rolling back on iOS

There is no binary rollback: once a user has installed a version, the App Store cannot put the previous
one back. The equivalents, from least to most drastic:

| Lever | Effect | When |
|---|---|---|
| Do not release | An approved build with manual release stays unreleased; remove it from review or reject it and fix forward | Problem found before release |
| Pause phased release | Stops automatic updates reaching more users; pauses total up to 30 days ([Apple](https://developer.apple.com/help/app-store-connect/update-your-app/release-a-version-update-in-phases)) | Problem found during rollout |
| Kill switch | Turns a feature or AI provider off remotely (designed, [runbook](process/runbooks/kill-switch.md)) | The faulty behaviour sits behind a switch |
| Hotfix with expedited review | Ships the fix; Apple accepts expedited requests for critical bug fixes ([App Review](https://developer.apple.com/distribute/app-review/)) | Any SEV1 or SEV2 needing code |
| Remove from sale | Leaves the App Store within 24 hours; existing users keep the app and still receive updates ([Manage availability](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-for-your-app-on-the-app-store)) | Last resort |

Git tags follow the same rule: a released tag is never moved or deleted (the tag ruleset blocks it); a
mistake is corrected by the next PATCH version.

## The `release` workflow

[`release.yml`](../.github/workflows/release.yml) is run by the Release hat, by hand, after the App
Store has approved the build:

```sh
gh workflow run release.yml --ref main -f version=1.2.0
gh run watch
```

1. **Guard.** The job runs only when dispatched on `main`, in the `release` environment.
2. **Gates.** Version format, tag not yet present, a `## [X.Y.Z]` CHANGELOG section, `MARKETING_VERSION`
   in `project.yml` matching (once the file exists), and `check_docs.py` and `invariants.py` passing.
3. **Release notes.** The CHANGELOG section for the version is extracted and must not be empty.
4. **Tag and GitHub Release.** `gh release create vX.Y.Z --target <commit>` creates the tag on the
   commit the workflow ran on and publishes the release with those notes (a pre-release for `-rc.N`)
   ([About releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)).
5. **Wiki mirror.** `scripts/gh/publish_wiki.py --push` mirrors `docs/` to the wiki.

Two cautions:

- The tag goes on `main`'s head at the moment of dispatch. Dispatch before anything else merges into
  `main`, and check that the head is the commit Xcode Cloud built.
- The workflow's `GITHUB_TOKEN` cannot push to the wiki, so publishing needs a `WIKI_TOKEN` secret in the
  `release` environment: a token that can push to this repository's wiki, scoped as narrowly as GitHub
  allows and set to expire. Without it the workflow prints a warning and skips the wiki, and the release still succeeds.
  The wiki's git repository exists only after its first page has been saved once in the GitHub UI
  ([`publish_wiki.py`](../scripts/gh/publish_wiki.py)); bootstrapping the wiki is a readiness item.

## Release notes

One source, the CHANGELOG, feeds the GitHub Release, TestFlight What to Test, the App Store's What's
New in EN and FR, and the wiki release notes. Who writes what, and when, is in the
[changelog strategy](changelog-strategy.md).

## Records

| Record | Where |
|---|---|
| What changed | [CHANGELOG.md](../CHANGELOG.md) and the GitHub Release |
| Evidence that gates passed | The release pull request |
| What shipped | The `vX.Y.Z` tag and the build number in App Store Connect |
| Current production version and anything deferred | `docs/working-memory.md` |
| Exceptions to a gate | `docs/decision-register.md` |
