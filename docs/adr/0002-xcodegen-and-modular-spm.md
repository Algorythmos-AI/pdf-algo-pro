# ADR-0002: XcodeGen project and modular Swift packages

**Status:** accepted (2026-09-28)

**Context.** Committed `.xcodeproj` files cause merge conflicts and hide configuration. A single target grows slow to build and hard to own.

**Decision.** Generate the Xcode project with XcodeGen from `project.yml` (pinned version, checksum-verified in CI); never commit the `.xcodeproj` except the SwiftPM lockfile. Split code into local Swift packages per capability (`Core`, `PDFEngine`, `DocumentStore`, `Scanning`, `OCR`, `Intelligence`, `Search`, `Commerce`, `Telemetry`, `DesignSystem`, `Features/*`) with a thin app target. Allowed imports follow the dependency graph in the architecture review and are enforced by the `invariants` gate.

**Alternatives considered.** Committed `.xcodeproj` (conflicts). Tuist (capable; the organisation standardised on XcodeGen). A single target (fast start, slow growth).

**Consequences.** Clear ownership boundaries that map to future teams; faster incremental builds; packages reusable on every Apple platform. Requires discipline about public APIs and a pinned XcodeGen version.

**Pillars served.** PIL-7

**References.** [XcodeGen](https://github.com/yonaskolb/XcodeGen) · [Swift packages](https://developer.apple.com/documentation/xcode/swift-packages)
