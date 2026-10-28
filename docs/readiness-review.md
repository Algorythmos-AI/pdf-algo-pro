# Readiness review

The implementation readiness gate for PDF Algo Pro. It scores each readiness area, lists the gaps,
the blockers and the recommendations, and gives a verdict. **No application code is written until
every Critical blocker is closed** ([founder principles](founder-principles.md), decision PAP-015 in
the [decision register](decision-register.md)).

Owner: Maintainer · Reviewed: weekly until the verdict is READY, then at the start of each milestone

## Verdict

**READY for 1.0 submission once C2 and C5 close** (PAP-065, 2026-10-24). The 1.0 release ships
what is built (PAP-065), on iPhone only (PAP-067), with the release flags of PAP-066. Of the Critical
blockers, C1 is closed for 1.0 because no vendor SDK is in the binary and ADR-0025 is accepted; it
reopens as a Major blocker for the release that returns redaction or conversion. C3 is closed: the
owner confirmed the remaining prerequisites on 2026-10-08 (details held privately). C2 closes when
CI and Xcode Cloud build with Xcode 27 (ADR-0023); C5 closes on the lighter design pass of PAP-070
(previews of every screen state, the snapshot gallery and the checklist) and the owner's walk-through
of a Release-configuration build; the visual refresh moved to 1.1. The Major blockers needed before submission are M1,
M5, M8, M10 and M11; the owner's device sign-offs and the release checklist in
[release management](release-management.md) complete the evidence.

**Owner exception (PAP-028).** The native iOS foundation app is being built before the gate clears,
with the owner's approval: PDFKit behind `PDFEngine`, no vendor SDK, no network code and on-device
intelligence only, on an interim iOS 26 toolchain (PAP-029). The verdict stays NOT READY; the blockers
still govern the vendor SDK, App Store submission and every cloud tier.

**Internal TestFlight (PAP-030, 2026-09-30).** The owner approved the push to the first internal
TestFlight build, tracked in [#47](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/47). For that
build: C1 is not applicable while the MVP runs on PDFKit (PAP-026), C2 is worked around by the interim
toolchain (PAP-029), C3 is complete, and C5 is waived. M5 (Xcode Cloud) and M2 (corpora) are part of
that push. The verdict for the App Store is unchanged.

## Scoring rubric

| Score | Meaning |
|---|---|
| 0 | Not started |
| 1 | Intent stated; no documented decisions |
| 2 | Decisions documented; significant inputs missing |
| 3 | Decisions and standards documented; some prerequisites or validation outstanding |
| 4 | Ready except for items that are verified in the first iteration of work |
| 5 | Proven in practice (running code, passing gates, measured results) |

An area scores 5 only on evidence from the running app and its gates.

## Scores

| Area | Score | Evidence | Main gap |
|---|---|---|---|
| Architecture | 4 | [iOS architecture review](ios-architecture-review.md) (17 areas), [ADR-0001 to ADR-0027](adr/README.md), [platform strategy](platform-strategy.md), [performance budgets](performance-budgets.md); the app runs on `integration` with PDFKit behind `PDFEngine`, no vendor SDK and no network code (PAP-028) | Xcode 27 in CI and Xcode Cloud (C2); the document-identity spike (M4) before the iCloud library in V1.1 |
| Security | 3 | [Threat model](threat-model.md), [privacy architecture](privacy-architecture.md), [data classification](data-classification.md), [compliance roadmap](compliance-roadmap.md), [SECURITY](../.github/SECURITY.md); `privacy-impact` required on every pull request (PAP-064) | Legal review LR-15, LR-17 and LR-19 before submission (M8); the SDK audit (C1) returns with V1.1 |
| UX | 2 | [Design system](design-system.md) with generated tokens, snapshot tests of first run, the offer, Home, Settings, Scan and About, the accessibility audit in every UI test | The design pass (C5): previews of every screen state, a snapshot gallery and a checklist, then the owner's walk-through of a Release-configuration build; no usability testing yet |
| Repository | 5 | Rulesets applied on `integration`, `main` and tags (M9); the `ios` check as a job graph with shards, a coverage gate and a flake budget (PAP-062); `invariants`, `docs`, `privacy-impact`, `pr-title`, `secrets` and `dependency-review` on every pull request; more than two hundred pull requests merged through them ([quality gates](process/quality-gates.md)) | `codeql (actions)` not yet a required check (C6) |
| Testing | 4 | [Testing strategy](testing-strategy.md); package, app and UI test suites with snapshots, the golden, malformed and OCR corpora and the deterministic evaluation suite in the repository (M2); PDF validation with qpdf and PDFium; coverage and flake gates green on every `integration` commit | No test has run on a device yet; the French UI run, the per-screen controls suites and the device test plan are to come; `pdf-validation` is still advisory |
| Monetisation | 3 | [Pricing strategy](pricing-strategy.md), [revenue model](revenue-model.md); the app's own offer over StoreKit 2 ([ADR-0027](adr/0027-own-paywall-over-storekit-2.md)), the free daily allowance (PAP-044) and the Staging products, seen with real plans on the simulator and a phone | Becomes 4 after a sandbox purchase and restore on a device; the production products and a real review screenshot (M10); willingness-to-pay research not run |
| App Store | 3 | [App Store strategy](app-store-strategy.md) with the 1.0 decisions (PAP-065 to PAP-067), guideline mapping, [submission runbook](process/runbooks/app-store-submission.md); privacy, terms and support pages live (PAP-038) | Becomes 4 when the listing is complete: the production app record and its URLs (M1), screenshots from the build and the review notes (M11) |
| Operations (added) | 3 | [Operations](operations.md), the runbooks, [release management](release-management.md); the Xcode Cloud Staging workflow has delivered 27 builds by hand (PAP-063) | The Release workflow (M5); the wiki (M6) |
| Product (added) | 3 | [PRD](prd.md) with the 1.0 release criterion, [product positioning](product-positioning.md), [competitive moat](competitive-moat.md), [roadmap](product/roadmap.md) | Hypotheses not yet tested ([customer research](customer-research.md)) |

## Blockers

Public titles are deliberately generic where the details concern accounts, agreements, vendors or
billing; those details are held privately.

### Critical (block the start of implementation)

| ID | Blocker | Owner | Exit criterion | Status (2026-10-24) |
|---|---|---|---|---|
| C1 | PDF SDK vendor spike, licence and telemetry audit | Architecture | Vendor chosen on the ADR-0007 criteria with a prototype; licence terms acceptable; SDK network and JavaScript behaviour audited; ADR-0007 accepted | Closed for 1.0 (PAP-065): no vendor SDK is in the binary and text editing is native ([ADR-0025](adr/0025-native-text-editing-for-the-safe-subset.md), PAP-036). Reopens as a Major blocker for the release that returns redaction or conversion (V1.1 at the earliest) |
| C2 | Xcode 27 toolchain in CI and Xcode Cloud | Architecture | The toolchain pull request is green in CI (iOS 26 and iOS 27 simulators) and Xcode Cloud archives with Xcode 27 ([ADR-0023](adr/0023-ios-26-floor-built-with-xcode-27.md)); local Xcode 27 when the development Mac has space | Open; the required gate and Xcode Cloud still build with Xcode 26.6 (PAP-029). Since 2026-10-25 `ios-27` builds with Xcode 27.0 and runs the unit and UI tests on iOS 27 beside the gate, on GitHub's preview image; the gate moves once that image is generally available (owner's decision). The full UI suite passed on the owner's iPhone with iOS 27 on 2026-10-25 (#295, #300). The development Mac has Xcode 27 and no simulator runtime |
| C3 | Apple Developer Program prerequisites (account, agreements and capabilities; details held privately) | Maintainer | All prerequisites confirmed complete | Closed (PAP-065): the owner confirmed the remaining prerequisites complete on 2026-10-08 |
| C5 | Information architecture and key flows | Design | Reviewed SwiftUI prototypes of every new V1 flow, and a design pass before external TestFlight (PAP-031): previews of every screen state, a snapshot gallery and a checklist, each screen reviewed by the owner on a Release-configuration build | Open; waived for internal TestFlight (PAP-030). For 1.0 it closes on the lighter design pass of PAP-070 when the owner has walked through a Release-configuration build against the [design-pass checklist](design/design-pass-checklist.md) and dated every row. The previews (a `#Preview` per screen state in each feature package) and the [snapshot gallery](design/gallery.md) from `scripts/design/gallery.py` are in place; the walk-through is not done. The visual refresh moved to 1.1 (PAP-070) |

### Major (must close before the milestone named)

C4 and C6 keep their original IDs after reclassification, so earlier references stay traceable.

| ID | Blocker | Needed by | Exit criterion | Status (2026-10-24) |
|---|---|---|---|---|
| C4 | AI tier provider terms (workspace, data processing and retention terms, spend caps) and relay design | V2 (Claude tier) | Terms confirmed; relay design reviewed | Open |
| C6 | CI execution: CodeQL advanced setup (details held privately) | MVP | `codeql (actions)` green and required | Partly: default setup is off and `codeql (actions)` is green; not yet a required check |
| M1 | Privacy policy, terms and support URLs live | 1.0 submission | Pages published and linked, in the app and on the App Store record | Pages live since 2026-10-06 and linked from Settings › About and the TestFlight record (PAP-038); the production app record and its URLs remain ([#10](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/10)); the legal review of the pages is M8 |
| M2 | Golden PDF corpus, OCR corpus and AI evaluation sets | First code pull request | Corpora in the repository (synthetic or licence-clean) | Closed: the golden and malformed PDF corpora (`PDFEngineTests`), the OCR corpus (`OCRTests`) and the deterministic evaluation suite (`IntelligenceTests`) are in the repository and run in CI |
| M3 | Organisation catalog entry merged | MVP | Catalog pull request merged | Open |
| M4 | Document-identity spike | V1.1 library work | Prototype passes rename, move and eviction cases | Open (#6); the iCloud library and folders are out of 1.0 (PAP-030, PAP-065) |
| M5 | Xcode Cloud workflows for `integration` and `main` | Release pull request | Staging and Release workflows green | Staging runs by hand on the owner's go, 27 builds so far (PAP-063); the Release workflow is the owner's to create, and one manual Release-configuration build from `integration` gives the parity smoke test before the release pull request |
| M6 | Wiki bootstrap | 1.0 | Wiki published from `docs/wiki` | Open (#11); the release workflow warns without its token |
| M7 | Dormant Swift gates proven | First code pull request | `ios`, coverage and CodeQL Swift jobs run green | Closed 2026-09-29: `ios`, coverage and CodeQL Swift green on `integration` |
| M8 | Legal review of the V1 items in the compliance roadmap | 1.0 submission | LR-15, LR-17 and LR-19 answered before submission; the rest before the release that needs them | Open; the brief is drafted in the private companion repository and sent by the owner |
| M9 | Rulesets applied | Before the second pull request merges | `integration`, `main` and tag rulesets active with the checks that report | Closed 2026-09-29: all three rulesets active |
| M10 | Production subscription products | 1.0 submission | Both plans on the production app, Ready to Submit, with a review screenshot from the Release build, Family Sharing on the annual plan and the grace period on ([subscriptions runbook](process/runbooks/app-store-connect-subscriptions.md)) | Open; the Staging products exist and work (PAP-050); the owner creates production's after a sandbox purchase on a device |
| M11 | App Store listing | 1.0 submission | The production app record with its metadata in five localisations, screenshots shot from the submitted build, review notes, age rating, privacy answers and the trader declaration ([App Store strategy](app-store-strategy.md), [#30](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/30)) | Open; the copy decisions are made (PAP-065, PAP-067); the record, products and screenshots follow in that order |

## Gaps (not blockers)

- Customer hypotheses (switch, pay, stay) are untested; research studies R1 to R3 run during
  Foundation.
- Several numbers are labelled assumptions (performance budgets, AI thresholds, business targets);
  each has a validation plan and is revisited at the end of the MVP.
- Market size has no reliable public figure; the [target market](target-market.md) defines a
  bottom-up method.
- Open questions are listed in each document (for example PRD OQ-1 to OQ-5).

## Recommendations

The order of the 1.0 plan ([working memory](working-memory.md)):

1. Move CI and Xcode Cloud to Xcode 27 (C2) and cut one Staging build with it; the text-editing
   device test runs on that build (PAP-066).
2. Fix the open defects first and prove the save path under sanitizers and fault injection.
3. Run the lighter design pass (C5, PAP-070) as previews, a snapshot gallery and a checklist, and have
   the owner walk a Release-configuration build against it. The visual refresh is 1.1 work.
4. Send the legal brief (M8) now; LR-15, LR-17 and LR-19 have the longest lead time.
5. Create the production app record, its products and the listing in that order (M1, M10, M11), so
   the Rate link, the review screenshot and the screenshots come from the build being submitted.
6. Record every device run in the sign-off tables; the release pull request links them.
7. Start research studies R1 and R2 after launch; they change positioning, not code.

## Change log

| Date | Change |
|---|---|
| 2026-09-28 | First review. C4 and C6 reclassified from Critical to Major: C4 is needed only for the V2 Claude tier, and CI now runs on pull requests (decision PAP-016). |
| 2026-09-29 | Owner exception PAP-028: the foundation app is built before the gate clears; interim iOS 26 toolchain (PAP-029). Verdict unchanged. |
| 2026-09-30 | Status column added. M7 and M9 closed; C3 closed for TestFlight; internal TestFlight approved (PAP-030) with C1 not applicable and C5 waived. Verdict for the App Store unchanged. |
| 2026-09-30 | Plan after build 1 (PAP-031 to PAP-033): C2 closes on CI and Xcode Cloud with the iOS 26 floor (ADR-0023); C5 becomes reviewed SwiftUI prototypes; C1 applies to V1. Verdict unchanged. |
| 2026-10-24 | 1.0 scope (PAP-065 to PAP-067): C1 closed for 1.0 and reopening as Major for the release that returns redaction or conversion; C3 closed; M2 closed; M10 and M11 added; scores revised (Repository 5, Testing 4, Monetisation 3, App Store 3). Verdict: READY for 1.0 submission once C2 and C5 close. |
| 2026-10-28 | Visual refresh moved to 1.1 (PAP-070): C5 closes for 1.0 on the lighter design pass (previews, snapshot gallery, checklist) and the owner's walk-through of a Release-configuration build. Verdict unchanged: READY for 1.0 submission once C2 and C5 close. |
