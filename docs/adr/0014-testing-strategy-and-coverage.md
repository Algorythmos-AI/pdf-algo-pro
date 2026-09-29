# ADR-0014: Testing strategy and 80% coverage gate

**Status:** accepted (2026-09-28)

**Context.** A premium, long-lived app needs confidence at every layer: logic, UI, accessibility, performance, OCR accuracy and AI quality.

**Decision.** Swift Testing for unit tests; XCTest for UI and performance tests; `.xctestplan` files; snapshot tests (ADR-0018); `performAccessibilityAudit()` in UI tests; a synthetic golden PDF corpus (forms, encrypted, scanned, very large, malformed); an OCR accuracy suite; the AI evaluation suite. Line coverage of at least 80% overall and per first-party target, excluding generated code and previews, enforced by `scripts/ci/coverage_gate.py`. Test documents are synthetic or licence-clean, never personal.

**Alternatives considered.** Lower or no coverage threshold (the organisation has none today; this repository sets one). XCTest only for unit tests (Swift Testing is Apple's current framework).

**Consequences.** Test effort is part of every feature estimate. Coverage is a floor, not a goal in itself; reviewers still judge test quality.

**Pillars served.** All pillars

**References.** [Swift Testing](https://developer.apple.com/documentation/testing) · [XCTest](https://developer.apple.com/documentation/xctest)
