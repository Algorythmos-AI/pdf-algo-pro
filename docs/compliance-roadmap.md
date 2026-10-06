# Compliance roadmap

The legal, regulatory and platform obligations that apply to PDF Algo Pro, their status today, and
when each must be met, sequenced by milestone (Foundation, MVP, V1, V1.1, V2). It covers privacy law
(Australia's Privacy Act 1988 and the Australian Privacy Principles, the EU and UK GDPR), AI
transparency (App Review Guideline 5.1.2(i) and Article 50 of the EU AI Act), Apple's App Store
requirements, data retention, accessibility and export control. Each item has an owner hat, an exit
criterion and a flag for legal review. **This document is a plan, not legal advice:** any item
marked "Yes" under legal review is a working position until a qualified adviser confirms it.

Owner: Privacy · Reviewed: each milestone, and whenever a law, an Apple guideline or a data flow changes

## How to read this

- **Milestones** follow the [roadmap](product/roadmap.md): Foundation (planning and readiness), MVP
  (internal TestFlight, on-device features), V1 (first App Store release, including the opt-in
  Private Cloud Compute tier and subscriptions), V1.1 (refinement), V2 (iPad, Mac, the Claude tier
  through the relay, and opt-in telemetry). An obligation sits in the first milestone whose scope
  triggers it.
- **Status** (as of 2026-09-28, before any application code): *Decided* (designed and recorded, not
  yet built) · *In progress* · *Planned* · *Not applicable* (with the reason) · *Monitor* (a law or
  proposal not yet in force).
- **Owner hats** are the hats in [GitHub governance](github-governance.md#roles-hats) (here mostly
  Privacy, Security, AI, Product and Release). Decision rights, including the Privacy hat's over data
  leaving the device, consent, the privacy label and the privacy manifest, are set by
  [SUPERVISION](../.github/SUPERVISION.md); this roadmap does not change them. Today the maintainer
  wears every hat.
- **Legal review "Yes"** means the item depends on a legal interpretation that has not yet been
  confirmed. The consolidated list is in [Needs legal review](#needs-legal-review).
- Data flows are in [privacy architecture](privacy-architecture.md), data classes in
  [data classification](data-classification.md), threats in the [threat model](threat-model.md), and
  the App Store checklist in [App Store strategy](app-store-strategy.md).

## Which regimes apply

| Regime | Why it may apply | Working position | Legal review |
|---|---|---|---|
| **Privacy Act 1988 (Cth) and the APPs** | The publisher, Algorythmos Pty Ltd, is Australian. Businesses at or below the small-business annual turnover threshold in the Privacy Act 1988 are generally exempt, with exceptions, and may opt in ([OAIC: small business](https://www.oaic.gov.au/privacy/privacy-guidance-for-organisations-and-government-agencies/organisations/small-business)) | Whether the exemption applies depends on facts assessed privately. **The product complies with the APPs regardless** (decision below). The statutory tort for serious invasions of privacy, in force since 10 June 2025, is not limited to APP entities ([OAIC: statutory tort](https://www.oaic.gov.au/privacy/your-privacy-rights/more-privacy-rights/statutory-tort-for-serious-invasions-of-privacy)) | Yes |
| **GDPR (Regulation (EU) 2016/679)** | Applies to a controller outside the EU that offers goods or services to people in the EU (Art 3(2)(a)); an EU language such as French is a targeting factor ([GDPR](https://eur-lex.europa.eu/eli/reg/2016/679/oj); [EDPB Guidelines 3/2018](https://www.edpb.europa.eu/our-work-tools/our-documents/guidelines/guidelines-32018-territorial-scope-gdpr-article-3-version_en)) | Assume it applies from V1, when the app is offered in French on EU storefronts | Yes |
| **UK GDPR** | Mirrors Art 3(2) and the representative duty ([UK GDPR Art 27](https://www.legislation.gov.uk/eur/2016/679/article/27)); ICO AI guidance is under review after the Data (Use and Access) Act ([ICO: AI and data protection](https://ico.org.uk/for-organisations/uk-gdpr-guidance-and-resources/artificial-intelligence/guidance-on-ai-and-data-protection/)) | Assume it applies from V1 (English (U.K.) storefront) | Yes |
| **ePrivacy Directive Art 5(3)** | Storing or reading information on a user's device needs consent unless strictly necessary for a service the user requested ([Directive 2002/58/EC, consolidated](https://eur-lex.europa.eu/legal-content/EN/TXT/?uri=CELEX:02002L0058-20091219)) | Telemetry is opt-in, which covers it; functional storage is strictly necessary | Yes |
| **EU AI Act (Regulation (EU) 2024/1689)** | Applies to providers placing AI systems on the EU market or whose output is used in the EU (Art 2(1)(a), (c)); a provider is whoever places a system on the market under its own name (Art 3(3)) ([AI Act](https://eur-lex.europa.eu/eli/reg/2024/1689/oj)) | PDF Algo Pro is likely the **provider of an AI system** built on Apple's and Anthropic's models, so Art 50 transparency applies; it is not a general-purpose model provider ([Commission GPAI Q&A](https://digital-strategy.ec.europa.eu/en/faqs/general-purpose-ai-models-ai-act-questions-answers)) | Yes |
| **App Store Review Guidelines** | Contractual condition of distribution (last updated 8 June 2026) ([App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)) | Designed in from the start | No |
| **US export regulations** | Uploading to TestFlight or the App Store is an export from the United States subject to US export law, regardless of where the developer is based ([Complying with encryption export regulations](https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations)) | Declare encryption use at every upload | Yes |
| **Australian export controls (DSGL)** | Dual-use Category 5 covers telecommunications and information security ([Defence Strategic Goods List](https://www.defence.gov.au/business-industry/exporting/export-controls-framework/defence-strategic-goods-list)) | Assess the app's encryption against Category 5 | Yes |
| **European Accessibility Act (Directive (EU) 2019/882)** | Microenterprises providing services are exempt from its accessibility requirements (Art 4(5)) ([Directive 2019/882](https://eur-lex.europa.eu/eli/dir/2019/882/oj)) | Probably out of scope; accessibility is a product requirement anyway | Yes |

## Obligations by milestone

### Foundation

| ID | Obligation | Source | Status | Owner | Exit criterion | Legal review |
|---|---|---|---|---|---|---|
| F-01 | Applicability assessment: APP entity status, GDPR and UK GDPR scope, AI Act provider role | Table above | Planned | Privacy | A written assessment, reviewed by an adviser, recorded privately and summarised in the decision register | Yes |
| F-02 | Data inventory, classification, flows and threat model | GDPR Art 25 and 30; APP 1.2 ([APPs](https://www.oaic.gov.au/privacy/australian-privacy-principles/read-the-australian-privacy-principles)) | In progress | Privacy, Security | [Data classification](data-classification.md), [privacy architecture](privacy-architecture.md) and [threat model](threat-model.md) merged | No |
| F-03 | Record of processing activities | GDPR Art 30; Art 30(5) exempts organisations under 250 people unless processing is likely to be risky, not occasional, or includes special categories | Planned | Privacy | A record covering support email, TestFlight testers and (V2) the relay and telemetry, kept whether or not strictly required | Yes |
| F-04 | Privacy by design and by default | GDPR Art 25; APP 1.2 | Decided ([ADR-0009](adr/0009-tiered-ai-and-consent.md), [ADR-0012](adr/0012-on-device-observability.md), [ADR-0017](adr/0017-privacy-first-telemetry.md)) | Architecture | The design-review checklist asks for the data class and consent path of every new flow ([engineering playbook](engineering-playbook.md)) | No |
| F-05 | Third-party SDK governance for the PDF SDK: privacy manifest, telemetry off, offline licence, licence terms | Guideline 5.1.1(i) (third parties must protect data equally); readiness blocker C1 | In progress | Architecture, Security | [ADR-0007](adr/0007-pdf-sdk-boundary-and-vendor-selection.md) accepted with the audit results | Yes |
| F-06 | AI provider terms: Anthropic Commercial Terms, the incorporated DPA with Standard Contractual Clauses, a zero-data-retention request, workspace spend limits | GDPR Art 28 and 46; APP 8.1; readiness blocker C4 ([Anthropic DPA](https://privacy.claude.com/en/articles/7996862-how-do-i-view-and-sign-your-data-processing-addendum-dpa)) | Planned | AI | Terms reviewed and accepted for the TestFlight and production workspaces; zero-retention outcome recorded | Yes |
| F-07 | Incident response with a breach-notification decision tree | Notifiable Data Breaches scheme ([OAIC](https://www.oaic.gov.au/privacy/notifiable-data-breaches/about-the-notifiable-data-breaches-scheme)); GDPR Art 33 (72 hours to the authority where feasible) | Planned | Security | The [incident response runbook](process/runbooks/incident-response.md) includes who decides, the tests for "serious harm" and "risk", and the regulators to notify | Yes |
| F-08 | Supply-chain controls: pinned actions, dependency review, CodeQL, secret scanning | APP 11.1 and 11.3 (reasonable steps include technical and organisational measures, [POLA Act 2024](https://www.legislation.gov.au/C2024A00128/asmade/text)); GDPR Art 32 | In progress ([ADR-0013](adr/0013-ci-cd.md)) | Security | All four workflows required on `integration` and `main` ([quality gates](process/quality-gates.md)) | No |

### MVP (internal TestFlight)

| ID | Obligation | Source | Status | Owner | Exit criterion | Legal review |
|---|---|---|---|---|---|---|
| M-01 | Privacy manifest with every required-reason API and its reasons | [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files); [required reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api) | Planned | Architecture | Manifest committed with the first Swift code; `invariants` gate green | No |
| M-02 | Encryption declaration (`ITSAppUsesNonExemptEncryption`) before the first TestFlight upload | [ITSAppUsesNonExemptEncryption](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption) | Planned | Release | Key set on a documented assessment of the app's and the SDK's encryption | Yes |
| M-03 | AI disclosure for on-device features: first-use explainer, persistent AI labels, notice at the start of each conversation | EU AI Act Art 50(1) and 50(5); FR-AI-010; [AI governance](ai-governance.md) | Decided | Product, Design | Labels in snapshot tests; notice shown before the first answer | Yes |
| M-04 | On-device retention: Recently Deleted for 30 days; derived data deleted with its source | GDPR Art 5(1)(e); APP 11.2; FR-LIB-006 | Decided ([iOS architecture review](ios-architecture-review.md)) | Architecture | Library tests pass | No |
| M-05 | No real personal documents in development or testing | APP 11; GDPR Art 5(1)(c) | In progress (`invariants` gate) | Security | Gate active; evaluation sets synthetic ([testing strategy](testing-strategy.md)) | No |
| M-06 | Draft privacy policy and support page | APP 1.3 to 1.5; GDPR Art 13; Guideline 5.1.1(i) | Done 2026-10-06: version 1.0 of the policy and the support page are live (PAP-038) | Privacy | Drafts ready for review before external TestFlight (readiness item "privacy and support URLs live") | Yes |

### V1 (first App Store release)

| ID | Obligation | Source | Status | Owner | Exit criterion | Legal review |
|---|---|---|---|---|---|---|
| V1-01 | Privacy policy published and linked in App Store Connect and in the app: what is collected and why, third parties, retention and deletion, how to withdraw consent, access and correction, complaints, overseas recipients and their countries | Guideline 5.1.1(i); APP 1.4; GDPR Art 13 (recipients and transfers); OAIC asks for clear information about AI use ([OAIC AI guidance](https://www.oaic.gov.au/privacy/privacy-guidance-for-organisations-and-government-agencies/guidance-on-privacy-and-the-use-of-commercially-available-ai-products)) | In progress: published in English and French and linked in the app and the TestFlight record (PAP-038); legal review (LR-15), professional French translation and the App Store record remain | Privacy | Live in English and French, professionally translated ([App Store strategy](app-store-strategy.md)) | Yes |
| V1-02 | Privacy label: **Data Not Collected** | [App privacy details](https://developer.apple.com/app-store/app-privacy-details/) | Decided ([privacy architecture](privacy-architecture.md)) | Release | App Store Connect answers match the label table; release checklist signed (NFR-PRIV-002) | Yes (support email optional disclosure) |
| V1-03 | Consent before the Private Cloud Compute tier, naming Apple and the data | Guideline 5.1.2(i), clarified 13 November 2025 to include third-party AI ([Apple news](https://developer.apple.com/news/?id=ey6d8onl)); APP 5 | Decided ([AI governance](ai-governance.md)) | AI | Consent tests pass; App Review approves | No (whether Apple requires it for PCC stays an App Review question; we ask either way) |
| V1-04 | Cross-border analysis for Private Cloud Compute | APP 8 ([APP guidelines, chapter 8](https://www.oaic.gov.au/privacy/australian-privacy-principles/australian-privacy-principles-guidelines/chapter-8-app-8-cross-border-disclosure-of-personal-information)); GDPR Chapter V | Planned | Privacy | Written position on whether PCC processing is a use or a disclosure and a transfer, given Apple's design that no one, including Apple staff, can access the data ([Private Cloud Compute](https://security.apple.com/blog/private-cloud-compute/)) | Yes |
| V1-05 | Machine-readable marking of AI-generated text (Art 50(2)) | [AI Act](https://eur-lex.europa.eu/eli/reg/2024/1689/oj) Art 50(2); Art 50 applies from 2 August 2026, and the grace period to 2 December 2026 covers only systems placed on the market before 2 August 2026 ([Regulation (EU) 2026/1744](https://eur-lex.europa.eu/eli/reg/2026/1744/oj); [Commission Q&A](https://digital-strategy.ec.europa.eu/en/faqs/transparency-obligations-under-article-50-ai-act)) | Planned | AI | AI text inserted into a PDF carries "PDF Algo Pro AI" as annotation author; exported summaries carry a visible footer and a machine-readable metadata marker; measures compared with the [Code of Practice](https://digital-strategy.ec.europa.eu/en/policies/code-practice-ai-generated-content) and the [Commission guidelines](https://digital-strategy.ec.europa.eu/en/policies/guidelines-transparency-ai-generated-content) | Yes |
| V1-06 | "Analyse Contract" not-legal-advice disclosure | FR-AI-004, FR-ONB-005; [AI governance](ai-governance.md); [non-goals](non-goals.md) | Decided | Product | Disclosure on every surface; advice-seeking evaluation subset passes | Yes (wording) |
| V1-07 | Subscriptions: ongoing value; clear description of what the user gets before subscribing; Schedule 2 disclosures; restore and manage; no paywall before first value | Guideline 3.1.2(a) and 3.1.2(c); FR-STORE-003; FR-ONB-004 | Decided ([ADR-0011](adr/0011-storekit-2-monetisation.md), [App Store strategy](app-store-strategy.md)) | Product | App Review approval; paywall copy reviewed in both languages | Yes (consumer-law review of terms and cancellation wording) |
| V1-08 | Terms of use: Apple's standard licence agreement or a custom one | Guideline 3.1.2 disclosures link to terms | Decided (PAP-038): Apple's standard licence, with supplementary terms of use that defer to it; live. Legal review (LR-15) remains | Maintainer | Decision recorded; link live | Yes |
| V1-09 | In-app account deletion | Guideline 5.1.1(v): apps that support account creation must offer deletion in the app | **Not applicable**: no accounts ([iOS architecture review](ios-architecture-review.md)) | Product | Stays not applicable while no account can be created; reopens with any account feature (C-02) | No |
| V1-10 | Age rating questionnaire under Apple's updated system (answers required since 31 January 2026) | [Upcoming requirements](https://developer.apple.com/news/upcoming-requirements/); [Age ratings](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions) | Planned | Release | Questionnaire answered; `Assumption:` 4+ as in [App Store strategy](app-store-strategy.md), confirmed by the answers | No |
| V1-11 | Accessibility Nutrition Labels, declared only where every common task works | Voluntary now and to become required ([Overview of Accessibility Nutrition Labels](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels)) | Planned | Design | Accessibility pass per declared feature ([design system](design-system.md)) | No |
| V1-12 | EU Digital Services Act trader status declared in App Store Connect | Apple must verify and display trader contact details for EU distribution ([DSA trader requirements](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/)) | Planned | Maintainer | Status declared; any published contact details are company contacts only | Yes |
| V1-13 | EU and UK representatives (or a documented exemption) | GDPR Art 27; UK GDPR Art 27 | Planned | Privacy | Representative appointed, or the occasional and low-risk exemption reasoned in writing | Yes |
| V1-14 | Data subject and APP 12/13 requests | GDPR Art 12(3) (one month, extendable), Art 15 to 22; APP 12 and 13 | Planned | Privacy | Procedure in [operations](operations.md); self-service where data is on the device; support-mailbox handling for data Algorythmos holds | Yes |
| V1-15 | Security of personal information | APP 11 (including 11.3); GDPR Art 32 | Planned | Security | Every V1 threat in the [threat model](threat-model.md) has its test or gate green | No |
| V1-16 | Encryption and export review for the release, including password protection (FR-EDIT-006) | Apple export documentation; US export rules; DSGL Category 5 | Planned | Release | Classification recorded; any required report or documentation filed | Yes |

### V1.1

| ID | Obligation | Source | Status | Owner | Exit criterion | Legal review |
|---|---|---|---|---|---|---|
| V11-01 | Automated-decision transparency in the privacy policy, from 10 December 2026 | New APP 1.7 to 1.9, [POLA Act 2024](https://www.legislation.gov.au/C2024A00128/asmade/text), Sch 1 Pt 15 | Monitor | Privacy | Written assessment; `Assumption:` no feature makes decisions that significantly affect a person's rights or interests, so no disclosure is needed; revisited if entitlements or quotas become automated decisions | Yes |
| V11-02 | Children's Online Privacy Code (to be registered by 10 December 2026) | [OAIC: Children's Online Privacy Code](https://www.oaic.gov.au/privacy/privacy-registers/privacy-codes/childrens-online-privacy-code) | Monitor | Privacy | Applicability assessed once registered (depends on APP entity status and whether the app is "likely to be accessed by children") | Yes |
| V11-03 | Privacy Amendment (Personal Data Protection) Bill 2026 exposure draft: a new definition of disclosure, a controller and processor framework, a "fair and reasonable" test | [AGD consultation](https://consultations.ag.gov.au/rights-and-protections/privacy-reform/); [consultation paper](https://consultations.ag.gov.au/rights-and-protections/privacy-reform/user_uploads/consultation_paper.pdf) | Monitor | Privacy | Impact on the APP 8 analysis (V2-04) reviewed if the bill is introduced | Yes |
| V11-04 | On-device translation adds no new data flow | [Privacy architecture](privacy-architecture.md) | Planned | Architecture | Confirmed in design review | No |

### V2 (Claude tier through the relay, opt-in telemetry, iPad and Mac)

The Claude TestFlight beta (App Attest) runs before V2; items V2-01 to V2-07 are met, in the scope
that applies to a limited beta, before the beta opens to testers.

| ID | Obligation | Source | Status | Owner | Exit criterion | Legal review |
|---|---|---|---|---|---|---|
| V2-01 | Data protection impact assessment for the cloud AI tiers and telemetry | GDPR Art 35; the ICO says AI use involves likely high-risk processing in the vast majority of cases ([ICO accountability and governance](https://ico.org.uk/for-organisations/uk-gdpr-guidance-and-resources/artificial-intelligence/guidance-on-ai-and-data-protection/what-are-the-accountability-and-governance-implications-of-ai/)) | Planned | Privacy | DPIA approved; every `Assumption:` retention period confirmed or changed | Yes |
| V2-02 | Lawful basis for sending document content to Anthropic, including special-category data a document may contain | GDPR Art 6(1)(a), 7(3), 9(2)(a); APP 3 and 6 | Planned | Privacy | Basis recorded (working position: consent, decision below) | Yes |
| V2-03 | Transfer of EU and UK users' content to a US processor through the relay | GDPR Chapter V; the EDPB treats a non-EU controller's disclosure to its own non-EEA processor as a transfer ([EDPB Guidelines 05/2021](https://www.edpb.europa.eu/our-work-tools/our-documents/guidelines/guidelines-052021-interplay-between-application-article-3_en)); EU-US Data Privacy Framework for participating organisations or SCCs ([Commission: EU-US transfers](https://commission.europa.eu/law/law-topic/data-protection/international-dimension-data-protection/eu-us-data-transfers_en)) | Planned | Privacy | Safeguard identified (provider's framework participation or SCCs in its DPA); transfer assessment recorded; the App Attest beta, where the device calls Anthropic directly, analysed separately | Yes |
| V2-04 | Cross-border disclosure to Anthropic under APP 8 | APP 8.1, 8.2(b) and s 16C accountability ([APP guidelines, chapter 8](https://www.oaic.gov.au/privacy/australian-privacy-principles/australian-privacy-principles-guidelines/chapter-8-app-8-cross-border-disclosure-of-personal-information)); if the AI developer can access the data, the OAIC treats it as a disclosure to cover in the APP 5 notice ([OAIC AI guidance](https://www.oaic.gov.au/privacy/privacy-guidance-for-organisations-and-government-agencies/guidance-on-privacy-and-the-use-of-commercially-available-ai-products)) | Planned | Privacy | Position recorded: contractual reasonable steps (APP 8.1), express informed consent (APP 8.2(b)), or both; consent text updated to match | Yes |
| V2-05 | Processor contracts and sub-processor list: Anthropic, the relay's hosting provider | GDPR Art 28; APP 8.1 | Planned | Privacy | Contracts in place; sub-processors named in the privacy policy | Yes |
| V2-06 | Consent before the Claude tier, naming Anthropic, the data and retention | Guideline 5.1.2(i); [AI governance](ai-governance.md) | Decided | AI | Consent tests; "ask before sending" default on; App Review approval | No |
| V2-07 | Relay retention: no content stored; counters and logs limited | GDPR Art 5(1)(c) and (e); APP 11.2 | Decided ([privacy architecture](privacy-architecture.md)) | Security | Relay storage-inspection test passes; retention periods confirmed in the DPIA | Yes |
| V2-08 | Opt-in telemetry: consent before collection, even of anonymous data; ePrivacy consent | Guideline 5.1.1(ii); ePrivacy Art 5(3); [ADR-0017](adr/0017-privacy-first-telemetry.md) | Decided | Product | Off by default; toggle tested; `Assumption:` 13-month retention confirmed; aggregates assessed as anonymous or treated as personal data | Yes |
| V2-09 | Privacy label and manifest updated for the Claude tier and telemetry | [App privacy details](https://developer.apple.com/app-store/app-privacy-details/) (opt-in collection must still be disclosed) | Decided (table in [privacy architecture](privacy-architecture.md)) | Release | Label changed in the same release; release note explains why | Yes |
| V2-10 | Privacy policy and in-app notices updated: new recipients, countries, transfers, retention | APP 1.4 and 5; GDPR Art 13 | Planned | Privacy | Published before the release that ships the flows | Yes |
| V2-11 | Breach readiness for the relay, the first Algorythmos system holding personal data | NDB scheme; GDPR Art 33 and 34 | Planned | Security | Runbook drill completed on the relay | Yes |
| V2-12 | Mac App Store release: same baseline (label, manifest, encryption, accessibility labels) | As V1 | Planned | Release | Mac release checklist complete | No |

### Continuous

| ID | Obligation | Source | Status | Owner | Exit criterion | Legal review |
|---|---|---|---|---|---|---|
| C-01 | Re-read the App Review Guidelines and Apple's upcoming requirements each milestone | [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) | In progress | Release | Checklist in [App Store strategy](app-store-strategy.md) updated | No |
| C-02 | Introducing accounts triggers in-app account deletion | Guideline 5.1.1(v) | Monitor | Product | Deletion ships in the same release as account creation | No |
| C-03 | Other jurisdictions (for example US state privacy laws) | Not assessed | Monitor | Privacy | Assessed before marketing is aimed at a new jurisdiction | Yes |
| C-04 | Voluntary Australian AI guidance | [Guidance for AI Adoption](https://www.industry.gov.au/publications/guidance-for-ai-adoption) (voluntary) | Monitor | AI | Practices compared with [AI governance](ai-governance.md) at its quarterly review | No |

## AI disclosure requirements

| Requirement | Source | How PDF Algo Pro meets it | When |
|---|---|---|---|
| Disclose sharing with third-party AI and obtain explicit permission first | Guideline 5.1.2(i) ([App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)) | Per-provider, per-device consent naming the provider, data and retention ([AI governance](ai-governance.md)) | PCC at V1; Claude at its beta and V2 |
| Tell people they are interacting with an AI system unless obvious, at the latest at first interaction, accessibly | AI Act Art 50(1) and 50(5) ([AI Act](https://eur-lex.europa.eu/eli/reg/2024/1689/oj)) | Notice at the start of every conversation; AI label with the tier on every answer, including in VoiceOver labels | V1 (EU availability) |
| Mark synthetic text in a machine-readable, detectable way, unless the system performs an assistive function for standard editing or does not substantially alter the input | AI Act Art 50(2); no grace period for systems placed on the market after 2 August 2026 ([Regulation (EU) 2026/1744](https://eur-lex.europa.eu/eli/reg/2026/1744/oj)) | V1-05 above; whether summaries, answers and extractions fall under the exception is unresolved, so marking ships anyway (decision below) | V1 |
| Label AI-generated text published to inform the public on matters of public interest | AI Act Art 50(4) applies to deployers, and a deployer excludes personal non-professional use (Art 3(4)) | The app never publishes; exported summaries carry a visible AI footer that helps professional users meet their own duty | V1 |
| Identify public-facing AI tools and explain AI use in privacy notices | [OAIC AI guidance](https://www.oaic.gov.au/privacy/privacy-guidance-for-organisations-and-government-agencies/guidance-on-privacy-and-the-use-of-commercially-available-ai-products) | Labels; privacy policy section on AI tiers | V1 |
| Never present generated content as the document's own | [Founder principles](founder-principles.md) 4 and 10 | Citations, "not found" states, AI-authored annotations marked | MVP onwards |

## Data retention

The authoritative schedule is in [data classification](data-classification.md). In summary:

| Data | Retention | Status |
|---|---|---|
| Documents and derived data on the device | Controlled by the user; Recently Deleted for 30 days | Decided |
| AI activity log | `Assumption:` 30 days | Decided, to confirm in the DPIA |
| Content sent to Private Cloud Compute | Not stored, per Apple ([WWDC26 session 241](https://developer.apple.com/videos/play/wwdc2026/241/)) | Provider statement |
| Content sent to Anthropic | Deleted within 30 days by default; up to two years if flagged; zero retention by agreement ([Anthropic](https://privacy.claude.com/en/articles/7996866-how-long-do-you-store-my-organization-s-data)) | Zero-retention terms sought (F-06) |
| Relay content | None | Decided |
| Relay counters and logs | `Assumption:` counters for the current and previous billing period; logs 30 days | To confirm in the DPIA |
| Telemetry aggregates | `Assumption:` 13 months, to allow a year-on-year comparison | To confirm in legal review |
| Support correspondence | `Assumption:` 12 months after the case closes | To confirm in legal review |

## Decision: comply with the APPs whether or not the small business exemption applies

**Decision.** PDF Algo Pro meets the Australian Privacy Principles, the Notifiable Data Breaches
process and the GDPR's equivalent duties as product policy, regardless of Algorythmos Pty Ltd's
status under the small business exemption.

**Rationale.** Privacy is the product ([founder principles](founder-principles.md) 1); the GDPR is
likely to apply from V1 with similar duties; the statutory privacy tort reaches beyond APP entities
([OAIC: statutory tort](https://www.oaic.gov.au/privacy/your-privacy-rights/more-privacy-rights/statutory-tort-for-serious-invasions-of-privacy));
and the government agreed in principle to remove the exemption after consultation
([Government response to the Privacy Act Review](https://www.ag.gov.au/rights-and-protections/publications/government-response-privacy-act-review-report)).

**Trade-offs.** Process cost (privacy policy, request handling, breach assessment) earlier than the
law may strictly require.

**Alternatives considered.** Relying on the exemption until it is removed (saves effort, but
contradicts the product promise and leaves EU duties unmet). Formally opting in to the Privacy Act
(adds OAIC jurisdiction; a legal review decision, LR-01).

**Risks.** Statements in the privacy policy become commitments users and regulators can rely on:
every statement is checked against this document and the code before publication.

**Future scalability impact.** Nothing changes when the business outgrows the exemption or the law
changes.

**Pillars served.** PIL-5.

## Decision: consent is the basis for every cloud AI and telemetry flow

**Decision.** Content goes to Private Cloud Compute or Anthropic, and telemetry leaves the device,
only on the user's opt-in consent, withdrawable as easily as it was given. The Anthropic consent
text is written so that it can also serve as express informed consent under APP 8.2(b) if legal
review chooses that route.

**Rationale.** Apple requires explicit permission before sharing with third-party AI (Guideline
5.1.2(i)) and consent for usage data (5.1.1(ii)); GDPR consent must be as easy to withdraw as to give
(Art 7(3)); documents may contain special-category data, for which explicit consent is the workable
condition (Art 9(2)(a)).

**Trade-offs.** Consent must be kept current and versioned; withdrawal must stop processing
immediately; some users will never opt in, which limits telemetry coverage.

**Alternatives considered.** Contract (Art 6(1)(b)) for cloud answers the user asked for (arguable,
but does not satisfy Apple's explicit-permission rule on its own). Legitimate interests for
telemetry (Apple still requires consent). One consent for all providers (hides who receives
content).

**Risks.** Whether device-local consent records are enough to demonstrate consent (LR-10).

**Future scalability impact.** New providers add a consent screen and a record type; enterprise
editions could pre-configure consent through managed settings.

**Pillars served.** PIL-4, PIL-5.

## Decision: mark AI-generated text from the first EU release

**Decision.** From V1, AI text that leaves the answer card (inserted into a document, exported or
shared) carries a visible label and a machine-readable marker, even though the standard-editing
exception in Art 50(2) might cover some features.

**Rationale.** New systems get no grace period ([Regulation (EU) 2026/1744](https://eur-lex.europa.eu/eli/reg/2026/1744/oj));
marking is cheap for text that the app itself writes into PDFs (annotation author, document
metadata); it matches founder principle 4.

**Trade-offs.** Exported documents reveal that AI helped produce a summary, which some users may not
want; the visible footer can be removed by the user, the metadata marker cannot be switched off in
EU storefronts.

**Alternatives considered.** Relying on the exception (legal risk while the guidelines are new).
Waiting for more guidance (no grace period to wait in).

**Risks.** The chosen technique may not be judged "effective, interoperable, robust and reliable"
(Art 50(2)); reviewed against the Code of Practice each milestone.

**Future scalability impact.** Content-provenance standards for documents can replace the marker
without changing the user experience.

**Pillars served.** PIL-4, PIL-5.

## Needs legal review

| ID | Question | Items |
|---|---|---|
| LR-01 | Is Algorythmos Pty Ltd an APP entity today; should it opt in to the Privacy Act; what follows from voluntary compliance statements? | F-01 |
| LR-02 | Is data processed only on the user's device, never reaching Algorythmos, "collected" or "held" under the Privacy Act, or processed by Algorythmos as controller under the GDPR? | F-01, F-03 |
| LR-03 | Does GDPR Art 3(2) apply, and is an EU (and UK) representative required or does the Art 27(2) exemption apply? | V1-13 |
| LR-04 | Is a record of processing activities mandatory under Art 30(5)? | F-03 |
| LR-05 | Private Cloud Compute: use or disclosure (APP 8), transfer or not (Chapter V), and Apple's role? | V1-04 |
| LR-06 | Claude beta (App Attest, device to Anthropic directly): roles and transfer mechanism? | V2-03 |
| LR-07 | Claude through the relay: Chapter V safeguard and transfer assessment? | V2-03, V2-05 |
| LR-08 | APP 8 route for Anthropic (8.1 contract, 8.2(b) consent, or both), and the effect of the draft 2026 definition of "disclosure"? | V2-04, V11-03 |
| LR-09 | Lawful basis and special-category (APP sensitive information) handling for cloud AI? | V2-02 |
| LR-10 | Are device-local, versioned consent records sufficient evidence of consent (GDPR Art 7(1); APP 8.2(b))? | V2-06 |
| LR-11 | DPIA conclusions and every `Assumption:` retention period | V2-01, V2-07 |
| LR-12 | Are telemetry aggregates anonymous, and is the ePrivacy consent design sufficient? | V2-08 |
| LR-13 | EU AI Act: provider status; whether summaries, answers and extractions fall under the Art 50(2) exception; adequacy of the marking technique; whether external TestFlight counts as placing on the market | M-03, V1-05 |
| LR-14 | Privacy label: does the support email meet the optional-disclosure criteria; is Other User Content "linked" at V2? | V1-02, V2-09 |
| LR-15 | Privacy policy, terms of use, subscription and cancellation wording, and consumer-law review | M-06, V1-01, V1-07, V1-08 |
| LR-16 | "Analyse Contract" disclosure wording, and whether explaining a contract raises any legal-services concern | V1-06 |
| LR-17 | Encryption classification under US export rules and the DSGL, including PDF password protection | M-02, V1-16 |
| LR-18 | Is the European Accessibility Act out of scope (microenterprise exemption, product and service categories)? | Regimes table |
| LR-19 | DSA trader status | V1-12 |
| LR-20 | Breach notification decision tree across the NDB scheme, GDPR and UK GDPR | F-07, V2-11 |
| LR-21 | Automated-decision disclosures (APP 1.7) and the Children's Online Privacy Code | V11-01, V11-02 |

## Open questions

- When legal review is engaged, and in which order the LR items are taken (V1 blockers first:
  LR-01, LR-03, LR-13, LR-14, LR-15, LR-17, LR-19).
- Launch storefronts beyond English- and French-speaking countries, which may add regimes
  ([App Store strategy](app-store-strategy.md)).
- Whether Anthropic participates in the EU-US Data Privacy Framework, or the SCCs in its DPA are the
  transfer safeguard (V2-03).
- Relay hosting provider and region (V2-05), shared with [privacy architecture](privacy-architecture.md).
