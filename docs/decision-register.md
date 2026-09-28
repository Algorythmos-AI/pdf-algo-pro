# Decision register

Every decision that shapes PDF Algo Pro: product, engineering and process. Architecture decisions
also have an ADR with the full reasoning; this register is the one place to see all decisions in
order. Format follows the organisation's decision log: ID · date · decision · by · why ·
consequences. Append only; to change course, add a new entry that supersedes an old one.
Business decisions with confidential detail are recorded in the private business register and
summarised here only when the summary is safe to publish.

**How to add a decision.** Take the next number after the highest `PAP-` ID, add one row at the end
in the same pull request as the change it decides, and link the document that carries the full
reasoning. A row is a summary: a major decision also records rationale, trade-offs, alternatives
considered, risks and future scalability impact in its document or, for architecture, in an ADR
(the ADR format is described in the [ADR index](adr/README.md)).

Owner: Maintainer · Reviewed: each milestone

| ID | Date | Decision | By | Why | Consequences |
|---|---|---|---|---|---|
| PAP-001 | 2026-09-28 | Minimum OS is iOS and iPadOS 27; Swift 6 with strict concurrency; Xcode 27. | Owner | The product is built on iOS 27 intelligence and document APIs. | [ADR-0001](adr/0001-platform-floor-and-swift-6.md); readiness blocker C2 (toolchain). |
| PAP-002 | 2026-09-28 | Intelligence is tiered: on device, then Apple Private Cloud Compute, then Claude; every cloud tier is opt-in with named consent. | Owner | Privacy and offline are pillars; long documents need larger models. | [ADR-0009](adr/0009-tiered-ai-and-consent.md), [ADR-0021](adr/0021-ai-provider-routing-and-failover.md); a relay is required before general availability. |
| PAP-003 | 2026-09-28 | Use a commercial PDF SDK from day one, behind our own engine boundary; vendor chosen by a scored spike. | Owner | True text editing, redaction and Office conversion are core to the category; PDFKit cannot do them. | [ADR-0007](adr/0007-pdf-sdk-boundary-and-vendor-selection.md) stays Proposed until the spike; readiness blocker C1. |
| PAP-004 | 2026-09-28 | The repository is `pdf-algo-pro`, the canonical product identifier; satellite repositories are reserved and created only when a separation criterion is met. | Owner | Organisation naming standard; one repository is simpler until separation is justified. | [ADR-0019](adr/0019-public-private-documentation-split.md); renamed from `PDF-Algo-Pro`. |
| PAP-005 | 2026-09-28 | Business-sensitive documents are kept as confidential editions in a private companion repository; this repository holds redacted public editions at the same paths. | Owner | The repository is public for now; prices, costs, targets and competitive detail must not be. | [ADR-0019](adr/0019-public-private-documentation-split.md); public documents never link to the private repository. |
| PAP-006 | 2026-09-28 | Branch model: `integration` (default, staging) into `main` (production). | Owner | A staging line feeds internal TestFlight before external testers and the App Store. | [ADR-0016](adr/0016-two-branch-model.md); a recorded exception to the organisation default for apps. |
| PAP-007 | 2026-09-28 | Quality gates: conventional titles, secret scan, docs, source invariants, dependency review, CodeQL, and iOS build, tests and 80% coverage behind a change detector. | Owner | A professional quality bar from the first pull request. | [Quality gates](process/quality-gates.md); [ADR-0013](adr/0013-ci-cd.md), [ADR-0014](adr/0014-testing-strategy-and-coverage.md). |
| PAP-008 | 2026-09-28 | Analytics are privacy-first: minimal, non-identifiable, aggregated, consented where required; never document content. | Owner | Privacy is the product. | [ADR-0017](adr/0017-privacy-first-telemetry.md); [analytics strategy](analytics-strategy.md). |
| PAP-009 | 2026-09-28 | Platform priority: iPhone, iPad, Mac, then visionOS; visionOS never shapes V1. | Owner | Prove the core loop where documents arrive; keep later platforms cheap. | [Platform strategy](platform-strategy.md). |
| PAP-010 | 2026-09-28 | Onboarding asks what the user does most with PDFs, with AI-first options on top; no paywall before first value. | Owner | Competitors' onboarding lists only generic tools; intelligence is our differentiator. | [PRD](prd.md), [design system](design-system.md). |
| PAP-011 | 2026-09-28 | Apple-first capability baseline for every feature. | Owner | The native experience is part of the moat. | [ADR-0022](adr/0022-apple-first-capability-baseline.md). |
| PAP-012 | 2026-09-28 | Evidence rule: every claim cited, every number sourced or labelled as an assumption. | Owner | Decisions must be traceable for years. | Enforced in reviews; the docs gate warns on unsourced numbers. |
| PAP-013 | 2026-09-28 | No `FUNDING.yml`. | Owner | Sponsorship does not fit a proprietary commercial product; standards are added only when justified. | [GitHub governance](github-governance.md). |
| PAP-014 | 2026-09-28 | Supervision rules for people and coding agents in `.github/SUPERVISION.md`. | Owner | Human decisions stay with humans; agent work is auditable through pull requests. | [SUPERVISION](../.github/SUPERVISION.md). |
| PAP-015 | 2026-09-28 | No application code until the readiness gate has no open Critical blocker. | Owner | Avoids building on unsettled foundations. | [Readiness review](readiness-review.md). |
| PAP-016 | 2026-09-28 | Readiness blockers C4 (AI provider terms) and C6 (CI execution) reclassified from Critical to Major. | Owner | A Critical blocker must prevent implementation from starting; C4 is needed only for the V2 Claude tier, and CI runs on pull requests. | [Readiness review](readiness-review.md). |
| PAP-017 | 2026-09-28 | The App Store privacy label describes the whole app: "Data Not Collected" for V1 and V1.1; the V2 relay and opt-in telemetry change it. | Owner | Apple's app privacy details require opt-in collection to be disclosed. | [Privacy architecture](privacy-architecture.md), [App Store strategy](app-store-strategy.md). |
| PAP-018 | 2026-09-28 | US English in code identifiers; Australian/British English in documents. | Owner | Identifiers match Apple's APIs; documents follow the organisation's style. | [Swift style guide](swift-style-guide.md). |
| PAP-019 | 2026-09-28 | One paid tier (Pro) at launch; no separate AI add-on. | Owner | Simplicity and the positioning that intelligence is the product. | [Pricing strategy](pricing-strategy.md). |
| PAP-020 | 2026-09-28 | Analyse Contract never uses the Claude tier for now. | Owner | Anthropic's usage policy treats legal interpretation as a high-risk use needing professional review. | [AI governance](ai-governance.md). |
| PAP-021 | 2026-09-28 | App extensions use the on-device tier only. | Owner | App Attest is not available in share extensions; smaller attack surface. | [Privacy architecture](privacy-architecture.md). |
| PAP-022 | 2026-09-28 | JavaScript in PDFs is disabled entirely. | Owner | Removes a class of malicious-document threats. | [Threat model](threat-model.md); checked in the SDK spike (C1). |
| PAP-023 | 2026-09-28 | Comply with the Australian Privacy Principles whether or not the small business exemption applies. | Owner | Privacy is the product; the exemption may be removed by reform. | [Compliance roadmap](compliance-roadmap.md). |
| PAP-024 | 2026-09-28 | Remote configuration may switch a prompt to its previous shipped version or turn it off; it never delivers new prompt text. | Owner | Prompt changes pass evaluation and App Review with the binary. | [Prompt management](prompt-management.md), [ADR-0020](adr/0020-prompt-versioning-and-eval-gates.md). |
| PAP-025 | 2026-09-28 | The `main` ruleset requires checks on the release pull request's head without requiring it to be up to date with `main`. | Owner | Squash back-merges carry content but not ancestry. | [Branching](process/branching.md), [ADR-0016](adr/0016-two-branch-model.md). |
| PAP-026 | 2026-09-28 | If the PDF SDK quote makes early break-even impossible, the MVP may run on PDFKit and license the SDK when V1 editing ships. Amends PAP-003. | Owner | The MVP features are within PDFKit's reach; the licence dominates break-even. | [ADR-0007](adr/0007-pdf-sdk-boundary-and-vendor-selection.md), [financial model](financial-model.md). |
| PAP-027 | 2026-09-28 | Phases aligned to the PRD: form filling and signing in the MVP; Handoff in V2; opt-in telemetry (FR-SET-004, a Must) moves from V1 to V2; V2 is the Claude tier at general availability, with Private Cloud Compute in V1. | Owner | The roadmap, milestones and PRD disagreed; telemetry needs the relay, which arrives in V2 ([ADR-0017](adr/0017-privacy-first-telemetry.md)). | [PRD](prd.md), [roadmap](product/roadmap.md), `.github/milestones.yml`, backlog item W-005. |
