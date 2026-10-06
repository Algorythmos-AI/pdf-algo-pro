# App Store strategy

How PDF Algo Pro is presented, found, reviewed and released on the App Store: the product page and
its search metadata, screenshots and previews, custom product pages, experiments, events and
ratings, the App Review and subscription rules the product must meet, privacy and accessibility
labels, the age rating, the launch sequence and localisation. Prices are not in this document; they
are held in the confidential edition of the pricing strategy. Every claim on the product page must
be true of the build being submitted ([founder principles](founder-principles.md), principle 10).

Owner: Product · Reviewed: before each App Store submission, and each milestone

## Summary

| Area | Decision |
|---|---|
| Name and subtitle | "PDF Algo Pro: Scan, Sign, Edit" (30 characters) with "Ask PDFs, get cited answers" (27 characters); French equivalents below; limits from [App information](https://developer.apple.com/help/app-store-connect/reference/app-information) |
| Categories | Productivity (primary), Business (secondary) |
| Screenshots | 10 frames per locale; iPhone 6.9-inch and iPad 13-inch sets ([screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications)); AI-with-citations first |
| App previews | Up to three per device size, 15–30 seconds, captured on device, captions burned in |
| Custom product pages | Four at launch, one per intent: AI, Scan, Sign, Edit |
| Experiments | One product page optimisation test at a time, decided at 90% confidence |
| Ratings | `requestReview` only after success moments; never in onboarding or after an error |
| Privacy label | "Data Not Collected" for V1 and V1.1 (PAP-017); the label changes before any telemetry or cloud relay ships (V2) |
| Release | Internal TestFlight → external TestFlight → App Store with a seven-day phased release |
| Languages | English and French at launch |

## Positioning summary

PDF Algo Pro is a native iPhone and iPad PDF app for reading, editing, scanning and signing, whose
difference is document intelligence (answers with page citations, summaries, data extraction,
contract explanations) that runs on the device by default on supported devices and uses the cloud
only when the user chooses. On-device intelligence needs a device that supports Apple Intelligence,
with Apple Intelligence turned on: iPhone 15 Pro and iPhone 15 Pro Max, iPhone 16 and later, iPad and
Mac with M1 or later, and iPad mini (A17 Pro)
([Apple Newsroom, 8 June 2026](https://www.apple.com/newsroom/2026/06/apple-intelligence-brings-powerful-ai-capabilities-into-everyday-experiences/);
[Apple Intelligence](https://www.apple.com/apple-intelligence/)). App Store copy therefore never
promises offline or on-device AI on every iPhone; it says "on supported devices" and links Apple's
device list. The full positioning, audiences and messaging are in [product positioning](product-positioning.md)
and [target market](target-market.md).

The product page has to answer three questions in its first three screenshots and first sentence:

| Question | What the page shows | Evidence behind the claim |
|---|---|---|
| **Why switch?** | Answers that cite the page they came from, without creating an account and, on supported devices, without uploading the document | The main competitors' AI features are cloud-based and most require an account ([competitive moat](competitive-moat.md)); PDF Algo Pro's on-device tier needs neither ([ADR-0009](adr/0009-tiered-ai-and-consent.md)) |
| **Why pay?** | Editing existing text, OCR, extraction and longer AI work, on top of a free app that already reads, annotates and signs | Apple's free Preview app already fills, signs, scans and marks up PDFs on iOS 26 and later ([Preview on the App Store](https://apps.apple.com/us/app/preview/id536344167)), so basic tasks cannot be the reason to pay ([pricing strategy](pricing-strategy.md)) |
| **Why stay?** | Files stay in the user's own iCloud Drive; no lock-in; a privacy label with nothing collected | Files as the source of truth ([ADR-0005](adr/0005-document-storage-and-identity.md)) |

Substitute risk the page must respect: Siri in iOS 27 (in beta, English first) can answer questions
about what is on screen
([Apple Newsroom, 14 September 2026](https://www.apple.com/newsroom/2026/09/major-updates-for-apples-software-platforms-are-now-available/)),
so basic "ask this PDF" is becoming a free system feature and is not a moat. The page positions on
depth: answers that cite the exact page, structured extraction into tables, questions and search
across the whole library rather than one screen, editing the document itself, and private by
default. It never leads with basic chat.

## App Store optimisation

Apple's limits: name and subtitle up to 30 characters each; keyword field 100 characters, commas
without spaces; promotional text 170 characters and changeable without a new version; do not repeat
words, use plurals of words already present, category names, the word "app", competitor names or
trademarks you are not authorised to use ([Product page](https://developer.apple.com/app-store/product-page/);
Guideline 2.3.7 in the [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)).

### Name and subtitle

Character counts are exact (App Store Connect counts characters, including spaces and punctuation).

| Option | Name | Characters | Subtitle | Characters |
|---|---|---|---|---|
| **A (recommended)** | PDF Algo Pro: Scan, Sign, Edit | 30 | Ask PDFs, get cited answers | 27 |
| B | PDF Algo Pro | 12 | Ask PDFs, get cited answers | 27 |
| C | PDF Algo Pro: Ask, Scan, Sign | 29 | Answers from your PDFs, cited | 29 |
| D | PDF Algo Pro – PDF Editor | 25 | Edit, sign and scan PDFs | 24 |
| **French (recommended)** | PDF Algo Pro : scanner, signer | 30 | Posez vos questions à vos PDF | 29 |

French uses a non-breaking space before the colon (French typography); it counts as one character.

Rejected subtitle wording: "Private, offline PDF assistant" (30) and "Private PDF answers, offline"
(28). On-device answers need a device that supports Apple Intelligence with it turned on, so an
unqualified "offline" or "private AI" claim would not be true for every buyer.

**Decision: option A.** **Rationale.** The name field carries the most search weight
(`Assumption:` widely reported by ASO practitioners; Apple does not publish ranking weights), so it
names the three most common generic tasks, while the subtitle carries the differentiator in a
verifiable form (citations are mandatory in the product). **Trade-offs.** A longer name is truncated
in some list views; the brand ("PDF Algo Pro") is always the visible part. **Alternatives
considered.** B (cleanest brand, weaker search coverage), C (leads with AI in the name; the subtitle
already does that), D (generic; "PDF" repeated). **Risks.** Guideline 2.3.7 rejects names packed
with keywords; three plain task verbs are descriptive rather than packed. **Future scalability
impact.** The name can drop the descriptor once the brand is known; subtitles can change with any
version. Name and subtitle cannot be A/B tested with product page optimisation, so the choice is
revisited with App Analytics search data after launch.

### Keyword field

Words already in the name or subtitle are not repeated. Each localisation has its own field. Apple
displays more than one localisation in some storefronts: Australia shows English (Australia) and
English (U.K.); France shows French and English (U.K.); the United States shows English (U.S.) and
several others including French; Canada shows English (Canada) and French (Canada)
([App Store localizations](https://developer.apple.com/help/app-store-connect/reference/app-information/app-store-localizations)).
`Assumption:` keywords from every localisation shown in a storefront are indexed there, so the
English (U.K.) and French (Canada) fields are used for complementary terms; validated with the
Search source in App Analytics.

| Localisation | Keyword field | Characters |
|---|---|---|
| English (U.S.) | `reader,editor,scanner,signature,annotate,highlight,ocr,merge,convert,summarize,chat,contract,extract` | 100 |
| English (Australia) | `reader,editor,scanner,signature,annotate,highlight,ocr,merge,convert,summarise,chat,contract,extract` | 100 |
| English (U.K.), complementary | `document,notes,invoice,receipt,combine,organise,rotate,xlsx,pptx,docx,markup,form,fill,page` | 91 |
| French (France) | `lecteur,éditeur,numériser,signature,surligner,ocr,fusionner,convertir,résumer,contrat,extraire` | 94 |
| French (Canada), complementary | `document,formulaire,remplir,facture,reçu,notes,organiser,combiner,annoter,docx,xlsx,pptx` | 88 |

Rules applied:

- **No competitor names or trademarks**, including Acrobat, Adobe, Readdle, DocuSign and "PDF
  Expert" (the word "expert" is avoided for the same reason). Microsoft's "Word", "Excel" and
  "PowerPoint" are trademarks, so the fields use file extensions instead; whether the description
  may name them factually is an open question.
- **Only features the build has.** Terms such as "redact" or "compress" are added only when the
  feature ships.
- **Spelling per locale:** "summarize" for the U.S., "summarise" for Australia.

### Promotional text and description

- Promotional text (170 characters) announces what is new; it does not affect search, so it is not
  used for keywords ([Product page](https://developer.apple.com/app-store/product-page/)).
- The description's first sentence is the only one most people read (same source). Draft:
  "Ask a PDF a question and get an answer that shows the page it came from." It is followed by a
  short feature list and a plain note that on-device intelligence works on supported devices with
  Apple Intelligence turned on (with a link to Apple's device list), and that cloud options are
  optional and named.
- No prices in the description (same source), no superlatives that cannot be proven ("best",
  "fastest"), and "Built by Algorythmos" at the end.

### Categories

**Decision: Productivity primary, Business secondary.** **Rationale.** People browse for document
tools in both: in the United States, Adobe Acrobat Reader ranks #13 in Business and Goodnotes #111
in Productivity (App Store listings accessed 2026-09-28:
[Acrobat Reader](https://apps.apple.com/us/app/adobe-acrobat-reader-pdf-maker/id469337564),
[Goodnotes](https://apps.apple.com/us/app/id1444383602)). Productivity matches the everyday tasks
(read, annotate, scan, sign) that bring most people in; Business matches extraction and contract
work for sole traders and small businesses ([target market](target-market.md)). **Trade-offs.**
Chart competition in Productivity is broad. **Alternatives considered.** Business primary (a
narrower audience than the product serves); Utilities (poor fit for document work). **Risks.** The
primary category decides chart placement; revisited with App Analytics browse data after launch.
**Future scalability impact.** The same categories apply on the Mac App Store.

## Screenshots

### Required sizes

From Apple's [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications):
one to ten screenshots per localisation, in JPEG or PNG, with no transparency.

| Display | Accepted sizes (portrait) | Requirement | Plan |
|---|---|---|---|
| iPhone 6.9-inch | 1320 × 2868, 1290 × 2796 or 1260 × 2736 | Required if the app runs on iPhone and 6.5-inch screenshots are not provided | **Provide at 1320 × 2868**; smaller iPhones use scaled versions |
| iPhone 6.5-inch | 1284 × 2778 or 1242 × 2688 | Required if 6.9-inch screenshots are not provided | Not provided |
| iPad 13-inch | 2064 × 2752 or 2048 × 2732 | Required if the app runs on iPad | **Provide at 2064 × 2752** if the first release runs on iPad (open question) |

The first one to three screenshots appear in search results when there is no app preview, and Apple
suggests at least one Dark Mode screenshot ([Product page](https://developer.apple.com/app-store/product-page/)).
Screenshots must show the app in use (Guideline 2.3.3) and suit a 4+ audience (Guideline 2.3.8).

### Ten-frame storyboard

The same story in every locale, with localised captions and French-language synthetic documents in
the French sets. Captions are short (`Assumption:` six words or fewer read at a glance in search
results).

| Frame | Shows | Caption (English) | Caption (French) | Claim checked against |
|---|---|---|---|---|
| 1 | A question and an answer with "p. 4" citation chips | Ask a PDF. See the page it came from. | Posez une question. Voyez la page source. | Citation requirement in [AI governance](ai-governance.md) |
| 2 | Scanning a receipt, then its searchable text | Scan paper to searchable PDF. | Numérisez en PDF consultable. | OCR on device ([ADR-0008](adr/0008-ocr-and-scanning.md)) |
| 3 | A summary with the "On device" tier badge | On-device summaries on supported iPhones. | Résumés sur l'appareil, iPhone compatibles. | Tiered AI and consent ([ADR-0009](adr/0009-tiered-ai-and-consent.md)); shot on a device that supports Apple Intelligence; the description links Apple's device list |
| 4 | Editing a typo in existing PDF text | Fix text in the PDF itself. | Corrigez le texte du PDF. | PDF engine capability ([ADR-0007](adr/0007-pdf-sdk-boundary-and-vendor-selection.md)) |
| 5 | Filling a form and placing a signature | Fill in forms and sign. | Remplissez et signez. | Signing and forms in the [PRD](prd.md) |
| 6 | Invoice totals extracted into a table | Pull totals and dates into a table. | Extrayez montants et dates. | Structured extraction |
| 7 | Contract clauses explained, with the disclosure visible | Understand key clauses. Not legal advice. | Comprenez les clauses. Pas un conseil juridique. | Disclosure in the [design system](design-system.md) |
| 8 | Highlights and notes on a report | Highlight, annotate, mark up. | Surlignez, annotez, commentez. | Annotation tools |
| 9 | Merging and reordering pages; export formats | Merge, reorder and convert. | Fusionnez, réorganisez, convertissez. | Organise and convert |
| 10 | Home in Dark Mode: the app mark, the starting actions, "Continue reading" with two or three synthetic documents, the sections with their counts, and the footer "Your documents stay on this device." with the company mark and "Built by Algorythmos" | Read, edit and scan offline. No account. | Lisez, modifiez et numérisez hors ligne. Sans compte. | Offline pillar (PIL-6); no account in V1; Home as built (PAP-040, [design system](design-system.md)) |

Frame 10 is the Dark Mode screenshot Apple suggests, and the one frame that carries the company's
mark: the endorsement is on Home and in About in the app (PAP-040), so the store shows it where the
app does. Settings and About are not frames: they show no task, and a screenshot must show the app
in use (Guideline 2.3.3).

Production rules:

- Frames are shot from the build being submitted, not drawn: the app is started on the simulator with
  an empty private library (`-ui-testing -skip-onboarding`, in a Debug build of the same commit), the
  synthetic documents are imported, and the screen is captured with `xcrun simctl io <device> screenshot`.
  What a frame shows is then what the build does, which is what the caption check below relies on.
- Frame 10 needs a library that looks used: at least three synthetic documents opened, one marked as
  a favourite, none in Recently deleted, so no count reads "0" beside a section the caption talks about.

- Documents in screenshots are synthetic and licence-clean, like the test corpus; no real people,
  companies or personal data ([testing strategy](testing-strategy.md)).
- Captions use the brand tokens on the website backgrounds, which pass AA contrast
  ([design system](design-system.md)); text on screenshots stays at least the equivalent of 17-point
  body text on the device.
- Before submission, each caption is checked against the build (release checklist in
  [process/runbooks/app-store-submission.md](process/runbooks/app-store-submission.md)).

## App preview videos

Apple allows up to three app previews per localisation per device size, 15 to 30 seconds each, at 30
frames per second, up to 500 MB, in H.264 or ProRes 422 (HQ)
([App preview specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications)).
Previews autoplay muted, so the first seconds and on-screen text matter, and they should use footage
captured on the device ([Product page](https://developer.apple.com/app-store/product-page/)).

| Preview | Length | Story |
|---|---|---|
| 1. Ask and check | 20–25 s | Open a report → ask a question → answer with citations → tap "p. 7" → the passage is highlighted |
| 2. Scan to searchable | 15–20 s | Scan a two-page letter → review → search finds a word from the scan |
| 3. Edit and sign | 20–25 s | Fix a typo → fill a form → sign → share |

Resolutions: iPhone portrait 886 × 1920 (accepted for 6.9-inch and 6.5-inch); iPad portrait 1200 ×
1600 (same source). Captions are burned in, localised, and never rely on sound. Previews are made only
for iPhone at launch; `Assumption:` one preview first, and more only if product page optimisation
shows previews improve conversion.

## Custom product pages

Apple allows up to 70 custom product pages, each with its own screenshots, previews and promotional
text, optional keywords that let the page appear in search, and a deep link into the app (iOS 18 and
later). Their metadata is reviewed independently of app updates, and App Analytics reports
impressions, downloads, conversion, retention and proceeds per page
([Custom product pages](https://developer.apple.com/app-store/custom-product-pages/)).

| Page | Audience | First screenshot | Assigned keywords (subset) | Deep link |
|---|---|---|---|---|
| AI | People who want to ask, summarise, extract or understand contracts | Answer with citations | chat, summarise or summarize, extract, contract | `pdfalgopro://start?intent=chat` |
| Scan | People who digitise paper | Scan to searchable PDF | scanner, ocr, receipt | `pdfalgopro://start?intent=scan` |
| Sign | People who fill and sign forms | Fill and sign | signature, form, fill | `pdfalgopro://start?intent=sign` |
| Edit | People who need to change a PDF | Edit existing text | editor, convert, merge | `pdfalgopro://start?intent=edit` |

Deep links preselect the matching onboarding intent and go through the single deep-link router,
which only navigates ([ADR-0004](adr/0004-navigation-and-multi-window.md)). Each page's link is used
where that intent is the reason someone is looking: support articles, social posts, and later Apple
Ads ad variations.

## Product page optimisation

Apple allows one test at a time, with up to three treatments of the icon, screenshots and previews,
for up to 90 days; alternate icons must be in the app binary; new metadata needs App Review; Apple
recommends waiting for 90% confidence before applying a result
([Product page optimization](https://developer.apple.com/app-store/product-page-optimization/)).

| Order | Hypothesis | Treatments | Decision rule |
|---|---|---|---|
| 1 | Leading with AI citations converts better than leading with scanning | First frame: AI answer (control) vs scan | Apply the winner at 90% confidence; otherwise keep the control |
| 2 | A Dark Mode set converts better for a document app | Light set (control) vs dark set | As above |
| 3 | A preview adds conversion over screenshots alone | No preview (control) vs Preview 1 | As above |
| 4 | An alternate icon improves recognition in search | Current icon vs one or two alternates (shipped in the binary with the preceding app update) | As above |

The conversion thresholds that would justify a change are business targets and are held privately
([success metrics](success-metrics.md)). Tests run on the default page only; custom product pages are
measured separately.

## In-app events

Apple allows up to 10 published and 15 approved events at a time, each lasting up to 31 days and
promoted up to 14 days before it starts; names are up to 30 characters, short descriptions 50 and
long descriptions 120; events need a deep link and are reviewed separately from app versions; they
appear in search and on the product page
([In-app events](https://developer.apple.com/app-store/in-app-events/)).

Events must describe something genuinely happening in the app. Candidates:

| Candidate | Badge | Condition |
|---|---|---|
| iPad edition: Apple Pencil, multiple windows, keyboard | Major Update | Ships with the V2 iPad-first experience ([platform strategy](platform-strategy.md)) |
| A new intelligence capability (for example multi-document questions) | Major Update | When it ships and passes the AI evaluation gates ([AI evaluation framework](ai-evaluation-framework.md)) |
| End-of-financial-year paperwork (Australia, July) | Special Event | Only with real in-app content (for example a receipts collection and guided extraction); otherwise not run |

## Ratings and reviews

- **API.** Use SwiftUI's `requestReview` action. The system shows the prompt at most three times in
  365 days, it does nothing in TestFlight builds, and Apple says not to call it in response to a
  button tap ([RequestReviewAction](https://developer.apple.com/documentation/storekit/requestreviewaction)).
  Guideline 5.6.1 requires the provided API for review prompts.
- **Only after success moments**, as the HIG recommends
  ([Ratings and reviews](https://developer.apple.com/design/human-interface-guidelines/ratings-and-reviews)):
  a scan saved as a searchable PDF; a signed document shared; an AI answer copied, shared or kept;
  an edited document saved. The request is made when the completion screen settles, not during the
  task.
- **Our own limits on top of the system's:** never in the first session or during onboarding; never
  in a session with an error; at least three completed core tasks on at least two different days
  first; at least 14 days between requests (the HIG suggests a week or two); at most once per app
  version. `Assumption:` these thresholds; tuned with ratings volume after launch.
- **No review gating.** No "Do you like the app?" pre-question that sends only happy users to the
  prompt, no incentives (Guideline 5.6.1).
- A permanent "Rate PDF Algo Pro" row in Settings opens the product page with `action=write-review`
  (same RequestReviewAction page).
- Replies to reviews in App Store Connect are factual and courteous; bug reports in reviews become
  issues without copying any personal details ([operations](operations.md)).

## App Review guidelines checklist

Guideline text from the [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
(last updated 8 June 2026). Rechecked before every submission.

| Guideline | What it requires | How PDF Algo Pro complies |
|---|---|---|
| **2.1** App Completeness | A final build with complete metadata and working URLs; demo access or a demo mode; back-end services live during review | No account exists, so no demo account is needed. Review notes explain the AI tiers, how to reach the consent screen, and where the bundled synthetic sample documents are. The privacy policy, support and terms URLs are live before submission (readiness item). Once the cloud relay exists, it is live and monitored during review. Subscriptions are submitted with the build |
| **2.3** Accurate Metadata | Metadata, privacy information, screenshots and previews reflect the app; no hidden features (2.3.1); screenshots show the app in use (2.3.3); names and keywords not packed or misleading (2.3.7); metadata suitable for 4+ (2.3.8) | Every caption checked against the build; privacy label reviewed each release; remote configuration can only **switch features off**, never switch on unreviewed functionality ([process/runbooks/kill-switch.md](process/runbooks/kill-switch.md)); new features described specifically in review notes |
| **3.1.1** In-App Purchase | Unlocking features or content uses in-app purchase | Pro and AI allowances are sold only through StoreKit 2 ([ADR-0011](adr/0011-storekit-2-monetisation.md)); no licence keys or external purchase links |
| **3.1.2** Subscriptions | Ongoing value, a period of at least seven days, available on all the user's devices, no removal of paid functionality (3.1.2(a)); describe clearly what the subscriber gets before asking (3.1.2(c)) | Monthly and annual plans; ongoing value from continuing updates and cloud AI capacity; universal purchase across iPhone and iPad (and Mac later); the paywall states what Pro includes before the purchase button |
| **4.2** Minimum Functionality | More than a repackaged website; lasting utility | A native SwiftUI app with no web views standing in for screens ([ADR-0022](adr/0022-apple-first-capability-baseline.md)) |
| **5.1.1** Data Collection and Storage | (i) a privacy policy linked in App Store Connect and in the app; (ii) consent for data collection, even anonymous, with an easy way to withdraw, and paid functionality not dependent on granting data access | Privacy policy linked in both places. Any telemetry is opt-in and can be switched off in Settings. Pro works fully without telemetry or cloud AI consent; cloud tiers ask for consent only because they send document text by nature ([privacy architecture](privacy-architecture.md)) |
| **5.1.1(v)** Account Sign-In | Apps that support account creation must offer in-app account deletion; do not require personal information unless relevant | No accounts in V1. If accounts are ever introduced, in-app deletion ships with them ([compliance roadmap](compliance-roadmap.md)) |
| **5.1.2(i)** Data Use and Sharing | Clearly disclose where personal data is shared with third parties, including third-party AI, and obtain explicit permission first | A consent screen before the first cloud request names the provider (Apple Private Cloud Compute; Claude by Anthropic), the data sent (the question and the relevant passages), and retention; revocable in Settings ([ADR-0009](adr/0009-tiered-ai-and-consent.md), [AI governance](ai-governance.md)). Treated as required for Private Cloud Compute too, because Apple does not say whether it counts as third-party AI |
| **5.6** Developer Code of Conduct | Honest dealings; no manipulation of reviews or rankings; 5.6.1 use the provided API for review prompts | The ratings rules above; no paid or incentivised reviews; honest paywall and cancellation |

## Subscription disclosure

Requirements from Apple's [auto-renewable subscriptions](https://developer.apple.com/app-store/subscriptions/)
page and Guideline 3.1.2, and how the paywall meets them. `SubscriptionStoreView` shows localised
names, descriptions and prices, a Close button, and the terms and privacy policy links submitted in
App Store Connect ([SubscriptionStoreView](https://developer.apple.com/documentation/storekit/subscriptionstoreview)).

| Requirement | Where it appears |
|---|---|
| Subscription name and duration, and what is provided during the period | Plan options in `SubscriptionStoreView`; a "What Pro includes" list above them |
| Full renewal price, clear and prominent, localised | Provided by StoreKit; the billed amount is the most prominent price (an annual plan shows the annual amount, not only a monthly equivalent) |
| Free trial: how long it lasts and the price charged when it ends | Line under each plan with a trial; wording reviewed in English and French |
| Auto-renewal terms | A plain statement that the plan renews automatically until cancelled, and that it can be cancelled any time in Settings |
| Terms of Use (EULA) and Privacy Policy links, in the app and in the App Store metadata | Policy buttons on the paywall; links in Settings; Privacy Policy URL and Terms of Use link in App Store Connect |
| Restore purchases | Restore button on the paywall (`storeButton` with `restorePurchases`) and in Settings |
| Manage and cancel | Settings row opening the system sheet (`manageSubscriptionsSheet`), as Apple recommends making the system management page easy to reach |
| Offer codes | Redeem Code button (`redeemCode`) |
| Billing problems | Billing Grace Period enabled in App Store Connect, as Apple recommends |

Prices, trial lengths and offers are set in App Store Connect from the confidential pricing strategy;
none appear in this repository ([pricing strategy](pricing-strategy.md)).

## Privacy labels

Apple defines "collect" as transmitting data off the device and keeping it in readable form longer
than needed to service the request; data processed only on the device is not collected; data Apple
collects (for example App Analytics) is not the developer's to disclose; data that is sent and
immediately discarded after servicing need not be disclosed; optional disclosure applies only when
all of Apple's criteria are met ([App privacy details](https://developer.apple.com/app-store/app-privacy-details/)).

| Configuration | What leaves the device, and to whom | Label |
|---|---|---|
| **Launch (V1, V1.1): on device plus opt-in Private Cloud Compute** | Nothing to us. Documents sync through the user's own iCloud Drive and library metadata through the user's CloudKit private database, which we cannot read. The app reads remote configuration from the CloudKit public database without sending user data. Apple's own App Analytics and crash reports are Apple's collection. When the user opts in, Private Cloud Compute requests go to Apple, which processes them and does not store them (the Private Cloud Compute row below) | **Data Not Collected** for V1 and V1.1 (decision PAP-017 in the [decision register](decision-register.md)), on the Private Cloud Compute assumption below |
| **Opt-in telemetry ships (V2)** | Daily aggregated feature counters and performance buckets, no identifiers ([analytics strategy](analytics-strategy.md)) | Usage Data (Product Interaction) and Diagnostics (Performance Data, Other Diagnostic Data), **Not Linked to You**, purpose Analytics. The label changes when the code ships, even though sharing is opt-in, because telemetry does not meet the optional-disclosure criteria |
| **Private Cloud Compute tier** | The question and relevant document passages, processed by Apple and not stored, as Apple states ([What's new in the Foundation Models framework, WWDC26](https://developer.apple.com/videos/play/wwdc2026/241/)) | `Assumption:` no disclosure, because nothing is retained; confirmed with the entitlement terms |
| **Claude tier through our relay (V2)** | The question and relevant passages, sent through `pdf-algo-pro-backend` to Anthropic | If the relay or provider keeps content beyond servicing the request: User Content (Other User Content), purpose App Functionality. If the relay keeps a subscriber identifier for quotas: Identifiers (User ID) or Purchases, **Linked to You**. The final answer depends on the provider's retention terms (readiness blocker C4) |
| **Support email with a diagnostics summary** | What the user chooses to send | `Assumption:` meets the optional-disclosure criteria (optional, infrequent, user-initiated each time, with the sender shown); confirmed before launch |

**Decision: launch with "Data Not Collected".** **Rationale.** It is the most direct proof of the
privacy pillar (PIL-5), and competitors' labels list data linked to the user or used for tracking
([competitive moat](competitive-moat.md)). **Trade-offs.** No in-app funnel data at launch;
Apple-native sources only ([analytics strategy](analytics-strategy.md)). **Alternatives considered.**
Shipping telemetry at launch (earlier insight, but the label changes on day one). **Risks.** A label
that falls behind the code; mitigated by a release-checklist step that compares the network-capable
packages and the relay's retention against the label. **Future scalability impact.** When the relay
and telemetry arrive, the label changes in the same release, with a release note explaining why.

## Age rating

Apple's ratings are 4+, 9+, 13+, 16+ and 18+, set by a questionnaire covering content and
capabilities such as unrestricted web access, user-generated content, messaging and chat,
advertising, and medical or wellness topics
([Age ratings values and definitions](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions)).

`Assumption:` **4+**. The app has no advertising, no messaging, no broadly distributed
user-generated content, no in-app web browsing (links open in Safari), and no health content.
Intelligence features answer questions about the user's own documents. Confirmed by completing the
questionnaire before the first submission; open question on whether document chat is treated as a
chat capability.

## Accessibility Nutrition Labels

App Store Connect lets developers declare VoiceOver, Voice Control, Larger Text, Dark Interface,
Differentiate Without Color Alone, Sufficient Contrast, Reduced Motion, Captions and Audio
Descriptions per device; a feature may only be declared if people can complete all common tasks with
it; the labels are voluntary today and will become required
([Overview of Accessibility Nutrition Labels](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels)).

- **Common tasks** for the declaration: open a document, read and search it, annotate, fill and sign,
  scan to a searchable PDF, ask a question and open a citation, organise pages, export and share,
  subscribe and restore.
- **Target declarations on iPhone and iPad:** VoiceOver, Voice Control, Larger Text, Dark Interface,
  Differentiate Without Color Alone, Sufficient Contrast, Reduced Motion. Each is declared only after
  the release's accessibility pass shows every common task can be completed with it
  ([design system](design-system.md)).
- **Not applicable:** Captions and Audio Descriptions (the app has no video content). App previews are
  captioned anyway.
- Risk: scanning depends on the system document camera; if a common task cannot be completed with
  VoiceOver, the VoiceOver label is not declared until it can.

## Launch plan

| Stage | Build and audience | Entry | Exit |
|---|---|---|---|
| 1. Internal TestFlight | Staging configuration from `integration` via Xcode Cloud; up to 100 internal testers ([TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview)) — today the maintainer | CI gates green ([quality gates](process/quality-gates.md)) | No open SEV1 or SEV2; performance budgets met on reference devices |
| 2. External TestFlight | Release configuration from `main`; up to 10,000 external testers; the first build goes through beta review; builds expire after 90 days; a public link with criteria (same source) | Release pull request merged ([release management](release-management.md)) | Crash-free sessions of at least 99.8% over the beta; accessibility pass; AI evaluation thresholds met; privacy label and review notes final; the relay live if the Claude tier is offered ([platform strategy](platform-strategy.md)) |
| 3. App Store review | Manual release after approval | Submission runbook complete ([process/runbooks/app-store-submission.md](process/runbooks/app-store-submission.md)) | Approved; tag `vX.Y.Z` cut on `main` |
| 4. Phased release | Automatic updates over seven days at 1%, 2%, 5%, 10%, 20%, 50% and 100%; pausable for up to 30 days in total; anyone can update manually ([Release a version update in phases](https://developer.apple.com/help/app-store-connect/update-your-app/release-a-version-update-in-phases)) | Release day | Seven days without a SEV1; crash-free sessions at target ([operations](operations.md)) |
| 5. After launch | Custom product pages live; first optimisation test; ratings prompts active | Phased release complete | Reviewed at the next milestone |

If a release goes wrong, the phased release is paused, a kill switch disables the faulty feature,
and a hotfix goes through expedited review ([process/runbooks/ios-hotfix.md](process/runbooks/ios-hotfix.md)).

**Decision: staged launch with a phased release.** **Rationale.** iOS has no binary rollback; small
exposure first limits harm. **Trade-offs.** New users download the full release immediately; only
automatic updates are phased. **Alternatives considered.** Immediate release to all users (no
containment). **Risks.** A defect that appears only at scale; mitigated by kill switches.
**Future scalability impact.** The same sequence serves the Mac App Store and later platforms.

## Localisation

- **English and French at launch**, in String Catalogs, right-to-left ready (NFR-L10N-001 in the
  [PRD](prd.md)).
- **App Store localisations:** English (U.S.), English (Australia), English (U.K.), French (France)
  and French (Canada). Each has its own keywords and localised screenshots; French screenshots show
  the French interface with French synthetic documents.
- **In-app English:** Australian spelling in the base language with a U.S. regional variant for
  spelling-sensitive strings (for example "summarise"/"summarize") is proposed; open question.
- **Legal and safety text** (terms, privacy policy, consent, "not legal advice") is translated
  professionally and reviewed, not machine-translated.
- **EU storefronts** (France, Belgium) require a Digital Services Act trader-status declaration, which
  displays trader contact details on the product page
  ([Manage European Union Digital Services Act trader requirements](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/));
  tracked in the [compliance roadmap](compliance-roadmap.md).

## Open questions

- **Universal first release?** If the first App Store release runs on iPad (adaptive layouts exist
  from the MVP), 13-inch iPad screenshots are required at submission, although iPad-specific features
  arrive later ([platform strategy](platform-strategy.md)).
- **Naming Microsoft formats.** Whether the description may say "Word, Excel and PowerPoint" as a
  factual description of export formats, or should use file-format names only.
- **Primary App Store language** (English (U.S.) or English (Australia)) and in-app spelling variants.
- **Launch storefronts.** Which countries at launch beyond the English- and French-speaking ones.
- **Private Cloud Compute and Guideline 5.1.2(i).** Consent is shown for it regardless; confirm the
  wording with Apple's current guidance.
- **Age rating for document chat**, confirmed in the questionnaire.
- **Support language** for French-speaking customers ([operations](operations.md)).
