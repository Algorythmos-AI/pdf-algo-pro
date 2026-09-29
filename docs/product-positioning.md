# Product positioning

How PDF Algo Pro describes itself: the category it competes in, who it is for, the positioning
statement, the messaging pillars and the proof behind each one. Every piece of copy (App Store
listing, website, onboarding, release notes) is checked against this document. The strategic
reasoning behind it is in the [competitive moat](competitive-moat.md).

Owner: Product · Reviewed: each milestone, and before any App Store listing change

## Category

**Premium native PDF productivity app for iPhone, iPad and Mac**, listed in Productivity (primary)
and Business (secondary), as set out in the [App Store strategy](app-store-strategy.md). We do not
position as an "AI chatbot for PDFs": that frames the product as a thin wrapper and invites
comparison with free system features. Intelligence is the reason to choose us inside the PDF
category.

## Who it is for

The primary audience is people on Apple devices who work with documents they would rather not
upload anywhere: contracts, statements, medical and insurance papers, identity documents, research
and client files. Segment definitions, the ideal customer profile and the sizing method are in the
[target market](target-market.md).

## Positioning statement

For people who live on iPhone, iPad and Mac and handle documents that matter, **PDF Algo Pro** is the
PDF app that **understands your documents without taking them from you**. Unlike PDF apps whose AI
sends your files to the cloud and asks you to sign in, PDF Algo Pro reads, answers and extracts on
your device, works offline, and fits into Apple's apps and shortcuts like it was built there.

## Messaging pillars

| Pillar | Message | Proof points (must stay true) | Product pillars |
|---|---|---|---|
| Understands your documents | Ask a question and get an answer that shows the page it came from. Summarise, extract data, analyse a contract. | Page citations on every answer; extraction to structured fields; evaluation results before each release ([AI evaluation framework](ai-evaluation-framework.md)) | PIL-4 |
| Stays on your device | Your documents are read on your iPhone. Nothing is uploaded unless you choose a cloud option, and we tell you exactly what and where. | On-device first ([ADR-0009](adr/0009-tiered-ai-and-consent.md)); consent that names the provider and the data; privacy label goal in the [privacy architecture](privacy-architecture.md); no account | PIL-5 |
| Works anywhere | Read, scan, search and ask questions on a plane or underground. | On-device OCR and intelligence on supported devices; [offline behaviour](ai-governance.md) documented | PIL-6 |
| Feels like Apple made it | Open from Files, scan from Control Center, find a clause with Spotlight, ask Siri. | The [Apple-first capability baseline](adr/0022-apple-first-capability-baseline.md) | PIL-7 |
| Everything you expect from a PDF app | Read, annotate, sign, edit, organise, convert, scan. | [PRD](prd.md) feature set | PIL-1, PIL-2, PIL-3 |

Order matters: lead with outcomes (understanding), then the reason to trust it (privacy), then
convenience. Never lead with the word "AI" alone.

## Why switch, why pay, why stay (public summary)

- **Switch:** your documents get smarter without leaving your device, and there is no account to
  create.
- **Pay:** editing, redaction, conversion and deeper intelligence in one honest subscription across
  your Apple devices, after you have already seen the value for free.
- **Stay:** your library becomes a private knowledge base you can search and question, and the app
  improves every release.

Each is a hypothesis with a test in the [competitive moat](competitive-moat.md) and
[customer research](customer-research.md).

## Onboarding language

The first question is "What do you do with PDFs most often?". Answer options, in this order:

1. Chat with PDF
2. Summarise document
3. Extract data with AI
4. Analyse contract, with the disclosure "Not legal advice. Check important terms with a qualified
   professional."
5. Edit PDF text
6. Annotate or highlight
7. Sign
8. Convert PDF to Word, Excel or PowerPoint
9. Merge or organise pages
10. Read or view
11. Scan to PDF
12. All tools

The choice personalises the home screen; the question can be skipped; no paywall appears before the
first completed task ([PRD](prd.md), FR-ONB requirements). The first four are the AI-first options
because they show the differentiator in the first minute; when the device cannot run the on-device
model, they explain what they need and point to the non-AI tools (from V2, Pro users can also opt
in to the Claude tier), and never fail silently.

## Words we use and avoid

| Use | Avoid | Why |
|---|---|---|
| "on your device", "private by default" | "100% private", "military-grade" | Absolute claims are untestable; cloud tiers exist when the user opts in |
| "answers with the page they came from" | "never wrong", "hallucination-free" | Models make mistakes; citations let people check |
| "on supported devices" | "works on every iPhone" | On-device intelligence needs an Apple Intelligence-capable device ([Foundation Models availability](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/availability-swift.enum/unavailablereason)) |
| "Analyse contract (not legal advice)" | "AI lawyer", "legal review" | Avoids implying professional advice; Apple's acceptable-use requirements bar unsupervised high-impact legal decisions ([requirements](https://developer.apple.com/apple-intelligence/acceptable-use-requirements-for-the-foundation-models-framework)) |
| "PDF Algo Pro, built by Algorythmos" | Copy that implies a large team | Algorythmos is a single-person company today |
| Competitor names only in comparison pages that meet App Store rules | Disparaging competitors | App Review Guideline 2.3 (accurate metadata) and basic fairness |

## Decision: position on private intelligence inside the PDF category

- **Rationale.** People search the App Store for PDF tasks, not for "document intelligence"; being in
  the PDF category captures that demand, and private intelligence is the reason to pick us there.
- **Trade-offs.** We are compared directly with long-established apps on basic features, so basic
  quality must be high from the first release.
- **Alternatives considered.** Position as an AI assistant (competes with free system features and
  general chat apps); position as a privacy tool (too narrow; privacy is the reason to trust, not
  the job to be done); position on price (a race to the bottom).
- **Risks.** Privacy messaging may not convert; "AI" fatigue. Both are tested with message
  experiments before launch ([customer research](customer-research.md)).
- **Future scalability impact.** The positioning holds across iPad, Mac and later visionOS, and
  across new models, because it rests on where processing happens and how answers are grounded, not
  on a specific model.

**Pillars served.** All seven, led by PIL-4, PIL-5 and PIL-7.
