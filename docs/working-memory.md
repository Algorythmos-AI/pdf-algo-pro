# Working memory

The living state of PDF Algo Pro: where the project is, what is in flight, the top risks, open
questions, recent decisions and known issues. Read it first when you pick up work; update it in any
pull request that changes the state (the pull request template asks). It is short on purpose: detail
lives in the linked documents.

Owner: Maintainer · Reviewed: every pull request that changes state; at least monthly

Last updated: 2026-09-30

## Current phase

**Foundation → MVP.** The planning package and the native iOS foundation app are on `integration`
(built under the owner's exception PAP-028, on the interim iOS 26 toolchain PAP-029). The readiness
gate is still **NOT READY** for the App Store ([readiness review](readiness-review.md)); the owner
approved the push to the first internal TestFlight build at the V1 quality bar (PAP-030), tracked in
[#47](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/47).

## In flight

| Item | State | Next step |
|---|---|---|
| TestFlight readiness ([#47](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/47)) | Plan approved; bar B1–B13; work in four lanes, one pull request per item | Items ticked in #47 as they merge; validation build after the first night |
| Flaky accessibility audit ([#44](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/44)) | Quarantined (#45) | Root cause and remove the quarantine by 2026-10-06 |
| Flaky large-text audits and Markup menu tap ([#76](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/76)) | Stricter still-screen wait; bar-button contrast quarantined | Five green runs, then remove the quarantine if possible, by 2026-10-07 |
| Organisation catalog entry | Catalog entry pending owner review | Owner review and merge |
| Backlog issues | 36 issues synced from `docs/planning/backlog.yaml`, on the project board | Owner creates the project views and built-in workflows in the web interface |
| Xcode Cloud Staging workflow (readiness M5) | Designed; post-clone script and Staging scheme in progress | Owner onboards the Staging product in Xcode; the workflow is configured through the App Store Connect API (PAP-030) |

## Top risks

| Risk | Where it is managed |
|---|---|
| PDF SDK licence cost makes early break-even impossible | [Financial model](financial-model.md); phased-licence option in [ADR-0007](adr/0007-pdf-sdk-boundary-and-vendor-selection.md) |
| A competitor ships private on-device intelligence first | [Competitive moat](competitive-moat.md) |
| The on-device model's small context limits long-document answers | [Model selection](model-selection.md) |
| Apple Intelligence device eligibility excludes part of the market | [AI governance](ai-governance.md), [product positioning](product-positioning.md) |
| A single maintainer is a bottleneck and continuity risk | [SUPERVISION](../.github/SUPERVISION.md), [operations](operations.md) |

## Open questions

- PRD OQ-1 to OQ-5 ([PRD](prd.md#open-questions)).
- Legal review items LR-01 to LR-21 ([compliance roadmap](compliance-roadmap.md)).
- Whether Private Cloud Compute counts as "third-party AI" under Guideline 5.1.2(i); consent is
  shown regardless.
- Development language of the String Catalogs (English variant).

## Recent decisions

The last ten, newest first; all decisions are in the [decision register](decision-register.md).

| ID | Decision |
|---|---|
| PAP-030 | Push to the first internal TestFlight build; agents merge green PRs into `integration`; single window; iCloud and folders deferred |
| PAP-029 | Interim iOS 26 floor and Xcode 26 in CI until Xcode 27 builds (C2) |
| PAP-028 | Owner exception: the foundation app is built before the readiness gate clears |
| PAP-027 | Phases aligned to the PRD; opt-in telemetry moves to V2 |
| PAP-026 | Phased PDF SDK licence allowed if the quote requires it |
| PAP-025 | `main` requires checks on the release head, not up to date with `main` |
| PAP-024 | Remote configuration never delivers new prompt text |
| PAP-023 | Comply with the Australian Privacy Principles regardless of exemption |
| PAP-022 | JavaScript in PDFs disabled |
| PAP-021 | Extensions use the on-device tier only |

## Known issues

- CodeQL Swift analysis takes 30–50 minutes (the tracer, not the build); it is moving to a nightly
  schedule (#47, P2). `codeql (actions)` runs and uploads, but is not yet a required check.
- The accessibility audit intermittently reports "Dynamic Type partially unsupported" on text in
  sheets; quarantined as a non-strict expected failure (#44, #45).
- The iOS job runs on the interim Xcode 26 toolchain with an `iPhone 17` on the iOS 26 runtime, and
  creates that simulator if the runner image lacks it (PAP-029, backlog F-002).
- The live on-device model tests (`LiveModelTests`) are opt-in: the development Mac has Apple
  Intelligence turned off, and CI runners have no model. Run them with `PDFALGOPRO_LIVE_MODEL=1`.
- The simulator reports the on-device model as available but has no model assets, so real answers
  fail there with the "didn't finish" message; UI tests use the scripted router instead.
- Release and performance test plans run in Xcode Cloud, not GitHub Actions; the performance-budget
  comparison script is still to be written ([testing strategy](testing-strategy.md)).
