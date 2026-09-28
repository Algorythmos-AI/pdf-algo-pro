# ADR-0004: Split-view navigation, typed routes and multi-window

**Status:** accepted (2026-09-28)

**Context.** PDF Algo Pro is entered from many surfaces (Spotlight, widgets, controls, intents, Handoff, URLs) and must scale from iPhone to iPad and Mac windows.

**Decision.** `NavigationSplitView` shell; typed `Route` enums in a `NavigationPath` per column, restored with `@SceneStorage`; one deep-link router for every entry point; documents in their own scenes with `WindowGroup(for: DocumentID.self)`; one presentation enum per scene. Layouts respond to size, never device type. The router only navigates: actions always need explicit user intent.

**Alternatives considered.** Coordinator objects (UIKit-era). Tab navigation (fits less well for a library that grows on iPad and Mac).

**Consequences.** Every entry point is testable through one router. Routes must stay `Codable`. Multi-window works on iPad and Mac without extra architecture.

**Pillars served.** PIL-1, PIL-7

**References.** [What's new in SwiftUI, WWDC26](https://developer.apple.com/videos/play/wwdc2026/269/)
