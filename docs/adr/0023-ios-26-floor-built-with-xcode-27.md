# ADR-0023: iOS 26 floor, built with the Xcode 27 SDK

**Status:** accepted (2026-09-30)

**Context.** ADR-0001 set the minimum OS to iOS and iPadOS 27 and the toolchain to Xcode 27. When Xcode 27 could not be installed, PAP-029 set a temporary iOS 26 floor with Xcode 26, and the internal TestFlight builds use it. iOS 27 shipped on 2026-09-14. Many phones will stay on iOS 26 for months, and devices without Apple Intelligence are part of the market ([product positioning](../product-positioning.md)). Every capability the V1 core needs is available on iOS 26:
- PDFKit;
- Vision document recognition (`RecognizeDocumentsRequest`);
- the on-device Foundation Models framework;
- `BGContinuedProcessingTask`;
- Controls;
- App Intents in Swift packages.

A few iOS 27 capabilities add value but are not required for the core:
- Private Cloud Compute through `PrivateCloudComputeLanguageModel`;
- the `LanguageModel` protocol;
- `SpotlightSearchTool`;
- the Evaluations framework;
- the `ReadableDocument` and `WritableDocument` protocols named in ADR-0005.

**Decision.**
- **Floor.** The deployment target is iOS 26.0 in `project.yml` and in every `Package.swift`.
- **Toolchain.** The app is built with the Xcode 27 SDK, in CI and in Xcode Cloud.
- **iOS 27 APIs** are used only behind `#available(iOS 27, *)`, with an iOS 26 path that works. For Private Cloud Compute on iOS 26, that path is the on-device tier or the "too long for this device" message (FR-AI-005).
- **Sequencing.** The move from Xcode 26 to Xcode 27 is one pull request. It:
  - pins the new toolchain in `ci.yml`;
  - adds an iOS 27 simulator job next to the iOS 26 one;
  - re-records every snapshot reference, because the new SDK can change how iOS 26 renders;
  - checks every iOS 27 API this record names against the SDK headers.

  No iOS 27 code merges before it.
- **Dependencies.** A package whose minimum is iOS 27 cannot be linked into the app. Where one is needed (for example `ClaudeForFoundationModels`), we write our own client over the iOS 26 Foundation Models types instead.

**Alternatives considered.**
- **iOS 27 floor (ADR-0001 unchanged).** It excludes phones that haven't updated, and devices that cannot run iOS 27, with nothing in the core that requires it.
- **Staying on Xcode 26.** App Store Connect will require the current SDK. It would also block the iOS 27 capabilities entirely.

**Consequences.**
- Supersedes the floor in ADR-0001; Swift 6 and strict concurrency are unchanged. Also supersedes PAP-001 and PAP-029.
- Amends ADR-0005: the iOS 27 document protocols are adopted behind `#available`.
- The PRD constraints and FR-ONB-006 name iOS 26.
- Threat T-01 covers both runtimes.
- The performance baseline device becomes the oldest iPhone that supports iOS 26, without Apple Intelligence (`Assumption:` iPhone 11, confirmed against Apple's compatibility list before the first measurement).
- Tests and evaluations run on both runtimes and both on-device models: snapshots per runtime, and AI evaluation on the iOS 26 and iOS 27 models.
- Readiness blocker C2 closes when the toolchain pull request is green in CI and Xcode Cloud. Until the development Mac has space for Xcode 27, code that uses iOS 27 APIs is compile-checked only in CI.

**Pillars served.** PIL-5, PIL-6, PIL-7

**References.** [ADR-0001](0001-platform-floor-and-swift-6.md) · [ADR-0005](0005-document-storage-and-identity.md) · [Decision register](../decision-register.md) (PAP-029, PAP-031) · [Swift `available` attribute](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/attributes/#available) · [Upcoming requirements](https://developer.apple.com/news/upcoming-requirements/)
