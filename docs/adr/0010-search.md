# ADR-0010: Core Spotlight for search, with an on-device index as fallback

**Status:** accepted (2026-09-28)

**Context.** Users search by title, tag and content (including OCR text), both in the app and from system Spotlight.

**Decision.** Index titles, tags and extracted text with Core Spotlight on device, and use it for in-app search too. If its query features prove insufficient in the MVP, add a dedicated on-device full-text index behind the `Search` package. Nothing is indexed outside the device.

**Alternatives considered.** A server-side search index (privacy). SQLite FTS5 from the start (more code before it is proven necessary).

**Consequences.** System integration for free; limited control over ranking. Decided with real data during the MVP.

**Pillars served.** PIL-1, PIL-6, PIL-7

**References.** [Core Spotlight](https://developer.apple.com/documentation/corespotlight)

**Addendum, 2026-10-08 (PAP-055).** As built, in-app search uses the app's own on-device index, which this ADR names as the fallback, and Core Spotlight is written to so that documents are found from the system. That stays: the app's index is exercised by tests and gives the same answer on every device. Behind `ReleaseFlag.baseFormMatching`, a searched word also matches in its base form, from NaturalLanguage.
