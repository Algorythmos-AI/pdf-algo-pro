# Environments

The places a build of PDF Algo Pro runs, which branch and build configuration feed each one, who can
use it, how signing identity and secrets reach the build without entering git, and which services
each build may talk to. The Staging set-up below is being put in place for the first internal
TestFlight build ([#47](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/47), PAP-030); anything
not yet decided is listed under [open questions](#open-questions).

Owner: Release · Reviewed: each milestone

## Summary

| Environment | Source | Build configuration | Bundle identifier | Built by | Used by |
|---|---|---|---|---|---|
| Local | Any branch | Debug | See [open questions](#open-questions) | Xcode on the maintainer's Mac | The maintainer; simulators and registered devices |
| CI | Every pull request and push | Debug, unsigned | — | GitHub Actions `ios` job | Nobody; checks only |
| Staging | `integration` | Staging | `com.algorythmos.pdfalgopro.staging` | Xcode Cloud, Staging workflow | TestFlight internal testers |
| Production | `main` | Release | `com.algorythmos.pdfalgopro` | Xcode Cloud, Release workflow | TestFlight external testers, then the App Store with phased release |

Identifiers follow ADR-0015 (identifiers and signing): App Group
`group.com.algorythmos.pdfalgopro`, iCloud container `iCloud.com.algorythmos.pdfalgopro`, URL scheme
`pdfalgopro://`.

## Local (Debug)

- Built and run from Xcode 27 on the maintainer's Mac, after `xcodegen generate` from `project.yml`
  (the `.xcodeproj` is generated, never committed; see [`.gitignore`](../../.gitignore)).
- Debug keeps the `DEBUG` compilation condition, so `print(` is allowed only inside `#if DEBUG`
  blocks (enforced by the `invariants` job; see [quality gates](quality-gates.md)).
- In-app purchases run against a local StoreKit configuration or the App Store sandbox; Apple states
  that development-signed apps built from Xcode use the sandbox environment
  ([Testing In-App Purchases with sandbox](https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox)).
- CloudKit uses the container's development environment while the schema is being built; the schema
  is deployed to production before release
  ([Deploying an iCloud container's schema](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema)).
- Test documents are synthetic or licence-clean; real documents never enter the repository
  ([AGENTS.md](../../AGENTS.md), hard rule 6).

## CI (GitHub Actions)

The `ios` job in [`ci.yml`](../../.github/workflows/ci.yml) builds and tests on a macOS runner. The
simulator test build is signed ad hoc ("Sign to Run Locally", `CODE_SIGN_IDENTITY=-`), because the
app-hosted tests use the Keychain, which refuses an unsigned app. The Staging device build is unsigned
(`CODE_SIGNING_ALLOWED=NO`). Neither needs a Team ID, certificate or profile, and the job holds no
secrets. It is not an environment anyone uses; it exists to run the gates in
[quality gates](quality-gates.md).

## Staging (`integration`)

The Staging workflow is being set up for the first internal TestFlight build (readiness M5, PAP-030).

- The `PDFAlgoProStaging` scheme archives the Staging configuration. Xcode Cloud starts it manually
  until build 1, then nightly from `integration`, rather than on every merge: 25 compute hours a month
  are included, and a night's work can be a dozen merges
  ([Xcode Cloud workflow reference](https://developer.apple.com/documentation/xcode/xcode-cloud-workflow-reference)).
  The archive action uploads for internal testing only.
- The Xcode project is generated, not committed (ADR-0002), so
  [`ci_scripts/ci_post_clone.sh`](../../ci_scripts/ci_post_clone.sh) installs the pinned XcodeGen
  (checksum-verified) and generates it after the clone, before packages resolve
  ([Writing custom build scripts](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts)).
- The Staging app is named "PDF Algo β" on the home screen and answers `pdfalgopro-staging://` links,
  so it installs beside the App Store app without taking its links (`APP_DISPLAY_NAME` and
  `APP_URL_SCHEME` in `project.yml`).
- The Staging configuration is optimised like Release, so testers exercise what will ship, but it
  carries the `.staging` bundle suffix so it installs beside the App Store app.
- A different bundle identifier means a separate App Store Connect app record: each app record is
  tied to one bundle ID
  ([Add a new app](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app)).
  The Staging record is used for internal TestFlight only and is never submitted for review.
- Internal testers are App Store Connect users; Apple allows up to 100
  ([TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview)).
  Today that is the maintainer.
- Purchases in TestFlight builds use the sandbox, so testers are not charged
  ([Testing In-App Purchases with sandbox](https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox)).
- "What to Test" notes come from `TestFlight/WhatToTest.<locale>.txt` files that Xcode Cloud picks up
  automatically ([Including notes for testers](https://developer.apple.com/documentation/xcode/including-notes-for-testers-with-a-beta-release-of-your-app));
  see the [changelog strategy](../changelog-strategy.md).

## Production (`main`)

- The release pull request (merge commit) or a hotfix (squash) lands on `main` and starts the Xcode
  Cloud Release workflow, which archives with the Release configuration.
- The build goes to TestFlight external testing first. Apple requires a clean build for external
  distribution from Xcode Cloud, and the first build added to an external group goes through App Review
  ([Xcode Cloud workflow reference](https://developer.apple.com/documentation/xcode/xcode-cloud-workflow-reference),
  [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview)).
- After the release gates pass, the same build is submitted for App Store review and released with
  phased release ([release management](../release-management.md),
  [App Store submission runbook](runbooks/app-store-submission.md)).
- **Claude tier.** In the Release configuration the Claude tier is off in App Store builds until V2
  general availability; before then it is available only in the external TestFlight beta, and only to
  testers who opt in ([ADR-0009](../adr/0009-tiered-ai-and-consent.md),
  [AI governance](../ai-governance.md)).
- App Store builds can reach only the CloudKit production environment
  ([Deploying an iCloud container's schema](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema)).
  Assumption: TestFlight builds also use the production environment; verified on the first Staging
  build.

## Build configurations

| Setting | Debug | Staging | Release |
|---|---|---|---|
| Used for | Local development, CI | Internal TestFlight | External TestFlight and the App Store |
| Optimisation | None | As Release | Whole-module, optimised for speed |
| `DEBUG` condition | Yes | No | No |
| Bundle identifier suffix | See open questions | `.staging` | None |
| Swift language mode | Swift 6, strict concurrency `complete` (ADR-0001) | Same | Same |
| Signing | Automatic, maintainer's local identity | Xcode Cloud managed | Xcode Cloud managed |
| Build number | Local placeholder | `CI_BUILD_NUMBER` | `CI_BUILD_NUMBER` |
| Logging | `OSLog`, verbose categories allowed | `OSLog` with privacy redaction | `OSLog` with privacy redaction |
| Claude tier | When opted in | When opted in (internal TestFlight) | Off in App Store builds until V2 general availability; before then only in the external TestFlight beta, when opted in |

Build numbers come from Xcode Cloud's `CI_BUILD_NUMBER` ("the number of the current build")
([Environment variable reference](https://developer.apple.com/documentation/xcode/environment-variable-reference));
the marketing version is SemVer in `project.yml` (see [release management](../release-management.md#versions-and-build-numbers)).

## Signing identity and secrets

Nothing secret is committed ([AGENTS.md](../../AGENTS.md), hard rule 5). The Apple Team ID is
treated as confidential for this public repository and is injected at build time.

| Where the build runs | Team ID and signing | Secrets |
|---|---|---|
| Local | [`Config/Base.xcconfig`](../../Config/Base.xcconfig) includes the git-ignored `Config/Team.xcconfig` when it exists; for a device build, create it with one line, `DEVELOPMENT_TEAM = <Team ID>`. Simulator builds need nothing. | A gitignored `.env`; `.env.example` holds placeholders only. |
| GitHub Actions | None: builds are unsigned. | Only the `release` environment's `WIKI_TOKEN` ([release workflow](../../.github/workflows/release.yml)). |
| Xcode Cloud | Xcode Cloud manages signing and gives build scripts the Team ID as `CI_TEAM_ID` ([Environment variable reference](https://developer.apple.com/documentation/xcode/environment-variable-reference)); `ci_post_clone.sh` writes it into `Config/Team.xcconfig`, which is never committed. | Workflow environment variables marked **Secret**, which are redacted from logs ([Xcode Cloud workflow reference](https://developer.apple.com/documentation/xcode/xcode-cloud-workflow-reference)). |

Signing material (`*.p8`, `*.p12`, `*.mobileprovision`, `*.cer`) is excluded by `.gitignore`, and the
`secrets / Secret scan` check blocks credentials in pull requests. No AI provider key is ever embedded
in the app: in beta the Claude tier authenticates with App Attest, and before general availability a
relay (`pdf-algo-pro-backend`) holds provider credentials server-side (ADR-0009).

## What each environment may talk to

Today the product is on-device only. Networking is allowed in three packages only (`Intelligence`,
`Commerce`, `Telemetry`), which the `invariants` job enforces once Swift sources exist.

| Destination | Local | Staging | Production | Notes |
|---|---|---|---|---|
| On-device Apple models (`SystemLanguageModel`) | Yes | Yes | Yes | No network. Availability depends on device and region support for Apple Intelligence ([SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)). |
| iCloud Drive (documents) and CloudKit private database (library metadata) | Development environment | Production | Production | The user's own data only (ADR-0005, ADR-0006). |
| App Store (StoreKit 2) | Sandbox or local configuration | Sandbox | Production | ADR-0011. |
| Apple Private Cloud Compute | Yes, when opted in | Yes, when opted in | Yes, when opted in | Opt-in, with consent that names the provider and the data (ADR-0009). |
| Anthropic (Claude tier) | Yes, when opted in | Yes, when opted in | Off in App Store builds until V2 general availability; before then only in the external TestFlight beta, when opted in | Beta only, App Attest, workspace spend caps until general availability ([ADR-0009](../adr/0009-tiered-ai-and-consent.md)); see the [failover runbook](runbooks/ai-provider-failover.md). |
| CloudKit public database (remote configuration, kill switch) | Development environment | See open questions | Production | Designed, not yet built: [kill switch runbook](runbooks/kill-switch.md). |
| `pdf-algo-pro-backend` relay | Later | Later (staging endpoint) | Later (production endpoint) | Required before the Claude tier reaches general availability. |
| Third-party analytics or crash SDKs | Never | Never | Never | MetricKit and `OSLog` only (ADR-0012). |

Diagnostics and telemetry never include document content, personal data or business data
(ADR-0017).

## Open questions

1. **Debug bundle identifier.** ADR-0015 fixes only the Staging suffix. A `.debug` suffix would let a
   development build sit beside the App Store build on the same device; decide in a new ADR.
2. **Staging App Group and iCloud container.** Whether Staging shares
   `group.com.algorythmos.pdfalgopro` and `iCloud.com.algorythmos.pdfalgopro` or gets `.staging`
   variants. Separate containers keep tester data and remote configuration apart from production.
3. **Remote configuration for Staging.** Whether Staging reads its own records in the public database
   or a separate container (depends on question 2).
4. **Provider workspaces.** Whether Staging and Production use separate AI provider workspaces, so that
   each has its own spend cap.
5. **Staging identity on the device.** Whether Staging uses a distinct display name and icon so
   testers can tell the builds apart.
