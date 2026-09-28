# Working memory

The living state of PDF Algo Pro: where the project is, what is in flight, the top risks, open
questions, recent decisions and known issues. Read it first when you pick up work; update it in any
pull request that changes the state (the pull request template asks). It is short on purpose: detail
lives in the linked documents.

Owner: Maintainer · Reviewed: every pull request that changes state; at least monthly

Last updated: 2026-09-29

## Current phase

**Foundation.** The planning package is written; the implementation readiness gate is **NOT READY**
with four Critical blockers open ([readiness review](readiness-review.md)). The native iOS foundation
app is being built under the owner's exception (PAP-028), on an interim iOS 26 toolchain (PAP-029).

## In flight

| Item | State | Next step |
|---|---|---|
| Foundation pull request [#1](https://github.com/Algorythmos-AI/pdf-algo-pro/pull/1) (repository, governance, CI) | Open; CI green except CodeQL upload | Owner switches CodeQL to advanced setup; merge |
| Planning package pull request [#2](https://github.com/Algorythmos-AI/pdf-algo-pro/pull/2) (this documentation) | Open, stacked on #1 | Rebase onto `integration` after the foundation merges |
| Foundation app pull request [#3](https://github.com/Algorythmos-AI/pdf-algo-pro/pull/3) (native iOS app, PAP-028) | Open, stacked on #2; first run of the `ios` job | Owner review; merge after #2 |
| Organisation catalog entry | Catalog entry pending owner review | Owner review and merge |
| Backlog issues | 36 issues synced from `docs/planning/backlog.yaml`, on the project board | Owner creates the project views and built-in workflows in the web interface |
| Rulesets (readiness M9) | Defined as code in `.github/rulesets`; not yet applied | Apply the `integration`, `main` and tag rulesets with the checks that reported, before the second pull request merges |

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
| PAP-029 | Interim iOS 26 floor and Xcode 26 in CI until Xcode 27 builds (C2) |
| PAP-028 | Owner exception: the foundation app is built before the readiness gate clears |
| PAP-027 | Phases aligned to the PRD; opt-in telemetry moves to V2 |
| PAP-026 | Phased PDF SDK licence allowed if the quote requires it |
| PAP-025 | `main` requires checks on the release head, not up to date with `main` |
| PAP-024 | Remote configuration never delivers new prompt text |
| PAP-023 | Comply with the Australian Privacy Principles regardless of exemption |
| PAP-022 | JavaScript in PDFs disabled |
| PAP-021 | Extensions use the on-device tier only |
| PAP-020 | Analyse Contract never uses the Claude tier |

## Known issues

- `codeql (actions)` analysis succeeds but its upload is rejected while CodeQL default setup is
  enabled on the repository; not a required check until fixed (backlog F-010).
- The iOS job runs on the interim Xcode 26 toolchain with an `iPhone 17` on the iOS 26 runtime, and
  creates that simulator if the runner image lacks it (PAP-029, backlog F-002).
- The live on-device model tests (`LiveModelTests`) are opt-in: the development Mac has Apple
  Intelligence turned off, and CI runners have no model. Run them with `PDFALGOPRO_LIVE_MODEL=1`.
- The simulator reports the on-device model as available but has no model assets, so real answers
  fail there with the "didn't finish" message; UI tests use the scripted router instead.
- Release and performance test plans run in Xcode Cloud, not GitHub Actions; the performance-budget
  comparison script is still to be written ([testing strategy](testing-strategy.md)).
