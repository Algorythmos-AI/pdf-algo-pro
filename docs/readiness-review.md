# Readiness review

The implementation readiness gate for PDF Algo Pro. It scores each readiness area, lists the gaps,
the blockers and the recommendations, and gives a verdict. **No application code is written until
every Critical blocker is closed** ([founder principles](founder-principles.md), decision PAP-015 in
the [decision register](decision-register.md)).

Owner: Maintainer · Reviewed: weekly until the verdict is READY, then at the start of each milestone

## Verdict

**NOT READY.** Four Critical blockers are open (C1, C2, C3, C5). The planning package itself is
complete: architecture, product, governance, security, AI and business documents exist and agree.
What remains is work that only the maintainer, vendors or Apple can complete, plus the UX design
that code needs as input.

## Scoring rubric

| Score | Meaning |
|---|---|
| 0 | Not started |
| 1 | Intent stated; no documented decisions |
| 2 | Decisions documented; significant inputs missing |
| 3 | Decisions and standards documented; some prerequisites or validation outstanding |
| 4 | Ready except for items that are verified in the first iteration of work |
| 5 | Proven in practice (running code, passing gates, measured results) |

No area can score 5 before code exists.

## Scores

| Area | Score | Evidence | Main gap |
|---|---|---|---|
| Architecture | 4 | [iOS architecture review](ios-architecture-review.md) (17 areas), [ADR-0001 to ADR-0022](adr/README.md), [platform strategy](platform-strategy.md), [performance budgets](performance-budgets.md) | PDF SDK choice (ADR-0007 Proposed); document-identity spike |
| Security | 3 | [Threat model](threat-model.md), [privacy architecture](privacy-architecture.md), [data classification](data-classification.md), [compliance roadmap](compliance-roadmap.md), [SECURITY](../.github/SECURITY.md) | Legal review items for V1; SDK network and JavaScript behaviour audit (C1) |
| UX | 2 | [Design system](design-system.md), onboarding intents in the [PRD](prd.md) | Information architecture, key flows and the Figma library (C5); no usability testing yet |
| Repository | 4 | Rulesets as code, four workflows, templates, labels and milestones as code; CI runs on pull requests ([quality gates](process/quality-gates.md)) | Rulesets applied after the first merge; CodeQL advanced setup |
| Testing | 3 | [Testing strategy](testing-strategy.md), [AI evaluation framework](ai-evaluation-framework.md), coverage gate script | Golden PDF, OCR and AI evaluation corpora not yet built; Swift gates dormant until code |
| Monetisation | 2 | [Pricing strategy](pricing-strategy.md), [revenue model](revenue-model.md), [unit economics](unit-economics.md), [financial model](financial-model.md) | PDF SDK licence cost unknown; willingness-to-pay research not run; store prerequisites (C3) |
| App Store | 2 | [App Store strategy](app-store-strategy.md), guideline mapping, [submission runbook](process/runbooks/app-store-submission.md) | Developer account prerequisites (C3); privacy policy and support URLs not live |
| Operations (added) | 3 | [Operations](operations.md), five runbooks, [release management](release-management.md) | Xcode Cloud workflows not set up |
| Product (added) | 3 | [PRD](prd.md), [product positioning](product-positioning.md), [competitive moat](competitive-moat.md), [roadmap](product/roadmap.md) | Hypotheses not yet tested ([customer research](customer-research.md)) |

## Blockers

Public titles are deliberately generic where the details concern accounts, agreements, vendors or
billing; those details are held privately.

### Critical (block the start of implementation)

| ID | Blocker | Owner | Exit criterion |
|---|---|---|---|
| C1 | PDF SDK vendor spike, licence and telemetry audit | Architecture | Vendor chosen on the ADR-0007 criteria with a prototype; licence terms acceptable; SDK network and JavaScript behaviour audited; ADR-0007 accepted |
| C2 | Xcode 27 toolchain locally and in CI | Architecture | Xcode 27 builds locally; the CI runner image and pinned simulator verified |
| C3 | Apple Developer Program prerequisites (account, agreements and capabilities; details held privately) | Maintainer | All prerequisites confirmed complete |
| C5 | Information architecture, key flows and Figma library | Design | Flows for every MVP intent reviewed; Figma library matches the design tokens |

### Major (must close before the milestone named)

C4 and C6 keep their original IDs after reclassification, so earlier references stay traceable.

| ID | Blocker | Needed by | Exit criterion |
|---|---|---|---|
| C4 | AI tier provider terms (workspace, data processing and retention terms, spend caps) and relay design | V2 (Claude tier) | Terms confirmed; relay design reviewed |
| C6 | CI execution: CodeQL advanced setup (details held privately) | MVP | `codeql (actions)` green and required |
| M1 | Privacy policy, terms and support URLs live | V1 submission | Pages published and linked |
| M2 | Golden PDF corpus, OCR corpus and AI evaluation sets | First code pull request | Corpora in the repository (synthetic or licence-clean) |
| M3 | Organisation catalog entry merged | MVP | Catalog pull request merged |
| M4 | Document-identity spike | MVP library work | Prototype passes rename, move and eviction cases |
| M5 | Xcode Cloud workflows for `integration` and `main` | First TestFlight build | Staging and Release workflows green |
| M6 | Wiki bootstrap | MVP | Wiki published from `docs/wiki` |
| M7 | Dormant Swift gates proven | First code pull request | `ios`, coverage and CodeQL Swift jobs run green |
| M8 | Legal review of the V1 items in the compliance roadmap | V1 submission | Review complete; documents updated |
| M9 | Rulesets applied | Before the second pull request merges | `integration`, `main` and tag rulesets active with the checks that report |

## Gaps (not blockers)

- Customer hypotheses (switch, pay, stay) are untested; research studies R1 to R3 run during
  Foundation.
- Several numbers are labelled assumptions (performance budgets, AI thresholds, business targets);
  each has a validation plan and is revisited at the end of the MVP.
- Market size has no reliable public figure; the [target market](target-market.md) defines a
  bottom-up method.
- Open questions are listed in each document (for example PRD OQ-1 to OQ-5).

## Recommendations

1. Run the PDF SDK spike first: it unblocks architecture (ADR-0007), the financial model and the
   first code. Ask both vendors for quotes at the same time.
2. Complete the Apple Developer prerequisites in parallel; they have external lead times.
3. Design the MVP flows (C5) while the spike runs, starting with onboarding and the reader.
4. Build the golden, OCR and AI evaluation corpora before the first feature, so gates have data
   from day one.
5. Apply the rulesets immediately after the foundation pull request merges, using the check names
   that reported.
6. Start research studies R1 and R2 now; they change positioning, not code, and are cheap.
7. Book legal review for the V1 compliance items early; answers can change onboarding and consent
   screens.

## Change log

| Date | Change |
|---|---|
| 2026-09-28 | First review. C4 and C6 reclassified from Critical to Major: C4 is needed only for the V2 Claude tier, and CI now runs on pull requests (decision PAP-016). |
