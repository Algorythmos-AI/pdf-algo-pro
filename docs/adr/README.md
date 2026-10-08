# Architecture decision records

Each ADR records one decision that shapes PDF Algo Pro: its context, the decision, the
alternatives considered and the consequences. They are numbered in the order they were written
and are not edited after acceptance; a later decision that changes course gets its own number and
says which ADR it supersedes. The [iOS architecture review](../ios-architecture-review.md) explains
them together; product and process decisions are logged in the [decision register](../decision-register.md).

Owner: Architecture · Reviewed: when a decision changes

| ADR | Decision | Status |
|---|---|---|
| [ADR-0001](0001-platform-floor-and-swift-6.md) | iOS 27 floor, Swift 6 and strict concurrency | accepted; floor superseded by ADR-0023 |
| [ADR-0002](0002-xcodegen-and-modular-spm.md) | XcodeGen project and modular Swift packages | accepted |
| [ADR-0003](0003-swiftui-observation-and-di.md) | SwiftUI, Observation and environment-based dependency injection | accepted |
| [ADR-0004](0004-navigation-and-multi-window.md) | Split-view navigation, typed routes and multi-window | accepted |
| [ADR-0005](0005-document-storage-and-identity.md) | Files as the source of truth, in iCloud Drive | accepted |
| [ADR-0006](0006-swiftdata-persistence.md) | SwiftData for the rebuildable library index | accepted |
| [ADR-0007](0007-pdf-sdk-boundary-and-vendor-selection.md) | Commercial PDF SDK behind our own boundary | proposed |
| [ADR-0008](0008-ocr-and-scanning.md) | On-device scanning and structured OCR | accepted |
| [ADR-0009](0009-tiered-ai-and-consent.md) | Tiered AI with on-device first and consent for every cloud tier | accepted |
| [ADR-0010](0010-search.md) | Core Spotlight for search, with an on-device index as fallback | accepted |
| [ADR-0011](0011-storekit-2-monetisation.md) | StoreKit 2 subscriptions without a third-party SDK | accepted; plans and paywall placement superseded by ADR-0026 |
| [ADR-0012](0012-on-device-observability.md) | On-device observability without third-party SDKs | accepted |
| [ADR-0013](0013-ci-cd.md) | GitHub Actions for gates, Xcode Cloud for signed builds | accepted |
| [ADR-0014](0014-testing-strategy-and-coverage.md) | Testing strategy and 80% coverage gate | accepted |
| [ADR-0015](0015-identifiers-and-signing.md) | Identifiers and signing | accepted |
| [ADR-0016](0016-two-branch-model.md) | Two-branch model: integration and main | accepted |
| [ADR-0017](0017-privacy-first-telemetry.md) | Privacy-first product telemetry | accepted |
| [ADR-0018](0018-snapshot-testing-test-only-dependency.md) | Snapshot testing as a test-only dependency | accepted |
| [ADR-0019](0019-public-private-documentation-split.md) | Public and private documentation, and the repository family | accepted |
| [ADR-0020](0020-prompt-versioning-and-eval-gates.md) | Prompts as versioned, evaluated artefacts | accepted |
| [ADR-0021](0021-ai-provider-routing-and-failover.md) | AI provider routing and failover | accepted |
| [ADR-0022](0022-apple-first-capability-baseline.md) | Apple-first capability baseline | accepted |
| [ADR-0023](0023-ios-26-floor-built-with-xcode-27.md) | iOS 26 floor, built with the Xcode 27 SDK (supersedes the floor in ADR-0001) | accepted |
| [ADR-0024](0024-remote-configuration-package.md) | Remote configuration in its own package, read from the CloudKit public database | accepted |
| [ADR-0025](0025-native-text-editing-for-the-safe-subset.md) | Native text editing for the documents where it is safe, behind our own boundary | accepted |
| [ADR-0026](0026-first-run-subscription-offer-and-plans.md) | A closable subscription offer at the end of first run, weekly and annual plans, and a free allowance (supersedes the plans and paywall placement in ADR-0011) | accepted; amended by PAP-049 and PAP-052 |

## Writing one

Copy the newest record, take the next number, keep the headings (Context, Decision, Alternatives
considered, Consequences, Pillars served, References), and state the status with its date:
`**Status:** proposed (YYYY-MM-DD)`, then `accepted`, `superseded by ADR-NNNN` or `rejected`.
Add the row to the table above in the same pull request.
