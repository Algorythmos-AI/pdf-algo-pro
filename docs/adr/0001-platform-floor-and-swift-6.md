# ADR-0001: iOS 27 floor, Swift 6 and strict concurrency

**Status:** accepted (2026-09-28)

**Context.** The product is new, premium and AI-led. iOS 27 (released 2026-09-14) brings the Foundation Models features we build on (Private Cloud Compute access, image input, third-party model plug-ins) and SwiftUI's new document architecture. Supporting older systems would mean a second code path for every one of them.

**Decision.** Minimum deployment target iOS and iPadOS 27; later macOS 27 and visionOS 27 from the same codebase. Build with Xcode 27. Swift 6 language mode with strict concurrency set to `complete`; warnings are errors in CI. Platform priority is fixed: iPhone, then iPad, then Mac, then visionOS, and visionOS never shapes V1.

**Alternatives considered.** iOS 26 floor (one more year of devices, but fallbacks for every iOS 27 capability, permanently). iOS 18 floor (no Foundation Models at all; the AI pillar would depend on the cloud).

**Consequences.** Reach is limited to devices on iOS 27 at launch. `Assumption:` paying users of premium productivity apps skew to current iOS versions; validated with App Store Connect adoption data before launch. Every framework call can assume iOS 27 APIs, which keeps the codebase small for years. Readiness blocker C2 (Xcode 27 locally and in CI) follows from this decision.

**Pillars served.** PIL-4, PIL-7

**References.** [What's new in the Foundation Models framework, WWDC26](https://developer.apple.com/videos/play/wwdc2026/241/) · [What's new in SwiftUI, WWDC26](https://developer.apple.com/videos/play/wwdc2026/269/)
