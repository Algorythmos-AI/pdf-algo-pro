# ADR-0017: Privacy-first product telemetry

**Status:** accepted (2026-09-28)

**Context.** The product needs to learn which features create value, but its promise is privacy.

**Decision.** Collect only minimal, non-identifiable, aggregated telemetry, with disclosure and consent where required; never document content, personal data or business data. Acquisition and revenue come from App Store Connect and App Store Server Notifications V2; performance from MetricKit. In-app funnels use opt-in counters aggregated on the device and sent in batches to `pdf-algo-pro-backend` once it exists. Events go through the `Telemetry` package with an allow-listed schema.

**Alternatives considered.** Third-party analytics SDKs (data processors, identifiers). No in-app telemetry at all (blind to activation and feature adoption).

**Consequences.** Less granular data than typical apps; accepted. The privacy label stays honest and small.

**Pillars served.** PIL-5

**References.** [App privacy details](https://developer.apple.com/app-store/app-privacy-details/) · [App Store Server Notifications](https://developer.apple.com/documentation/appstoreservernotifications)
