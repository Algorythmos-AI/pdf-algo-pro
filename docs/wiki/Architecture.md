# Architecture

A modular Swift 6 app for iOS and iPadOS 27, generated with XcodeGen from local Swift packages
(`Core`, `PDFEngine`, `DocumentStore`, `Scanning`, `OCR`, `Intelligence`, `Search`, `Commerce`,
`Telemetry`, `DesignSystem` and one package per feature). SwiftUI with Observation, actors for
services, documents in iCloud Drive, SwiftData for the library, a commercial PDF SDK behind the
`PDFEngine` boundary, and tiered intelligence through Apple's Foundation Models framework.

## Read more

- [iOS architecture review](../ios-architecture-review.md): all 17 areas with rationale,
  trade-offs, alternatives, risks and scalability
- [Architecture decision records](ADRs.md)
- [Platform strategy](../platform-strategy.md) and [performance budgets](../performance-budgets.md)
- [Coding standards](../coding-standards.md) and [Swift style guide](../swift-style-guide.md)
