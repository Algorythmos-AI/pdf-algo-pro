# PDF Algo Pro documentation

Start here. This folder is the planning package and operating manual for PDF Algo Pro: what the
product is and why, how it is built, how work flows from an idea to the App Store, and every
decision behind it. The 30-minute path below gets a new engineer or agent productive; the index
lists every document with its owner hat and review cadence.

Owner: Maintainer · Reviewed: each milestone, and whenever a document is added or removed

## The 30-minute path

### Minutes 0 to 5: the product

- **What:** a native PDF reader, editor and scanner for iPhone and iPad, and later Mac, whose
  intelligence (summaries, answers with page citations, data extraction) runs on the device first.
- **Why it can win:** every generic PDF task is already solved by established apps; the opening is
  AI document intelligence that is **private by default, native to Apple and works offline**.
- **Why switch, pay, stay:** documents get smarter without leaving the device and without an
  account; one honest subscription after value is shown for free; a private library that can be
  searched and questioned.
- **Seven pillars** (every requirement maps to at least one): PIL-1 Document Reading, PIL-2 Document
  Editing, PIL-3 OCR & Scanning, PIL-4 AI Document Intelligence, PIL-5 Privacy, PIL-6 Offline
  Capability, PIL-7 Native Apple Experience.
- Read: [product positioning](product-positioning.md), then "Moat thesis" and "Why 'uses Apple's
  model' is not the moat" in the [competitive moat](competitive-moat.md).

### Minutes 5 to 15: how it is built

- Swift 6 on iOS and iPadOS 27; XcodeGen with local Swift packages; SwiftUI and Observation;
  documents in iCloud Drive; a commercial PDF SDK behind the `PDFEngine` boundary (vendor chosen by a
  spike; [ADR-0007](adr/0007-pdf-sdk-boundary-and-vendor-selection.md) is still Proposed);
  intelligence through Apple's Foundation Models framework: on device in the MVP, Private Cloud
  Compute from V1, an opt-in Claude tier from V2.
- Read: the decision summary table at the top of the
  [iOS architecture review](ios-architecture-review.md), the [ADR index](adr/README.md), and
  "How the router decides" in [model selection](model-selection.md).

### Minutes 15 to 25: how we work

- Work branches squash-merge into `integration` (staging, internal TestFlight); releases are promoted
  to `main` (App Store). Every pull request passes the quality gates. Decisions are recorded.
- Read: "The model" in [branching](process/branching.md), the gates table in
  [quality gates](process/quality-gates.md), "How work flows" in the
  [engineering playbook](engineering-playbook.md), and the hard rules in [AGENTS.md](../AGENTS.md)
  (what never goes in this public repository) with [SUPERVISION](../.github/SUPERVISION.md).

### Minutes 25 to 30: where things are now

- Read: [working memory](working-memory.md) (current state) and the
  [readiness review](readiness-review.md) (what must happen before code).
- Requirements have IDs in the [PRD](prd.md); planned work is in the
  [backlog](planning/backlog.yaml); decisions are in the [decision register](decision-register.md).

### Check yourself

After the path you should be able to answer: What is PDF Algo Pro and who is it for? What is the
moat? What are the seven pillars? Where does intelligence run, and when does data leave the device?
Which branch does a pull request target, and what must pass? Where are decisions recorded? What
blocks implementation today?

## Index


### Start here

| Document | Owner | Reviewed |
|---|---|---|
| [Working memory](working-memory.md) | Maintainer | every pull request that changes state; at least monthly |
| [Readiness review](readiness-review.md) | Maintainer | weekly until the verdict is READY, then at the start of each milestone |
| [Decision register](decision-register.md) | Maintainer | each milestone |

### Product strategy

| Document | Owner | Reviewed |
|---|---|---|
| [Product requirements document](prd.md) | Product | each milestone |
| [Product positioning](product-positioning.md) | Product | each milestone, and before any App Store listing change |
| [Competitive moat](competitive-moat.md) | Product | each milestone, and whenever a competitor ships a major AI or privacy change |
| [Target market](target-market.md) | Product | each milestone, and after each customer research study |
| [Customer research](customer-research.md) | Product | after each study, and at each milestone |
| [Founder principles](founder-principles.md) | Maintainer | yearly, or when a principle is challenged by a real decision |
| [Non-goals](non-goals.md) | Product | each milestone |
| [Success metrics](success-metrics.md) | Product | each milestone |
| [Roadmap](product/roadmap.md) | Product | at the end of each phase |

### Business

| Document | Owner | Reviewed |
|---|---|---|
| [Pricing strategy](pricing-strategy.md) | Product | before V1 submission, then each quarter |
| [Revenue model](revenue-model.md) | Product | each quarter |
| [Unit economics](unit-economics.md) | Product | each quarter, and whenever a price, commission or AI price changes |
| [Financial model](financial-model.md) | Product | each quarter, after the PDF SDK quote, and at each milestone |

### Apple platform and architecture

| Document | Owner | Reviewed |
|---|---|---|
| [iOS architecture review](ios-architecture-review.md) | Architecture | each milestone, and whenever an ADR changes |
| [Platform strategy](platform-strategy.md) | Product and Architecture | at each platform launch decision |
| [Design system](design-system.md) | Design | each milestone, and whenever a token or component changes |
| [PDF text editing architecture](pdf-text-editing-architecture.md) | Architecture and PDF engine | each milestone, and whenever the editor's supported cases change |
| [Performance budgets](performance-budgets.md) | Architecture | each milestone, and after each MetricKit review |

### AI governance

| Document | Owner | Reviewed |
|---|---|---|
| [AI governance](ai-governance.md) | AI | quarterly, after any AI incident, and before any provider, model or consent change |
| [AI evaluation framework](ai-evaluation-framework.md) | AI | each milestone, and whenever a threshold, evaluation set or judge changes |
| [Prompt management](prompt-management.md) | AI | each milestone, and when the Foundation Models framework or a provider package changes |
| [Model selection](model-selection.md) | AI | quarterly, on every iOS release and beta, and when a provider changes its models or terms |

### Security, privacy and compliance

| Document | Owner | Reviewed |
|---|---|---|
| [Privacy architecture](privacy-architecture.md) | Privacy | each milestone, and before any change that sends data off the device |
| [Data classification](data-classification.md) | Privacy | each milestone, and whenever a new data type, storage location or recipient is added |
| [Threat model](threat-model.md) | Security | each milestone, when a trust boundary changes, and after every security incident |
| [Compliance roadmap](compliance-roadmap.md) | Privacy | each milestone, and whenever a law, an Apple guideline or a data flow changes |

### Engineering

| Document | Owner | Reviewed |
|---|---|---|
| [Engineering playbook](engineering-playbook.md) | Architecture | each milestone |
| [Coding standards](coding-standards.md) | Architecture | each milestone, and whenever an ADR changes |
| [Swift style guide](swift-style-guide.md) | Architecture | after each WWDC, when a new Xcode or Swift version is adopted, and each milestone |
| [Code review guide](code-review-guide.md) | Maintainer | each milestone, and whenever a role is assigned to a new person |
| [Testing strategy](testing-strategy.md) | Quality | each milestone, and when a new Xcode version is adopted |

### GitHub operating system and knowledge

| Document | Owner | Reviewed |
|---|---|---|
| [GitHub governance](github-governance.md) | Maintainer | each milestone, and whenever a ruleset, template or label file changes |
| [Repository standards](repository-standards.md) | Maintainer | quarterly, and when the organisation standards change |
| [Release management](release-management.md) | Release | each release, and each milestone |
| [Project management](project-management.md) | Product | each milestone |
| [Changelog and release notes](changelog-strategy.md) | Release | each release |
| [Wiki plan](wiki-plan.md) | Maintainer | each milestone |

### Process and runbooks

| Document | Owner | Reviewed |
|---|---|---|
| [Branching and merging](process/branching.md) | Release | each milestone, and whenever a ruleset or `ci.yml` changes |
| [Environments](process/environments.md) | Release | each milestone |
| [Quality gates](process/quality-gates.md) | Quality | each milestone, and with any change to a workflow, ruleset or threshold |
| [VoiceOver script](process/voiceover-script.md) | Quality and Design | each milestone, and whenever a screen or journey is added |
| [Device smoke test](process/device-smoke-test.md) | Quality | whenever a build adds a feature only a device can show |
| [Text editing device test](process/text-editing-device-test.md) | Quality and PDF engine | whenever the editor's supported cases change, and before the release flag is removed |
| [Localisation](process/localization.md) | Product and Design | each milestone, and whenever a language is added |
| [App Store submission](process/runbooks/app-store-submission.md) | Release | after each release |
| [iOS hotfix](process/runbooks/ios-hotfix.md) | Release | after each hotfix |
| [Incident response](process/runbooks/incident-response.md) | Operations | after every SEV1 or SEV2, and each milestone |
| [Kill switch](process/runbooks/kill-switch.md) | Operations | each milestone, and after every use |
| [AI provider failover](process/runbooks/ai-provider-failover.md) | AI | each milestone, and after every failover |

### Operations and go-to-market

| Document | Owner | Reviewed |
|---|---|---|
| [Operations](operations.md) | Operations | each milestone, after every SEV1 or SEV2, and before each App Store release |
| [Analytics strategy](analytics-strategy.md) | Product and Privacy | each milestone, and whenever the tracking plan changes |
| [App Store strategy](app-store-strategy.md) | Product | before each App Store submission, and each milestone |

### Organisation

| Document | Owner | Reviewed |
|---|---|---|
| [Algorythmos alignment](algorythmos-alignment.md) | Maintainer | each milestone, and when an organisation standard changes |

### Also in this folder

- [Planning backlog](planning/backlog.yaml): planned work as code, synced to issues.
- [Architecture decision records](adr/README.md): ADR-0001 to ADR-0026.
- [Wiki source](wiki/Home.md): curated pages published to the GitHub wiki ([wiki plan](wiki-plan.md)).

## Conventions

- **Evidence:** every claim cites a source; every number is sourced or labelled `Assumption:` with
  a validation plan. The docs gate warns on unsourced numbers.
- **Major decisions** record rationale, trade-offs, alternatives considered, risks and future
  scalability impact.
- **Public repository:** business-sensitive documents are redacted editions; a confidential edition
  is held privately. Nothing here links to private material.
- **Spelling:** Australian/British English in documents; US English in code identifiers.
