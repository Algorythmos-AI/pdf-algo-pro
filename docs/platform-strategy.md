# Platform strategy

Which Apple platforms PDF Algo Pro serves, in what order, what they share, and what each one gets
that the others do not. The order is fixed so that later platforms never distort the first.

Owner: Product and Architecture · Reviewed: at each platform launch decision

## Priority

| Priority | Platform | Role | Ships in |
|---|---|---|---|
| **P1** | iPhone | Primary: capture (scan), quick reading, answers on the go | MVP, V1 |
| **P2** | iPad | Deep work: long-form reading, annotation with Apple Pencil, side-by-side documents | V2 (adaptive layouts from the MVP) |
| **P3** | Mac | Desktop document work: large screens, keyboard, Finder | V2 (work starts only when the Mac entry criteria below are met) |
| **P4** | Apple Vision Pro | Compatible iPad app first; native only with evidence | After Mac |

**Rules.** visionOS never shapes V1 decisions. The only cross-platform rule in V1 is that UIKit
stays inside adapters (which the Mac target needs anyway). Every screen is built adaptive from
the first line of code (size classes and window size, never device checks), so iPad and Mac are
additions rather than rewrites.

**Rationale.** iPhone is where documents arrive (email, messages, the camera) and where the
competitors' onboarding already meets users; iPad and Mac are where the longest sessions happen.
Shipping iPhone first proves the core loop; the adaptive architecture keeps the second and third
platforms cheap.

**Alternatives considered.** iPad first (strong for annotation, but a smaller audience for the
capture-and-answer loop). All platforms at once (quality spread too thin for one maintainer).
Mac Catalyst for the Mac (faster, but not native; see the architecture review).

## Shared code matrix

`Shared` = same code on the platform · `Adapter` = shared logic, platform-specific view or API ·
`n/a` = not used on that platform.

| Package | iPhone | iPad | Mac | visionOS |
|---|---|---|---|---|
| Core | Shared | Shared | Shared | Shared |
| DesignSystem | Shared | Shared | Adapter (Mac controls, pointer, menus) | Adapter (materials, ornaments) |
| DocumentStore | Shared | Shared | Shared | Shared |
| PDFEngine | Adapter (page view) | Adapter | Adapter (vendor Mac support required) | Adapter (vendor support to confirm) |
| Scanning | Shared (document camera) | Shared | Adapter (Continuity Camera) | n/a at first |
| OCR | Shared | Shared | Shared | Shared |
| Intelligence | Shared | Shared | Shared (Foundation Models on macOS 27) | Shared (visionOS 27) |
| Search | Shared | Shared | Shared | Shared |
| Commerce | Shared | Shared | Shared (Mac App Store) | Shared |
| Telemetry | Shared | Shared | Shared | Shared |
| Features/* | Shared | Shared + iPad additions | Shared + Mac additions | Shared (compatible app) |

`Assumption:` 85–90% of code is shared across iPhone, iPad and Mac with this structure; measured by
line counts per package when the Mac target starts.

## iPhone (P1)

- Scan from anywhere: Control Center control, widget, Share extension, the camera in the app.
- One-handed reading; quick answers with page citations; summaries.
- App Intents for Siri and Shortcuts ("Summarise the last PDF I downloaded").
- Resizable layouts: iOS 27 lets iPhone apps resize, for example with iPhone Mirroring and on iPad
  ([What's new in SwiftUI, WWDC26](https://developer.apple.com/videos/play/wwdc2026/269/)).

**Exit criteria for V1:** the V1 requirements in the [PRD](prd.md) met; performance budgets met on
the reference iPhones; crash-free sessions at least 99.8% over the TestFlight external beta.

## iPad (P2)

- Three-column `NavigationSplitView`; multiple windows and Stage Manager (`WindowGroup` per document).
- Apple Pencil through PencilKit: annotation, signing, hover preview, and squeeze and barrel roll
  on Apple Pencil Pro ([PencilKit](https://developer.apple.com/documentation/pencilkit)).
- Keyboard shortcuts and the iPadOS menu bar (`.commands`); pointer support.
- Drag and drop of pages and documents between apps (`Transferable`).
- Side-by-side compare of two documents.

**Exit criteria:** every iPhone feature works in every iPad window size; the iPad additions above
shipped; an iPad accessibility pass (keyboard-only navigation, VoiceOver) complete.

## Mac (P3)

- A native multiplatform SwiftUI target (not Catalyst) with Mac conventions: menus, multiple
  windows, keyboard-first editing, Finder integration.
- Scanning through Continuity Camera from a nearby iPhone.
- Foundation Models available on macOS 27 for the on-device tier
  ([What's new in the Foundation Models framework, WWDC26](https://developer.apple.com/videos/play/wwdc2026/241/)).
- Distribution through the Mac App Store with the same subscription (universal purchase).

**Entry criteria (before starting):** the chosen PDF SDK supports macOS with feature parity for
the V1 feature set; the V2 iPad experience stable; evidence of demand (support requests, survey
results).

## Apple Vision Pro (P4)

- First: make the iPad app available on Apple Vision Pro as a compatible app (no new code).
- Later, only with evidence: a native visionOS target for reading and reviewing in windows with
  ornaments. No 3D or immersive features are planned.

**Entry criteria for a native target:** compatible-app usage data and requests justify it; the PDF
SDK supports visionOS; PencilKit and other framework availability confirmed per package.

## Apple Intelligence

Apple Intelligence is a cross-platform layer rather than a platform, and PDF Algo Pro uses it on
every platform that supports it:

| Capability | Use |
|---|---|
| Foundation Models (on device) | Default tier for summaries, answers with citations and structured extraction ([ADR-0009](adr/0009-tiered-ai-and-consent.md)) |
| Private Cloud Compute | Opt-in tier for long documents and harder reasoning |
| App Intents | Document actions for Siri, Shortcuts and Spotlight |
| Writing Tools | Available in the app's text fields (notes, comments, form text) |
| Visual Intelligence | Recognising documents and text in what the camera sees |

On devices without Apple Intelligence, AI features explain what they need and the app offers the
non-AI tools only until V2; the rest of the app is unaffected. Private Cloud Compute also needs
Apple Intelligence, so it does not help these devices. From V2, Pro users on them can opt in to the
Claude tier, with its consent screen shown only after first value ([PRD](prd.md), FR-ONB-006).
Apple publishes which devices support Apple Intelligence
([Apple Intelligence](https://www.apple.com/apple-intelligence/)); the in-app check uses the
framework's availability API rather than device model lists.

## Risks

| Risk | Mitigation |
|---|---|
| The PDF SDK lags on Mac or visionOS | Platform coverage is a scored criterion in the vendor spike ([ADR-0007](adr/0007-pdf-sdk-boundary-and-vendor-selection.md)) |
| iPad needs leak into MVP scope | Only adaptivity is required in the MVP; iPad features are scheduled for V2 |
| Framework availability differs by platform | The shared-code matrix is checked per package at each platform's entry decision |
