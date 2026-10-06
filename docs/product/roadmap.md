# Roadmap

The order in which PDF Algo Pro is built, phase by phase. Every item serves at least one pillar
(PIL-1 Document Reading · PIL-2 Document Editing · PIL-3 OCR & Scanning · PIL-4 AI Document
Intelligence · PIL-5 Privacy · PIL-6 Offline Capability · PIL-7 Native Apple Experience). Phases are
outcomes, not dates: a phase ends when its exit criteria are met. Requirements behind each item are
in the [PRD](../prd.md); milestones on GitHub carry the same names.

Owner: Product · Reviewed: at the end of each phase

## Phase overview

| Phase | Outcome | Platform | Exit criteria |
|---|---|---|---|
| **Foundation** | Planning package, readiness gate cleared, toolchain and repository ready | — | No open Critical blocker in the [readiness review](../readiness-review.md) |
| **MVP** | First TestFlight build proving the core loop: capture or open, read, understand, fill and sign | iPhone | MVP requirements met; performance budgets met on reference iPhones; internal TestFlight crash-free ≥ 99.8% |
| **V1** | First App Store release: edit, organise, subscribe, in English and French | iPhone (adaptive on iPad) | V1 requirements met; external TestFlight beta complete; App Store approval |
| **V1.1** | Refinement from real use: quality, performance, accessibility, top requested gaps | iPhone (adaptive on iPad) | Crash-free and rating objectives held for a full release cycle |
| **V2** | iPad-first experience; Mac; the opt-in Claude tier at general availability (Private Cloud Compute arrives in V1) | iPad, Mac | iPad and Mac exit criteria in [platform strategy](../platform-strategy.md); relay in production |
| **Later** | Compatible app on Apple Vision Pro; native visionOS only with evidence | visionOS | Entry criteria in [platform strategy](../platform-strategy.md) |

## Foundation

| Item | Pillars |
|---|---|
| Planning package, ADRs, governance, quality gates | all |
| PDF SDK vendor spike and licence (C1) | PIL-1, PIL-2, PIL-3 |
| Xcode 27 toolchain locally and in CI (C2) | PIL-7 |
| Apple Developer Program prerequisites and identifiers (C3) | PIL-7 |
| Information architecture, key flows and the Figma library (C5) | PIL-7 |
| Document-identity spike; golden PDF and OCR corpora | PIL-1, PIL-3, PIL-6 |

## MVP (iPhone, internal TestFlight)

| Item | Pillars |
|---|---|
| Library in iCloud Drive with folders, tags, recents, search (titles, tags, OCR text) | PIL-1, PIL-6, PIL-7 |
| Fast, accessible reader: large documents, outline, thumbnails, text selection, read aloud | PIL-1, PIL-7 |
| Annotate and highlight | PIL-1, PIL-2 |
| Fill forms; sign with ink signatures kept in the Keychain | PIL-2, PIL-5 |
| Scan with the document camera; on-device OCR; searchable PDFs | PIL-3, PIL-5, PIL-6 |
| On-device intelligence: summarise, ask with page citations, extract fields | PIL-4, PIL-5, PIL-6 |
| Onboarding intent picker (AI-first options on top); replaced in V1 by the introduction pages | PIL-4, PIL-7 |
| Share extension, App Intents, Spotlight, Files integration, drag and drop | PIL-7 |
| Privacy manifest, MetricKit, on-device diagnostics | PIL-5 |

## V1 (App Store)

| Item | Pillars |
|---|---|
| Edit existing text, images and links (PDF SDK) | PIL-2 |
| Organise pages: merge, split, reorder, rotate, delete, extract | PIL-2 |
| True redaction | PIL-2, PIL-5 |
| Convert to Word, Excel and PowerPoint (on device if the chosen SDK supports it) | PIL-2 |
| Password protection and app lock | PIL-5 |
| "Analyse Contract" with a not-legal-advice disclosure | PIL-4 |
| Opt-in Private Cloud Compute tier for long documents | PIL-4, PIL-5 |
| First-run introduction pages, a one-time tip on Home | PIL-4, PIL-7 |
| Subscriptions (StoreKit 2): weekly and annual plans, a closable offer at the end of first run, a free daily allowance, a confirmation after purchase | PIL-5, PIL-7 |
| Widgets, Control Center scan control, Action extension | PIL-7 |
| English and French throughout | PIL-7 |

## V1.1

| Item | Pillars |
|---|---|
| Performance and accessibility improvements from MetricKit and support | PIL-1, PIL-7 |
| Translation of documents on device | PIL-4, PIL-6 |
| Compare two versions of a document | PIL-1, PIL-4 |
| Top requested gaps, each checked against the [non-goals](../non-goals.md) | varies |

## V2

| Item | Pillars |
|---|---|
| iPad-first: three columns, multiple windows, Apple Pencil, keyboard and menu bar | PIL-1, PIL-2, PIL-7 |
| Native Mac app (universal purchase) | PIL-1, PIL-2, PIL-7 |
| Handoff of the open document and page between devices | PIL-7 |
| AI tier provider terms, spend caps and relay design (C4, a Major blocker needed by V2; decision PAP-016) | PIL-4, PIL-5 |
| Opt-in Claude tier through the relay; per-user entitlements and quotas | PIL-4 |
| Ask across the whole library (on-device retrieval) | PIL-4, PIL-6 |
| Opt-in aggregated telemetry through the relay | PIL-5 |

## Principles for changing the roadmap

- A new item names its pillars and passes the non-goals check.
- Moving an item between phases is recorded in the [decision register](../decision-register.md).
- Dates are communicated only for the next phase, and only when its blockers are cleared.
