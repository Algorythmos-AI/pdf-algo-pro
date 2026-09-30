# Working memory

The living state of PDF Algo Pro: where the project is, what is in flight, the top risks, open
questions, recent decisions and known issues. Read it first when you pick up work; update it in any
pull request that changes the state (the pull request template asks). It is short on purpose: detail
lives in the linked documents.

Owner: Maintainer · Reviewed: every pull request that changes state; at least monthly

Last updated: 2026-10-01

## Current phase

**MVP → V1.** The native iOS app is on `integration`, built under the owner's exception PAP-028, on
the interim Xcode 26 toolchain (PAP-029) and an iOS 26 floor that stays (ADR-0023, PAP-033). The owner
installed the validation build on 2026-09-30. Build 1 waits for the bar in
[#47](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/47)
([quality gates](process/quality-gates.md#build-1-bar)). V1 scope and the operating authority for
building it are PAP-031 and PAP-032. The readiness gate is still **NOT READY** for the App Store
([readiness review](readiness-review.md)).

## In flight

| Item | State | Next step |
|---|---|---|
| TestFlight readiness ([#47](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/47)) | Merged: evaluation screen, performance, background OCR, continued recognition, French, snapshots, the everyday toolkit, the save-path rework with fault injection, H6 and H2. Pushed and queued, one PR at a time: H9 signed PDFs, H5 one writer, FR-EDIT-008 version history, the kill-switch package, and the B3/C polish and tools | Merge the queue; the owner gives the go for build 1 |
| Independent PDF validation (plan B2) | qpdf job in CI, advisory for two weeks; Core Graphics parse queued | [#96](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/96): three offset-0 xref entries in a saved RTL/CJK file |
| Flaky large-text audits and Markup menu tap ([#76](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/76)) | Stricter still-screen wait; bar-button contrast quarantined | Remove the quarantine if possible, by 2026-10-07 |
| Flaky audit timeout ([#53](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/53)) | Quarantined | Fix or delete with the debt recorded |
| Needs a device | H4 (saving off the main actor) waits for device timings; FR-AI-015 line items and the follow-up prompt ([#90](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/90)) wait for a live evaluation (ADR-0020); reading themes wait for a visual check | Owner runs the performance and live AI evaluation on the phone |
| Organisation catalog entry | Catalog entry pending owner review | Owner review and merge |
| Backlog issues | 36 issues synced from `docs/planning/backlog.yaml`, on the project board | Owner creates the project views and built-in workflows in the web interface |
| Xcode Cloud Staging workflow (readiness M5) | Configured (manual start, internal only, Xcode 26.6); the validation build archived and installed | Nightly after build 1 (PAP-031); Release workflow before V1 |
| Xcode 27 toolchain (readiness C2) | The development Mac lacks the disk space; CI and Xcode Cloud can run it | One pull request moves CI and Xcode Cloud to Xcode 27 after build 1 (ADR-0023) |

## Top risks

| Risk | Where it is managed |
|---|---|
| PDF SDK licence cost makes early break-even impossible | [Financial model](financial-model.md); phased-licence option in [ADR-0007](adr/0007-pdf-sdk-boundary-and-vendor-selection.md) |
| A competitor ships private on-device intelligence first | [Competitive moat](competitive-moat.md) |
| The on-device model's small context limits long-document answers | [Model selection](model-selection.md) |
| Apple Intelligence device eligibility excludes part of the market | [AI governance](ai-governance.md), [product positioning](product-positioning.md) |
| A single maintainer is a bottleneck and continuity risk | [SUPERVISION](../.github/SUPERVISION.md), [operations](operations.md) |
| A save or an edit loses or damages a user's file | Revert history FR-EDIT-008 before build 2; fault-injection tests of the save path ([PRD](prd.md)) |

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
| PAP-033 | iOS 26 floor, built with the Xcode 27 SDK (ADR-0023) |
| PAP-032 | V1 scope: 19 new requirements, compress becomes a Must, on-device conversion only, cut order |
| PAP-031 | Operating authority after build 1: agents merge green PRs into `integration`; vendor SDK, remote configuration and PCC in scope; stop the line on red |
| PAP-030 | Push to the first internal TestFlight build; agents merge green PRs into `integration`; single window; iCloud and folders deferred |
| PAP-029 | Interim iOS 26 floor and Xcode 26 in CI until Xcode 27 builds (C2) |
| PAP-028 | Owner exception: the foundation app is built before the readiness gate clears |
| PAP-027 | Phases aligned to the PRD; opt-in telemetry moves to V2 |
| PAP-026 | Phased PDF SDK licence allowed if the quote requires it |
| PAP-025 | `main` requires checks on the release head, not up to date with `main` |
| PAP-024 | Remote configuration never delivers new prompt text |

## Known issues

- CodeQL Swift analysis takes 30–50 minutes (the tracer, not the build); it is moving to a nightly
  schedule (#47, P2). `codeql (actions)` runs and uploads, but is not yet a required check.
- The accessibility audit reported "Dynamic Type partially unsupported" on text in sheets now and then,
  because it measures before a sheet has redrawn at the new size. On sheets that finding is excluded,
  and the large-text journeys and snapshots check sheets at an accessibility size instead (#44).
- The iOS job runs on the interim Xcode 26 toolchain with an `iPhone 17` on the iOS 26 runtime, and
  creates that simulator if the runner image lacks it (PAP-029, backlog F-002).
- The live on-device model tests (`LiveModelTests`) are opt-in: the development Mac has Apple
  Intelligence turned off, and CI runners have no model. Run them with `PDFALGOPRO_LIVE_MODEL=1`.
- The simulator reports the on-device model as available but has no model assets, so real answers
  fail there with the "didn't finish" message; UI tests use the scripted router instead.
- Release and performance test plans run in Xcode Cloud, not GitHub Actions; the performance-budget
  comparison script is still to be written ([testing strategy](testing-strategy.md)).
