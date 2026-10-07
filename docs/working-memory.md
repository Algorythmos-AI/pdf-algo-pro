# Working memory

The living state of PDF Algo Pro: where the project is, what is in flight, the top risks, open
questions, recent decisions and known issues. Read it first when you pick up work; update it in any
pull request that changes the state (the pull request template asks). It is short on purpose: detail
lives in the linked documents.

Owner: Maintainer · Reviewed: every pull request that changes state; at least monthly

Last updated: 2026-10-07

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
| First run, subscription and free allowance ([ADR-0026](adr/0026-first-run-subscription-offer-and-plans.md), PAP-042 to PAP-045, PAP-048) | Built: the store foundation is on `integration`; the three-page introduction, the offer after first run, its confirmation, the trial reminder, the enforced daily allowance and the Settings section are in review. Nothing can be bought until the products exist in App Store Connect, and the plans as StoreKit draws them have not been seen | Owner: paid-app agreements, the Family Sharing decision, the two allowance numbers, then the subscription group and products for the production and Staging apps; run the store suite from Xcode and the new rows of the [device smoke test](process/device-smoke-test.md). |
| Editing existing text (FR-EDIT-001, [ADR-0025](adr/0025-native-text-editing-for-the-safe-subset.md)) | On `integration` since 2026-10-04 and in the Staging build of 2026-10-05, behind the `textEditing` release flag (on in Debug and Staging, off in Release) and the Pro access value; no purchase flow yet | ADR-0025 accepted (PAP-036). Owner's first device run (2026-10-05) found Edit dead after a document was opened a second time: the page view stayed bound to the first load. Fixed on `fix/dependable-text-editing` with one picking path, outlines that cannot go stale, time limits and a content-free editing summary in Report a problem. The owner confirmed editing on the phone; a second defect (edits to documents in a typeface the device lacks were refused; no way to finish) was fixed in #145 with a guarantee of no dead ends (PAP-039), and a synthetic corpus now checks every line of fifteen kinds of document. Next: the owner sweeps a folder of their own PDFs with the local probe, then runs the [text editing device test](process/text-editing-device-test.md), including its new "Staying dependable" rows; the flag goes on in Release only after it is signed off |
| TestFlight readiness ([#47](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/47)) | On `integration`: version history, signed PDFs saved as a copy, one writer per document, App Lock, follow-up questions, the privacy report, whole-library search, document info, multi-select and merge, moving and resizing annotations, read aloud across pages, link confirmation, stamps, bookmarks, the annotation list, scan review, CSV file, the Siri summary, the rating request, app icon v2 with Liquid Glass. Foundations not yet used by a screen: the kill-switch package, the AI routing policy with consent, and the Commerce package (now with the product catalogue, one entitlement store followed from launch, and the free daily allowance). First run is now three introduction pages and, when the plans load, the subscription offer once; Scan and the assistant ask the allowance before they start (the Siri summary too); Settings opens with a subscription section; the purchase confirmation can schedule the trial reminder. People who decline notifications are told in the app when the trial is a day from its end. Nothing can be bought until the owner creates the products in App Store Connect; until then internal builds have "Pro without a purchase" in Settings › Internal testing | The owner gives the go for the Staging build; device checks in the [device smoke test](process/device-smoke-test.md) |
| Independent PDF validation (plan B2) | qpdf and PDFium in CI, and Core Graphics in the corpus tests; the save suites run under Thread Sanitizer. All advisory | Make the jobs required after two weeks; [#96](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/96) is a quirk of the synthetic input |
| Flaky large-text audits and Markup menu tap ([#76](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/76)) | Stricter still-screen wait; bar-button contrast quarantined | Remove the quarantine if possible, by 2026-10-07 |
| Flaky audit timeout ([#53](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/53)) | Quarantined | Fix or delete with the debt recorded |
| Flaky simulator launch ([#126](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/126)) | Seen once on `integration`; the next run passed | Warm up the simulator or retry the launch, by 2026-10-08 |
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

- PRD OQ-1 to OQ-5 ([PRD](prd.md#open-questions)). OQ-2 (the two allowance numbers) and OQ-5 (Family
  Sharing) now block the subscription products.
- Legal review items LR-01 to LR-21 ([compliance roadmap](compliance-roadmap.md)).
- Whether Private Cloud Compute counts as "third-party AI" under Guideline 5.1.2(i); consent is
  shown regardless.
- Development language of the String Catalogs (English variant).
- "Rate PDF Algo Pro" in Settings › About: not built, because the link needs the public App Store
  identifier, which exists only once the app is on the store. Add it in the release pull request.

## Recent decisions

The last ten, newest first; all decisions are in the [decision register](decision-register.md).

| ID | Decision |
|---|---|
| PAP-048 | As built: no tip card on Home, the purchase tests run from Xcode and not in CI, one internal switch for Pro, and the subscription section after the AI switch |
| PAP-047 | The accent is the product's red on white, with native bars; on documents, selection is the system's blue; the icon's field is red |
| PAP-046 | Existing text can be moved by holding and dragging a line: a real, proven move, with covering as the fallback (FR-EDIT-009) |
| PAP-045 | First run becomes three introduction pages; the intent question moves to Settings; Home's empty-library line is the first-use hint; a confirmation after purchase |
| PAP-044 | The free tier meters scans saved and intelligence requests per day; Pro removes the limits and adds text editing; existing documents are never gated |
| PAP-043 | Pro is a weekly and an annual plan, with the trial on the weekly plan; supersedes "no weekly plans" |
| PAP-042 | The subscription offer may show once at the end of first run, closable at once; supersedes "no paywall before first value" |
| PAP-041 | "Include a diagnostics summary" is on by default and the choice is stored; the summary's contents are unchanged |
| PAP-040 | On iPhone the app opens on Home (mark, starting actions, recent documents, sections with counts, trust footer); the brand shows in a few signature moments on Home, in Settings and in About |
| PAP-039 | An edit that cannot be proven is covered automatically and announced; pages are rehearsed; the proof compares baselines |
| PAP-038 | Privacy policy, terms, support and product pages live on algorythmos.com and linked from Settings; support address pdfalgopro@algorythmos.com; drift guards in CI and the release workflow |
| PAP-037 | The reader's bar has one filled button, "Edit", with a one-time tip; Ask stays in the bar and the title gives way on narrow iPhones |
| PAP-036 | ADR-0025 accepted: native text editing for the safe subset; the release flag waits for the device test |
| PAP-035 | Existing-text editing is built natively for the safe subset, behind `PDFTextEditing`, a release flag and Pro; ADR-0007 stays proposed for the rest (ADR-0025) |
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
