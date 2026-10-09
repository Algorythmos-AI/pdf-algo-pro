# Algorythmos alignment

How PDF Algo Pro fits the Algorythmos-AI organisation: which organisation standards it adopts as
they are, which it adapts, and which new standards it introduces, with the reason for each. The
aim is that PDF Algo Pro feels like a first-class citizen of the organisation, and that anything
new it introduces is justified and could be adopted by other repositories.

Owner: Maintainer · Reviewed: each milestone, and when an organisation standard changes

## How this was assessed

The organisation's public repositories were reviewed in September 2026: the `.github` repository
(community defaults, reusable security workflow, labels, templates), the shipping iOS app, the
meeting-notes app, the knowledge-base platform and data repositories, the company website and the
research lab. Organisation standards and decisions are cited only as "org standard (name)" or by
org decision ID ([repository standards](repository-standards.md)); their text is not reproduced
here.

Status key: **Adopt** (used as the organisation does) · **Adapt** (used with a documented change) ·
**New** (introduced here; candidate for the organisation).

## Architectural patterns

| Organisation practice | PDF Algo Pro | Status |
|---|---|---|
| SwiftUI app with `@Observable @MainActor` models and one app container in the environment (shipping iOS app and meeting-notes app) | Same pattern, with protocol-typed services and per-feature models ([ADR-0003](adr/0003-swiftui-observation-and-di.md)) | Adopt |
| Typed routes and one deep-link router for URLs, intents and Spotlight (shipping iOS app) | Same, with a split-view shell and per-document windows ([ADR-0004](adr/0004-navigation-and-multi-window.md)) | Adapt |
| Local Swift package for the core, actor-isolated data access (shipping iOS app) | One package per capability ([ADR-0002](adr/0002-xcodegen-and-modular-spm.md)) | Adapt |
| SwiftData with a versioned schema and a fallback ladder (shipping iOS app) | Same, behind a `LibraryStore` protocol ([ADR-0006](adr/0006-swiftdata-persistence.md)) | Adopt |
| Swift 6 with strict concurrency `complete` (shipping iOS app; the meeting-notes app is migrating) | Same ([ADR-0001](adr/0001-platform-floor-and-swift-6.md)) | Adopt |
| iOS 17 deployment floor (existing apps) | iOS 27 floor ([ADR-0001](adr/0001-platform-floor-and-swift-6.md)) | Adapt: the product is built on iOS 27 AI and document APIs |
| On-device first; no third-party analytics or crash SDKs (shipping iOS app) | Same ([ADR-0012](adr/0012-on-device-observability.md), [ADR-0017](adr/0017-privacy-first-telemetry.md)) | Adopt |
| Server-side verification of StoreKit transactions; the client never sets a "Pro" flag (meeting-notes app) | Same once the relay exists; StoreKit 2 on device before that ([ADR-0011](adr/0011-storekit-2-monetisation.md)) | Adopt |
| Cloud AI only behind the product's own backend; personal data scrubbed before model calls (meeting-notes app) | On-device and Private Cloud Compute first; Claude via App Attest in beta and a relay before GA ([ADR-0009](adr/0009-tiered-ai-and-consent.md)) | Adapt |

## Naming conventions

| Organisation practice | PDF Algo Pro | Status |
|---|---|---|
| Repository names in lowercase kebab-case; `<product>` for a product repository (org standard (naming)) | `pdf-algo-pro` (renamed from `PDF-Algo-Pro`) | Adopt |
| One-line description of at most 120 characters that starts with the product name and names no AI tool (org standard (naming); org decision D-015) | "PDF Algo Pro: native PDF reader, editor and scanner for iPhone, iPad and Mac — private and offline-first" (106 characters) | Adopt |
| `<name>-ops` / `<name>-source` for private companions (org standard (naming)) | A private companion repository for confidential business documents; its `<name>-private` shape is proposed to the organisation ([ADR-0019](adr/0019-public-private-documentation-split.md)) | New |
| `com.algorythmos.<product>` bundle identifiers and App Groups (meeting-notes app) | `com.algorythmos.pdfalgopro`, `group.…`, `iCloud.…` ([ADR-0015](adr/0015-identifiers-and-signing.md)) | Adopt, now written down |
| Branch names `<type>/<description>` and Conventional Commit pull request titles | Same, enforced by the `pr-title` check | Adopt |

## CI/CD standards

| Organisation practice | PDF Algo Pro | Status |
|---|---|---|
| Reusable secret-scan workflow from the organisation's `.github` repository, pinned to a commit | Called from `ci.yml` as the `secrets` job | Adopt |
| Workflows with read-only default permissions, pinned runners and timeouts | Same in all five workflows | Adopt |
| Third-party actions pinned to commit SHAs (applied unevenly across repositories) | Every action pinned to a SHA | Adopt, applied fully |
| A `changes` job so required checks always report while macOS minutes are spent only when needed (meeting-notes app) | Same for the `ios` and `codeql (swift)` jobs | Adopt |
| Pinned Xcode that fails when missing; pinned, checksum-verified XcodeGen; `Package.resolved` drift gate (meeting-notes app) | Same, for Xcode 27 and XcodeGen 2.46.0 | Adopt |
| Xcode Cloud for signed builds, stamping `CI_BUILD_NUMBER` (meeting-notes app) | Same ([ADR-0013](adr/0013-ci-cd.md)) | Adopt |
| Rulesets as code with a dry-run apply script (knowledge-base platform) | Same script, reused | Adopt |
| Dependabot from the organisation template | Same; `github-actions` now, `swift` added with the first `Package.swift` | Adopt |
| CodeQL (one repository only) | `codeql.yml` for workflows now and Swift when code exists | New for iOS: security analysis on every app |
| Four named workflows | `ci.yml`, `codeql.yml`, `release.yml`, `dependency-review.yml` | New (structure requested for this product) |

## Documentation standards

| Organisation practice | PDF Algo Pro | Status |
|---|---|---|
| README header with Status, Owner, Runs at, Run locally, Context (org standard (onboarding)) | Same | Adopt |
| Numbered ADRs with a status line and Context / Decision / Consequences (knowledge-base platform) | Same, plus Alternatives and Pillars sections ([ADR index](adr/README.md)) | Adapt |
| Append-only decision log with ID, date, decision, who, why, consequences (org standard (decision log)) | Same format in the [decision register](decision-register.md) | Adopt |
| Keep a Changelog with `[Unreleased]` | Same; one source feeds four audiences ([changelog strategy](changelog-strategy.md)) | Adapt |
| Runbooks in the repository | `docs/process/runbooks/` | Adopt |
| `docs/` mirrored to the GitHub wiki by a script (research lab) | Same script, adapted so curated pages lead ([wiki plan](wiki-plan.md)) | Adapt |
| Backlog as code synced to milestones and issues (research lab) | `planning/backlog.yaml` | Adopt |
| `CLAUDE.md` as an import of `AGENTS.md` (research lab) | Same | Adopt |
| Performance-budget and SLO tables (meeting-notes app) | [Performance budgets](performance-budgets.md), [operations](operations.md) | Adopt |

## Security standards

| Organisation practice | PDF Algo Pro | Status |
|---|---|---|
| Private vulnerability reporting; email with a `SECURITY: <repository>` subject; acknowledgement within five business days (organisation default) | Same, with the product's scope | Adopt |
| Secret scanning and push protection on public repositories | On | Adopt |
| No secrets in files; Team ID injected at build time (shipping iOS app's pattern) | Same | Adopt |
| Organisation data classes (public, internal, confidential, restricted) | Applied to every data type in [data classification](data-classification.md) | Adopt |
| Privacy manifest kept in step with API use by automated gates (shipping iOS app) | `invariants` gate | Adopt |
| Nothing from private repositories in public places; no company records (org standard (agent rules)) | Redaction rules and public-safety checks ([repository standards](repository-standards.md)) | Adopt |
| Third-party SDK review | Mandatory ADR with privacy manifest, telemetry, licence and exit plan | New |
| Third-party AI consent | Named-provider consent under Guideline 5.1.2(i) ([AI governance](ai-governance.md)) | New |

## Testing standards

| Organisation practice | PDF Algo Pro | Status |
|---|---|---|
| "Add or update tests for behaviour you change"; CI green to merge | Same | Adopt |
| XCTest; accessibility, contrast and performance-budget tests (shipping iOS app) | Swift Testing for unit tests; XCTest for UI and performance ([ADR-0014](adr/0014-testing-strategy-and-coverage.md)) | Adapt |
| No coverage threshold anywhere | At least 80% line coverage, overall and per target | New |
| No snapshot testing | Test-only `swift-snapshot-testing` ([ADR-0018](adr/0018-snapshot-testing-test-only-dependency.md)) | New |
| Synthetic test data | Synthetic golden PDF corpus; real documents blocked by the `invariants` gate | Adopt, enforced |

## Deployment standards

| Organisation practice | PDF Algo Pro | Status |
|---|---|---|
| Apps use `main` only; `integration` → `main` for deployed platforms with staging (org standard (onboarding)) | `integration` → `main` for an app ([ADR-0016](adr/0016-two-branch-model.md)); recorded as org decision D-023 | Adapt (recorded exception) |
| Human approval for production deployments and releases (org standard (agent rules)) | Release pull request, manual `release.yml`, App Store submission by a person ([SUPERVISION](../.github/SUPERVISION.md)) | Adopt |
| No binary rollback on iOS: pause the phased release, hotfix with expedited review (shipping iOS app) | Same, plus a remote kill switch ([release management](release-management.md)) | Adopt |
| Tags `vX.Y.Z` on `main` | Same, cut after App Store approval | Adopt |

## Brand

| Organisation practice | PDF Algo Pro | Status |
|---|---|---|
| Endorsed brand: product name first, "Built by Algorythmos"; lead with trust and outcomes | Same | Adopt |
| Company palette (violet and blue family) and website tokens with WCAG AA contrast | The cyan marks the intelligence layer and the company mark keeps its colours; the app's accent is the product's own red, not the company violet ([PAP-047](decision-register.md), [design system](design-system.md)) | Differs, recorded |
| No copy implying a team (single-person company) | Governance written as roles ("hats") | Adopt |

## New standards introduced

Each is introduced because the organisation has no equivalent, and each is offered back to the
organisation:

1. **Coverage threshold** (80%, [ADR-0014](adr/0014-testing-strategy-and-coverage.md)): premium,
   long-lived software needs a floor; enforced by script.
2. **Third-party SDK governance**: an ADR, privacy manifest review, telemetry audit and NOTICE entry
   before any dependency ships.
3. **AI provider consent standard**: named-provider, revocable consent before any content leaves
   the device.
4. **Identifier scheme written down**: bundle, App Group and iCloud identifiers per product.
5. **CodeQL for Swift** on app repositories.
6. **Public/private documentation split** with a `<name>-private` companion.
7. **Swift Testing and snapshot testing** as the default for new app code.
8. **Evidence rule** for planning documents: cite or label as an assumption.

## Catalog registration

The catalog entry for PDF Algo Pro (org standard (catalog)) is pending owner review; its state is
tracked in [working memory](working-memory.md). For this repository it records an app, planned,
public for now with an intended visibility of private, default branch `integration`, proprietary
licence, deploying to TestFlight and the App Store. The branch-model exception is org decision
D-023; the `<name>-private` naming shape is proposed to the organisation in
[ADR-0019](adr/0019-public-private-documentation-split.md).

## Check yourself

After 30 minutes with these documents, anyone new should be able to answer:

1. **What is PDF Algo Pro?** A native Apple PDF app whose edge is private, offline, on-device
   document intelligence ([product positioning](product-positioning.md)).
2. **Where does it run?** iPhone and iPad through TestFlight and the App Store; no deployed service
   today ([README](../README.md)).
3. **Does it work today?** Not yet: it is in planning; implementation waits for the
   [readiness gate](readiness-review.md).
4. **Who owns it, and who do you ask?** The maintainer, through the `@Algorythmos-AI/maintainers` GitHub team (one person today); roles are listed in
   [SUPERVISION](../.github/SUPERVISION.md).
5. **How do you run it locally?** There is nothing to run yet; once code lands, the README's
   "Run locally" row explains `xcodegen generate` and the Xcode 27 requirement.
6. **Why is the repository public, and what does that mean for you?** Public for free CI minutes
   under org decision D-002, intended to become private: never commit anything from private
   repositories, company records, prices or targets ([repository standards](repository-standards.md)).
7. **What is the branch model?** `integration` (default, staging) into `main` (production)
   ([branching](process/branching.md)).
8. **Where are decisions recorded?** Architecture in [ADRs](adr/README.md); product and process in
   the [decision register](decision-register.md).
9. **What must never be built?** The [non-goals](non-goals.md).
10. **What is happening right now?** [Working memory](working-memory.md).
