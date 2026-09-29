# ADR-0018: Snapshot testing as a test-only dependency

**Status:** accepted (2026-09-28)

**Context.** Visual regressions in a design-led app need automated detection. Apple offers no snapshot-testing framework.

**Decision.** Use Point-Free's `swift-snapshot-testing` in test targets only; it never ships in the app. Reference images live next to the tests; recording requires an explicit flag.

**Alternatives considered.** An in-house `ImageRenderer` diff harness (maintenance cost for a solved problem). No snapshot tests (visual regressions reach users).

**Consequences.** One test-only dependency, pinned and reviewed like any other; no privacy or binary-size impact.

**Pillars served.** PIL-7

**References.** [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing)
