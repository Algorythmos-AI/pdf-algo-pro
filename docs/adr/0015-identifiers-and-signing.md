# ADR-0015: Identifiers and signing

**Status:** accepted (2026-09-28)

**Context.** Identifiers are permanent once registered; signing material must never enter git.

**Decision.** Bundle identifier `com.algorythmos.pdfalgopro` (Staging configuration adds `.staging` so both builds install side by side); App Group `group.com.algorythmos.pdfalgopro`; iCloud container `iCloud.com.algorythmos.pdfalgopro`; URL scheme `pdfalgopro://`. Automatic signing; the Team ID is injected at build time (Xcode Cloud or a local, git-ignored setting) and never committed.

**Alternatives considered.** Hyphenated identifiers (valid, but inconsistent across App Group and iCloud identifiers). Committing the Team ID (the organisation's safer pattern keeps it out of the repository).

**Consequences.** Identifiers follow the organisation's `com.algorythmos.<product>` pattern. Registering them is part of readiness blocker C3.

**Pillars served.** PIL-7

**References.** [Bundle IDs](https://developer.apple.com/documentation/appstoreconnectapi/bundle-ids)
