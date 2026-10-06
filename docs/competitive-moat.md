# Competitive moat

Why PDF Algo Pro can win and keep customers in a category where every generic PDF task is already
solved. This public edition covers the landscape at category level, the moat thesis and the
explicit answers to "why would someone switch, pay and stay", each stated as a hypothesis to test.
The full competitor teardown, pricing comparison and defensibility scoring are in a confidential
edition held privately.

Owner: Product · Reviewed: each milestone, and whenever a competitor ships a major AI or privacy change

## The starting point: parity is the entry fee

Reading, annotation, signing, editing, conversion, page organisation and scanning are offered by
every established PDF app on the App Store, including Adobe Acrobat Reader, PDF Expert, UPDF, Foxit
PDF Editor and Smallpdf (their App Store listings, accessed 2026-09-28:
[Acrobat](https://apps.apple.com/us/app/adobe-acrobat-reader-pdf-maker/id469337564),
[PDF Expert](https://apps.apple.com/us/app/id743974925),
[UPDF](https://apps.apple.com/us/app/id1595826623),
[Foxit](https://apps.apple.com/us/app/id507040546),
[Smallpdf](https://apps.apple.com/us/app/id1485259500)). PDF Algo Pro must match the tasks people use
daily (see the [PRD](prd.md)), but matching them is not a reason to switch.

## What the market leaves open

Findings from public sources, accessed 2026-09-28:

- **AI in leading PDF apps is cloud-first.** Adobe states that its generative features involve cloud
  processing and require being online and signed in
  ([usage policy](https://helpx.adobe.com/acrobat/desktop/use-acrobat-ai/understand-usage-policies/ai-usage-policy-limitations.html),
  [technical requirements](https://helpx.adobe.com/acrobat/desktop/use-acrobat-ai/get-started-with-generative-ai/ai-tech-requirements.html)).
  UPDF's AI uploads the document to its cloud ([privacy policy](https://updf.com/privacy-policy/)).
  Foxit's offline "Local AI" is limited to desktop, and its mobile workflows use an uploaded
  processing path ([security overview](https://www.foxit.com/company/ai-assistant-security-privacy/)).
- **No public evidence** was found that these apps use Apple's Foundation Models framework or
  Private Cloud Compute. This is unverified either way and is re-checked at every review.
- **Recurring review themes** across the category, from Apple's public review feeds: frustration
  with trial-to-subscription billing, forced sign-in, and AI features that open uninvited or cannot
  be turned off. Samples are small and skew negative; they show direction, not frequency.
- **Apple's own substitutes** cover the basics for free: Preview on iPhone and iPad fills, signs,
  scans and marks up PDFs ([listing](https://apps.apple.com/us/app/preview/id536344167)), and Siri
  in iOS 27 can answer questions about content on screen
  ([Apple Newsroom, 2026-09-14](https://www.apple.com/newsroom/2026/09/major-updates-for-apples-software-platforms-are-now-available/)).

## Moat thesis

PDF Algo Pro is **the PDF app that understands your documents without taking them from you**. The
moat is **AI document intelligence that is private by default, native to Apple and works offline**,
built in four reinforcing layers:

1. **Private-by-architecture intelligence.** On-device first; Apple Private Cloud Compute second;
   a third-party model only with named, revocable consent, as
   [App Review Guideline 5.1.2(i)](https://developer.apple.com/app-store/review/guidelines/#data-use-and-sharing)
   requires. No account needed. See [ADR-0009](adr/0009-tiered-ai-and-consent.md) and the
   [privacy architecture](privacy-architecture.md).
2. **Grounded, verifiable answers.** Every answer and extraction cites the page it came from, and the
   citation opens that page. Quality is measured by the
   [AI evaluation framework](ai-evaluation-framework.md), not asserted.
3. **Native Apple depth.** Documents as App Intents entities for Siri and Spotlight, Control Center
   scan, Share and Action extensions, widgets, open in place from Files, multi-window on iPad
   ([ADR-0022](adr/0022-apple-first-capability-baseline.md)).
4. **Trust as a business model.** No trial traps (a reminder before a trial ends, and an offer
   that closes at once), no forced sign-in, AI that can be hidden, no paywall on the user's own
   files ([founder principles](founder-principles.md)).

The layers compound. Private intelligence makes people willing to bring sensitive documents; more
documents make library-wide answers more valuable; native integration puts the app where documents
arrive; trust keeps subscriptions renewing.

**Why "uses Apple's model" is not the moat.** Foundation Models is available to every developer,
and Siri can already answer questions about what is on screen. The moat is depth that takes time to
build: whole-document and whole-library answers with citations, structured extraction, system
integration and a trustworthy business model. Siri is treated as a channel (through App Intents),
not only as a substitute.

## Why would someone switch?

| # | Hypothesis | Evidence behind it | How it is tested |
|---|---|---|---|
| SW-1 | People who handle sensitive documents avoid uploading them to AI services, and will switch to an app whose AI runs on the device | Cloud-first AI across the leading apps (above) | Interviews and message tests ([customer research](customer-research.md)) |
| SW-2 | Users who feel misled by billing practices are open to a transparent alternative | Recurring review themes | Review mining; beta sign-up questions |
| SW-3 | Users annoyed by intrusive AI prefer AI that is opt-in and quiet | Recurring review themes | Beta usability sessions |
| SW-4 | People who need answers offline have no alternative on iPhone today | Online requirements documented above | Interviews; offline share in opt-in aggregated telemetry |

Switching barriers the product removes: annotated PDFs open without loss, files open in place from
Files and other apps, and no account is needed.

## Why would someone pay?

| # | Hypothesis | How it is tested |
|---|---|---|
| PAY-1 | Editing, redaction, conversion and advanced intelligence are worth a subscription when the free tier is honestly useful | Trial and conversion against the financial model's assumptions |
| PAY-2 | Private, offline intelligence is a reason to pay, not only a reason to try | Paywall message tests; willingness-to-pay interviews |
| PAY-3 | One subscription across iPhone, iPad and Mac is expected | Survey; purchase mix after the Mac launch |

Pricing principles are in the [pricing strategy](pricing-strategy.md).

## Why would someone stay?

| # | Hypothesis | Mechanism |
|---|---|---|
| ST-1 | A library that can be asked questions becomes more valuable with every document | On-device index and retrieval across the library |
| ST-2 | Integration into daily paths creates habit | Spotlight, Siri, Share sheet, Control Center, widgets |
| ST-3 | Trust earned through transparent billing and privacy keeps renewals high | No dark patterns; clear cancellation |
| ST-4 | Visible improvement every release justifies renewal | Release cadence; rising evaluation scores ([Guideline 3.1.2](https://developer.apple.com/app-store/review/guidelines/#subscriptions) expects ongoing value) |

There is deliberately no lock-in: documents remain standard PDFs in the user's own storage and the
index can be rebuilt. People stay because of value.

## Decision: compete on private intelligence, not on feature parity

- **Rationale.** Parity cannot win against incumbents with years of polish and large installed
  bases; private, offline, native intelligence is an opening the market leaves and the one the
  seven pillars are built around.
- **Trade-offs.** The on-device model is small (4,096 tokens per session,
  [Managing the context window](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window))
  and needs an Apple Intelligence-capable device, so some capabilities depend on the opt-in cloud
  tiers or are unavailable on older iPhones.
- **Alternatives considered.** A cheaper all-in-one editor (a price race against funded
  incumbents); a cloud AI assistant like the incumbents' (no differentiation, higher cost, weaker
  privacy); a note-taking app (a different category).
- **Risks.** Competitors adopt Apple's on-device model; Apple adds PDF intelligence to its own apps;
  privacy may not drive purchase for enough users. Each has a monitoring signal and a response in
  the confidential edition.
- **Future scalability impact.** The architecture keeps intelligence behind one router
  ([ADR-0021](adr/0021-ai-provider-routing-and-failover.md)), so the product can add better models as
  Apple and providers ship them without changing features.

**Pillars served.** PIL-4 AI Document Intelligence, PIL-5 Privacy, PIL-6 Offline Capability, PIL-7
Native Apple Experience.
