# ADR-0003: SwiftUI, Observation and environment-based dependency injection

**Status:** accepted (2026-09-28)

**Context.** The UI must feel native on four platforms and stay testable for years without a framework at its core.

**Decision.** SwiftUI for all screens; UIKit only inside adapters in the package that owns the capability. Feature models are `@Observable` final classes on `@MainActor`; shared and long-running work lives in actors returning `Sendable` values. Services are protocols in `Core`; a composition-only `AppContainer` places live implementations in the SwiftUI environment with `@Entry` keys; previews and tests use fake containers. No third-party DI or architecture framework.

**Alternatives considered.** The Composable Architecture (third-party core dependency). `ObservableObject` (coarser invalidation). Third-party DI containers. UIKit-first.

**Consequences.** Fine-grained view updates on large documents; compile-time data-race safety; no framework lock-in. Cross-feature coordination goes through services and the router rather than a global store.

**Pillars served.** PIL-7, supports all

**References.** [What's new in SwiftUI, WWDC26](https://developer.apple.com/videos/play/wwdc2026/269/) · [Observation](https://developer.apple.com/documentation/observation)
