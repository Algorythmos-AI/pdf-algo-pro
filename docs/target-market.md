# Target market

Who PDF Algo Pro is for, in what order, and how the market is sized. This public edition holds the
evidence about the category, the segments, the ideal customer profile and the sizing method;
sizing figures and launch-market choices are in a confidential edition held privately.

Owner: Product · Reviewed: each milestone, and after each customer research study

## What public evidence shows

There is no reliable public figure for the mobile PDF app market. Public companies in the category
report that document software is large and growing, and that AI is part of the growth. For example,
Adobe reports its Business Professionals & Consumers segment (Acrobat offerings and Adobe Express)
at US$6,495m of subscription revenue in fiscal 2025, up 15%, with growth attributed to Acrobat
([Adobe FY2025 Form 10-K](https://www.sec.gov/Archives/edgar/data/796343/000079634326000003/adbe-20251128.htm)),
and Wondershare reports PDFelement mobile revenue growing more than 30% in 2025 while its document
products overall declined
([Wondershare 2025 annual report](http://static.cninfo.com.cn/finalpage/2026-04-28/1225211130.PDF)).
The share a new Apple-only entrant can win cannot be read from public data, so it is modelled
bottom-up.

## Segments

| ID | Segment | Main jobs ([customer research](customer-research.md)) | Priority |
|---|---|---|---|
| S1 | Independent professionals (consultants, contractors, agents, sole practitioners) | Understand and sign client documents on the move | Primary |
| S2 | Knowledge workers in confidential settings using personal Apple devices (legal, finance, health administration, HR) | Understand and extract from documents that must not be uploaded | Primary |
| S3 | Personal administrators (household paperwork) | Make sense of and find bills, statements, medical and insurance letters | Secondary |
| S4 | Students and researchers | Read and question long documents | Tertiary |

Why S2 matters: Australia's privacy regulator recommends that organisations do not enter personal
information, especially sensitive information, into publicly available generative AI tools
([OAIC guidance on commercially available AI products](https://www.oaic.gov.au/privacy/privacy-guidance-for-organisations-and-government-agencies/guidance-on-privacy-and-the-use-of-commercially-available-ai-products)).
On-device intelligence lets these people use AI on documents without that disclosure.

## Ideal customer profile

An Apple-centric professional (iPhone plus iPad or Mac) who receives several PDFs a week containing
other people's personal or confidential information, uses Preview or a free tier of an established
app today, and has avoided or felt uneasy about uploading documents to AI. This is a hypothesis,
tested by the interviews and message tests in [customer research](customer-research.md).

## Sizing method

```text
Addressable users  = active Apple devices eligible for the app, by market
                     × share of users who work with PDFs weekly
                     × share in the target segments
Serviceable users  = addressable users in launch markets and languages
                     × share on Apple Intelligence-capable devices
Obtainable users   = the scenarios in the financial model (100 to 100,000 monthly active users)
```

Each input is filled only from a cited source (Apple's published figures, national labour-force
statistics, survey results, App Store Connect device mix) or a labelled assumption with a validation
plan. The planning question is whether the product can reach its break-even user count, set out in
the [financial model](financial-model.md).

## Languages and markets

English and French at V1 ([PRD](prd.md), NFR-L10N-001). Storefronts are chosen before V1 submission,
taking into account the obligations in the [compliance roadmap](compliance-roadmap.md) (for example
GDPR when targeting users in the EU, and EU AI Act transparency).

## Decision: start with professionals who handle other people's documents

- **Rationale.** Their need for private intelligence is strongest, they pay for their own tools and
  they can be reached through professional channels.
- **Trade-offs.** A narrower message than "everyone with PDFs".
- **Alternatives considered.** Students (price-sensitive, well served by note-taking apps);
  enterprises (need device management and sales capability; see [non-goals](non-goals.md)).
- **Risks.** Employer rules may forbid personal apps for work documents; tested in interviews.
- **Future scalability impact.** The same product serves households and students without change.
