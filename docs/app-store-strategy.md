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
| Screenshots | 10 frames per locale; the iPhone 6.9-inch set only, because 1.0 is iPhone-only (PAP-067) ([screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications)); AI-with-citations first |
| App previews | Up to three per device size, 15–30 seconds, captured on device, captions burned in |
| Custom product pages | Four at launch, one per intent: AI, Scan, Sign, Edit |
| Experiments | One product page optimisation test at a time, decided at 90% confidence |
| Ratings | `requestReview` only after success moments; never in onboarding or after an error |
| Privacy label | "Data Not Collected" for V1 and V1.1 (PAP-017); the label changes before any telemetry or cloud relay ships (V2) |
| Release | Internal TestFlight → external TestFlight → App Store with a seven-day phased release |
| Languages | English and French at launch; English (U.S.) is the primary language (PAP-067) |

## Positioning summary

PDF Algo Pro is a native PDF app for reading, editing, scanning and signing, whose difference is
document intelligence (answers with page citations, summaries, data extraction, contract
explanations) that runs on the device by default on supported devices and uses the cloud only when
the user chooses. 1.0 is an iPhone app (PAP-067) with no cloud processing at all (PAP-065); iPad
comes with V2 and the opt-in cloud tiers after 1.0, so the 1.0 product page describes neither. On-device intelligence needs a device that supports Apple Intelligence,
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
| **Why stay?** | Files stay ordinary PDFs on the iPhone, in the app's folder in the Files app; no lock-in; a privacy label with nothing collected | Files as the source of truth ([ADR-0005](adr/0005-document-storage-and-identity.md)); in 1.0 the library is the app's Documents folder, shown in Files (`UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` in `App/PDFAlgoPro/Info.plist`). The iCloud Drive library is V1.1 (PAP-065), so 1.0 copy does not say "iCloud" |

Substitute risk the page must respect: Siri in iOS 27 (in beta, English first) can answer questions
about what is on screen
([Apple Newsroom, 14 September 2026](https://www.apple.com/newsroom/2026/09/major-updates-for-apples-software-platforms-are-now-available/)),
so basic "ask this PDF" is becoming a free system feature and is not a moat. The page positions on
depth: answers that cite the exact page, structured extraction into tables, search across the
whole library rather than one screen, editing the document itself, and private by default. It never
leads with basic chat. In 1.0 a question is asked of one document at a time; questions across the
library are a later capability (the in-app event candidate below), so 1.0 copy does not claim them.

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
| English (U.S.) | `reader,editor,scanner,signature,annotate,highlight,ocr,merge,summarize,chat,contract,extract` | 92 |
| English (Australia) | `reader,editor,scanner,signature,annotate,highlight,ocr,merge,summarise,chat,contract,extract` | 92 |
| English (U.K.), complementary | `document,notes,invoice,receipt,combine,organise,rotate,markup,form,fill,page` | 76 |
| French (France) | `lecteur,éditeur,numériser,signature,surligner,ocr,fusionner,résumer,contrat,extraire` | 84 |
| French (Canada), complementary | `document,formulaire,remplir,facture,reçu,notes,organiser,combiner,annoter` | 73 |

For 1.0, "convert", "convertir" and the Office file extensions are left out, because conversion is
not in the build (PAP-065); they return with the release that ships it.

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
  Apple Intelligence turned on (with a link to Apple's device list). For 1.0 the description says
  nothing about iCloud or cloud options, because neither the iCloud library nor a cloud tier is in
  the build (PAP-065); everything it describes runs on the device.
- No prices in the description (same source), no superlatives that cannot be proven ("best",
  "fastest"), and "Built by Algorythmos" at the end.
- Promotional text for 1.0, in English (all three English localisations) and French (both French
  localisations), each within the 170 characters; it names Apple Intelligence because answers need
  it, and nothing the build does not have:

  ```text
  Ask a PDF a question and see the page each answer comes from, with Apple Intelligence. Scan, sign, mark up and merge on your iPhone, with no account.
  ```

  ```text
  Posez une question à un PDF et voyez la page d’où vient chaque réponse, avec Apple Intelligence. Numérisez, signez, annotez et fusionnez sur votre iPhone, sans compte.
  ```

### What's New in 1.0

The "What's New in This Version" text for 1.0, in English and French, each well under the 4,000
characters Apple allows ([Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)).
`Assumption:` App Store Connect asks for this field only on updates, so for the first version it may
not appear; the same text then serves the GitHub Release introduction and the promotional text's
first idea. It names only what the Release build has: no text editing (unless PAP-066 turns it on,
when the bracketed line is added), no iCloud, no iPad, no cloud and no conversion. The English text is
used for all three English localisations, since it has no word spelt differently between them; the
French text is used for French (France) and French (Canada).

English (one line per bullet; the lines are long on purpose, so the text pastes as written):

```text
The first release of PDF Algo Pro.

- Ask a PDF a question and get an answer that shows the page it came from. Summaries, answers, data extraction and contract explanations run on your iPhone with Apple Intelligence, on supported devices.
- Scan paper into searchable PDFs, then rotate, reorder and name the pages before saving.
- Highlight, draw, add notes, stamps and shapes, fill in forms and sign.
- Merge documents, reorder pages, reduce file size, and add or remove a password.
- Find any word across your library, and keep it in order with tags and bookmarks.
- Version history brings back an earlier version of a document.
- No account. Your documents stay on this iPhone.
[- Change the words already in a PDF, with Pro.]
```

French:

```text
La première version de PDF Algo Pro.

- Posez une question à un PDF et obtenez une réponse qui montre la page d’où elle vient. Résumés, réponses, extraction de données et explication de contrats fonctionnent sur votre iPhone avec Apple Intelligence, sur les appareils compatibles.
- Numérisez vos papiers en PDF interrogeables, puis faites pivoter, réorganisez et nommez les pages avant d’enregistrer.
- Surlignez, dessinez, ajoutez des notes, des tampons et des formes, remplissez des formulaires et signez.
- Fusionnez des documents, réorganisez les pages, réduisez la taille et ajoutez ou retirez un mot de passe.
- Retrouvez n’importe quel mot dans votre bibliothèque, et organisez-la avec des tags et des signets.
- L’historique des versions restaure une version antérieure d’un document.
- Sans compte. Vos documents restent sur cet iPhone.
[- Modifiez le texte déjà présent dans un PDF, avec Pro.]
```

Each line is checked against the build like the review notes: the feature list of PAP-065, the scan
review and version history in the [PRD](prd.md), and the French wording against the app's own strings
(Plus › Historique des versions, Numériser) before pasting. The French text is reviewed by the French
reviewer with the rest of the listing ([localisation](process/localization.md)).

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
| iPad 13-inch | 2064 × 2752 or 2048 × 2732 | Required if the app runs on iPad | Not in 1.0 (PAP-067): the app is iPhone-only until V2 |

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
| 2 | Scanning a receipt, then its searchable text | Scan paper to searchable PDF. | Numérisez en PDF interrogeable. | OCR on device ([ADR-0008](adr/0008-ocr-and-scanning.md)) |
| 3 | A summary with the "On device" tier badge | On-device summaries on supported iPhones. | Résumés sur l’appareil, sur iPhone compatible. | Tiered AI and consent ([ADR-0009](adr/0009-tiered-ai-and-consent.md)); shot on a device that supports Apple Intelligence; the description links Apple's device list |
| 4 | Editing a typo in existing PDF text | Fix text in the PDF itself. | Corrigez le texte du PDF. | Native text editing ([ADR-0025](adr/0025-native-text-editing-for-the-safe-subset.md)); in 1.0 only if text editing ships (PAP-066), otherwise the frame is left out and the set has nine |
| 5 | Filling a form and placing a signature | Fill in forms and sign. | Remplissez et signez. | Signing and forms in the [PRD](prd.md) |
| 6 | Invoice totals extracted into a table | Pull totals and dates into a table. | Extrayez montants et dates. | Structured extraction |
| 7 | Contract clauses explained, with the disclosure visible | Understand key clauses. Not legal advice. | Comprenez les clauses. Pas un conseil juridique. | Disclosure in the [design system](design-system.md) |
| 8 | Highlights and notes on a report | Highlight, annotate, mark up. | Surlignez, annotez, commentez. | Annotation tools |
| 9 | Merging and reordering pages | Merge and reorder pages. | Fusionnez et réorganisez. | Organise pages (FR-ORG-001); conversion is not in 1.0 (PAP-065) |
| 10 | Home in Dark Mode: the app mark, the starting actions, "Continue reading" with two or three synthetic documents, the sections with their counts, and the footer "Your documents stay on this device." with the company mark and "Built by Algorythmos" | Read, edit and scan offline. No account. | Lisez, modifiez et numérisez hors ligne. Sans compte. | Offline pillar (PIL-6); no account in V1; Home as built (PAP-040, [design system](design-system.md)) |

Frame 10 is the Dark Mode screenshot Apple suggests, and the one frame that carries the company's
mark: the endorsement is on Home and in About in the app (PAP-040), so the store shows it where the
app does. Settings and About are not frames: they show no task, and a screenshot must show the app
in use (Guideline 2.3.3).

Production rules:

- Frames are shot from the build being submitted, not drawn. `App/UITests/StoreScreenshotTests.swift`
  takes them, through its own test plan (`StoreScreenshots.xctestplan`, never run in CI), on an iPhone
  with a 6.9-inch display, which shoots at exactly 1320 × 2868:

  ```
  TEST_RUNNER_STORE_LANGUAGE=fr xcodebuild test -scheme PDFAlgoPro -testPlan StoreScreenshots \
    -destination "platform=iOS,id=<device>" -resultBundlePath shots-fr.xcresult
  ```

  Each frame is attached to the result bundle as `store-<language>-<frame>`. The library is the Debug
  seed `showcase`: an invoice, a lease and a quarterly report, synthetic and in the frame's language.
  The frames with answers (1, 3, 6, 7) use the device's own model (`-intelligence live`), never the
  scripted one UI tests use, so each shows what the app really answered. On a device without Apple
  Intelligence they are skipped. What a frame shows is then what the build does, which is what the
  caption check below relies on. Before shooting, turn on Do Not Disturb and Portrait Orientation
  Lock, and leave the phone alone: a notification banner, or a tap from another app, ends up in the
  frame. Frames 2 (scanning) and 4 (editing text) are not taken this way yet. CI runs the same suite on
  the simulator (`store-screenshots`, not required) when the suite, its plan or its documents change,
  in English and French; there the frames with answers are skipped, since the simulator has no
  Apple Intelligence.
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
| Edit | People who need to change a PDF | Edit existing text | editor, merge (no "convert" in 1.0, PAP-065) | `pdfalgopro://start?intent=edit` |

Deep links preselect the matching onboarding intent and go through the single deep-link router,
which only navigates ([ADR-0004](adr/0004-navigation-and-multi-window.md)). **Not in 1.0:** the
1.0 router knows `document`, `library`, `scan` and `settings` and nothing else
(`Packages/Core/Sources/Core/Route.swift`), so a `start?intent=` link opens nothing. For 1.0 the
pages either have no deep link, or the Scan page uses `pdfalgopro://scan`; the `start` route is added
in the release that turns these pages on. The Edit page also waits for text editing (PAP-066). Each page's link is used
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
- A permanent "Rate PDF Algo Pro" row in Settings › About opens the product page with
  `action=write-review` (same RequestReviewAction page). On `integration` since #351, with the
  production App Store ID; the page loads only once the app is released, so in TestFlight and in App
  Review it is expected not to load, as the 1.0 review notes say.
- Replies to reviews in App Store Connect are factual and courteous; bug reports in reviews become
  issues without copying any personal details ([operations](operations.md)).

## App Review guidelines checklist

Guideline text from the [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
(last updated 8 June 2026). Rechecked before every submission.

| Guideline | What it requires | How PDF Algo Pro complies |
|---|---|---|
| **2.1** App Completeness | A final build with complete metadata and working URLs; demo access or a demo mode; back-end services live during review | No account exists, so no demo account is needed. The [review notes for 1.0](#review-notes-for-10) explain how to reach every feature from "Try a sample" and that intelligence is on-device only; 1.0 has no consent screen because it has no cloud tier (PAP-065). The privacy policy, support and terms URLs are live before submission (readiness item M1). The app has no back end in 1.0; once the cloud relay exists, it is live and monitored during review. Subscriptions are submitted with the build |
| **2.3** Accurate Metadata | Metadata, privacy information, screenshots and previews reflect the app; no hidden features (2.3.1); screenshots show the app in use (2.3.3); names and keywords not packed or misleading (2.3.7); metadata suitable for 4+ (2.3.8) | Every caption checked against the build; privacy label reviewed each release; remote configuration can only **switch features off**, never switch on unreviewed functionality ([process/runbooks/kill-switch.md](process/runbooks/kill-switch.md)); new features described specifically in review notes |
| **3.1.1** In-App Purchase | Unlocking features or content uses in-app purchase | Pro and AI allowances are sold only through StoreKit 2 ([ADR-0011](adr/0011-storekit-2-monetisation.md)); no licence keys or external purchase links |
| **3.1.2** Subscriptions | Ongoing value, a period of at least seven days, available on all the user's devices, no removal of paid functionality (3.1.2(a)); describe clearly what the subscriber gets before asking (3.1.2(c)) | Weekly and annual plans (the shortest period is seven days); ongoing value from continuing updates and unlimited on-device use (1.0 has no cloud AI capacity to sell, PAP-065); in 1.0 the app runs on iPhone only (PAP-067), and universal purchase across iPhone, iPad and Mac comes with those apps; the paywall states what Pro includes before the purchase button |
| **4.2** Minimum Functionality | More than a repackaged website; lasting utility | A native SwiftUI app with no web views standing in for screens ([ADR-0022](adr/0022-apple-first-capability-baseline.md)) |
| **5.1.1** Data Collection and Storage | (i) a privacy policy linked in App Store Connect and in the app; (ii) consent for data collection, even anonymous, with an easy way to withdraw, and paid functionality not dependent on granting data access | Privacy policy linked in both places. 1.0 collects nothing and has no telemetry that leaves the device (`NSPrivacyCollectedDataTypes` is empty in `App/PDFAlgoPro/Resources/PrivacyInfo.xcprivacy`). Later: any telemetry is opt-in and can be switched off in Settings; Pro works fully without telemetry or cloud AI consent; cloud tiers ask for consent only because they send document text by nature ([privacy architecture](privacy-architecture.md)) |
| **5.1.1(v)** Account Sign-In | Apps that support account creation must offer in-app account deletion; do not require personal information unless relevant | No accounts in V1. If accounts are ever introduced, in-app deletion ships with them ([compliance roadmap](compliance-roadmap.md)) |
| **5.1.2(i)** Data Use and Sharing | Clearly disclose where personal data is shared with third parties, including third-party AI, and obtain explicit permission first | A consent screen before the first cloud request names the provider (Apple Private Cloud Compute; Claude by Anthropic), the data sent (the question and the relevant passages), and retention; revocable in Settings ([ADR-0009](adr/0009-tiered-ai-and-consent.md), [AI governance](ai-governance.md)). Treated as required for Private Cloud Compute too, because Apple does not say whether it counts as third-party AI. Not applicable to 1.0: no document text leaves the device (PAP-065, V1-03 in the [compliance roadmap](compliance-roadmap.md)) |
| **5.6** Developer Code of Conduct | Honest dealings; no manipulation of reviews or rankings; 5.6.1 use the provided API for review prompts | The ratings rules above; no paid or incentivised reviews; honest paywall and cancellation |

## Review notes for 1.0

The text for App Store Connect's "Notes" field (App Review Information) and for Beta App Review,
to paste for the first submission (plan step L5). It describes the 1.0 scope (PAP-065 to PAP-067)
and was checked against the code on `integration` on 2026-10-29, after #351, with the background
check of #336 (in review on `fix/trial-reminder-after-payment`) read from its branch; before each
submission, check every line again against the build submitted (the table after it). Text editing
is off in the Release configuration today (`textEditing` in [`ReleaseFlags.swift`](../Packages/Core/Sources/Core/ReleaseFlags.swift)),
so the notes leave it out; if its device test is signed off and the flag goes on (PAP-066), add the
bracketed sentence. The French storefronts are reviewed with the same English notes; the
background sentence is also given in French after the notes, for a reply to App Review in French
and for the French tester notes. `Assumption:` the Notes field holds 4,000 characters, like the
other long text fields in App Store Connect. Pasted with each wrapped line joined to its paragraph,
the text below is 3,837 characters, or 3,934 with the text-editing sentence.

> PDF Algo Pro needs no account and has no server of its own, so no demo account is needed.
>
> How to reach every feature
> 1. On first launch, go through the three introduction pages (Continue, or Skip), then tap Close on
> the subscription offer.
> 2. Home opens with an empty library. Tap "Try a sample": it adds a three-page synthetic document (a
> guide, an invoice and a privacy page) and opens it.
> 3. In the document, Ask (the sparkles button) holds Summarise, Ask a question, Extract data and
> Explain contract; ask "What is the total due?" and tap the page cited. Markup holds highlight,
> draw, shapes, text box, Signature, notes and stamps. More holds Find, Share and Print, Pages
> (rotate, reorder, delete), Contents, bookmarks, Export and protect (reduce file size, add or remove
> a password, share a flattened copy or a page as an image) and Read aloud. Version history appears
> there once a change is saved, Recognise text for pages with no text (a PDF made from photos).
> 4. Back leads to All documents: its search field finds words inside documents (try "invoice"), and
> Select chooses documents to share, favourite, merge or delete.
> 5. Scan: on Home, tap Scan (camera, Photos or Files). Pages can be rotated, moved or deleted, and the
> scan named, before saving.
> 6. Merge: with two documents (a scan, or a PDF from Import), in All documents tap Select, choose
> both, then Merge.
> 7. Settings is the gear button on Home.
>
> On-device intelligence
> Summaries, answers, extraction and contract explanations run on the device with Apple's Foundation
> Models framework, and every answer cites its pages. They need Apple Intelligence; where it is not
> available, Ask explains why (device not supported, turned off, or the model getting ready), and
> everything else works. Settings > Hide AI features removes Ask. Explain contract always shows
> "Explains the document. Not legal advice."
>
> Nothing leaves the device
> Documents, questions and answers stay on the iPhone. There is no cloud AI and no analytics. The only
> network traffic is the App Store's, for plans and purchases, and links the person taps, which open
> in Safari or the App Store.
>
> Background
> The app declares the background fetch mode for one purpose: shortly before a free trial's reminder
> is due, it checks the subscription on the device and removes the reminder if the person has already
> subscribed or been refunded; it makes no network request of its own. Text recognition a person
> starts may also finish in the background.
>
> Subscriptions
> One group, Pro Weekly and Pro Yearly. The free trial is on Pro Yearly only, shown only when the App
> Store says the account is eligible; Family Sharing is on Pro Yearly. The offer appears once after
> the introduction, with Close from the start, and any time from Settings > Subscription > See plans.
> It shows the App Store's prices and periods, the trial's length, what is due today and after, that
> the plan renews until cancelled, Restore purchases, Redeem a code, Terms and Privacy. Settings >
> Subscription also has Manage subscription. To test: start the Pro Yearly trial with a Sandbox
> account, reinstall the app, then tap Settings > Subscription > Restore purchases. Reading, signing,
> sharing and exporting never need a subscription; Pro removes the daily limits on saved scans and
> on-device answers. [If text editing ships: "Pro also adds editing of the existing text
> of a PDF, with the Edit button in the document's bar."]
>
> Settings > About: Privacy Policy, Terms of Use, Support, and Rate PDF Algo Pro (the App Store's
> review page, which loads once the app is released).
>
> Permissions
> - Camera: only to scan, asked the first time the document camera opens.
> - Face ID: only if you turn on Settings > Require Face ID (App Lock).
> - Notifications: only if, after starting the trial, you turn on "Remind me the day before" on the
> Welcome to Pro screen.
>
> Privacy label: Data Not Collected. Nothing is switched on remotely: the app has no remote
> configuration in this version.

The background sentence in French:

> L’app déclare le mode de récupération en arrière-plan pour une seule raison : peu avant l’échéance
> du rappel d’un essai gratuit, elle vérifie l’abonnement sur l’appareil et retire le rappel si la
> personne s’est déjà abonnée ou a été remboursée ; elle ne fait aucune requête réseau de son côté.

If #336 does not ship in 1.0, the Background paragraph keeps only its last sentence, on text
recognition.

Before pasting, check each claim against the build and its evidence:

| Claim | Evidence in the code or the repository |
|---|---|
| No account, no server | No account code; no `URLSession` or other networking code in `App/` or `Packages/`; no entitlements file, so no iCloud or CloudKit; [compliance roadmap](compliance-roadmap.md) V1-09 |
| Three introduction pages, Skip and Continue; Close on the offer | `OnboardingModel.pages` and `OnboardingView`; `PaywallFlowView` (Close); `OnboardingUITests`, `PaywallUITests` |
| "Try a sample" on Home while the library is empty; three synthetic pages; the sample opens | `LibraryView.home` shows `homeStart` while `counts[.all] == 0` (`library.home.sample`; the empty All documents list has `library.empty.sample`); `LibraryModel.addSample(task:)` adds and opens it, with no assistant task unless one was chosen in What you do most (none by default, `HomeAction.primary(for:)`); `SyntheticPDF.makeSample()` and `SampleContent` (its first page suggests "What is the total due?"); `LibraryUITests` |
| The reader's menus as named | `ReaderToolbar.swift`: Ask with its four tasks; Markup; More with Find, Share and Print in one row, Pages, Contents, the bookmark, Export and protect, Read aloud; Version history only when `canRestorePreviousVersion` (after a save), Recognise text only when `canRecognizeText` (no text layer) |
| Back leads to All documents; search and Select there | `LibraryView.startAtAllDocuments()`; `.searchable` ("Titles, tags and text") and Select on the document list; the selection bar's Share, Favourite, Merge and Delete |
| Scan from the camera, Photos or Files; rotate, move, delete and name before saving | `ScanView` |
| Merge from Select in All documents | `LibraryView` (Select, Merge, enabled from two documents) |
| Settings from Home | The gear button in `LibraryView`'s sidebar toolbar (`library.sidebar.settings`) |
| On-device only, with Foundation Models; citations | `OnDeviceModel` (`SystemLanguageModel`); citations required in [AI governance](ai-governance.md); PAP-065 (the Private Cloud Compute tier is V1.1) |
| Ask explains when intelligence is unavailable | `OnboardingModel.load()`; `AssistantView.explanation(for:)`; `AssistantUITests` with `-intelligence-unavailable` |
| Hide AI features | `SettingsView` (`isIntelligenceHidden`); `ReaderModel.showsIntelligence` |
| The contract disclosure | `ContractDisclosure` in `DesignSystem/Components.swift`, shown by `AssistantView` for Explain contract; V1-06 in the [compliance roadmap](compliance-roadmap.md) |
| Background fetch for the trial reminder only, no request of the app's own | On `fix/trial-reminder-after-payment` ([#336](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/336)) until it merges: `UIBackgroundModes: [fetch]` and the `trial-reminder-check` identifier in `project.yml`; `SystemBackgroundChecks` submits one `BGAppRefreshTaskRequest`; `TrialReminderCheck.run()` refreshes the entitlement through StoreKit and removes the reminder when the trial no longer runs |
| Recognition may finish in the background | `ContinuedProcessing` (`BGContinuedProcessingTask`) in `ContinuedWork.swift`; the `recognition.*` identifiers in `project.yml` |
| Plans, trial on Pro Yearly, Family Sharing | PAP-049, PAP-050; `PaywallOfferView`; plan names in the [subscriptions runbook](process/runbooks/app-store-connect-subscriptions.md) |
| Restore purchases, Redeem a code, Terms, Privacy, Manage subscription | `PaywallOfferView`, `SubscriptionSection`; what a restore ends in, in `RestoreOutcome` (#351); [subscription disclosure](#subscription-disclosure) below |
| Free use and the daily limits Pro removes | `PaywallContent` ("Unlimited scans", "Unlimited answers"); `UsageAllowance` |
| About: Privacy Policy, Terms of Use, Support, Rate PDF Algo Pro | `AboutView`; `AppLinks.writeReview` opens `apps.apple.com` with `action=write-review`, handed to the system as a `Link` (#351) |
| Permissions and when they are asked | `NSCameraUsageDescription` and `NSFaceIDUsageDescription` in `project.yml` and the generated `App/PDFAlgoPro/Info.plist`; `AppLock.swift`; `TrialReminderScheduler` asks for notifications only from the reminder switch in `WelcomeProView` |
| Data Not Collected | [Privacy labels](#privacy-labels) below; `PrivacyInfo.xcprivacy`; PAP-017 |
| Nothing switched on remotely | `RemoteConfig` is linked but imported by no app or feature code; release flags are compiled in ([release flags](process/release-flags.md)) |
| Text editing | Off in Release unless its device test is signed off (`ReleaseFlag.textEditing.compiledDefault` is `false`; PAP-066 in the [decision register](decision-register.md)) |

## Subscription disclosure

Requirements from Apple's [auto-renewable subscriptions](https://developer.apple.com/app-store/subscriptions/)
page and Guideline 3.1.2, and how the paywall meets them. The paywall is the app's own screen over
StoreKit 2, and every figure on it is StoreKit's for the storefront and the account
([ADR-0027](adr/0027-own-paywall-over-storekit-2.md)).

| Requirement | Where it appears |
|---|---|
| Subscription name and duration, and what is provided during the period | Each plan card (StoreKit's name, price and period); the list of what Pro adds above them |
| Full renewal price, clear and prominent, localised | StoreKit's price on each plan card, as the card's largest text, and again in the terms under the cards (an annual plan shows the annual amount, never only a weekly equivalent) |
| Free trial: how long it lasts and the price charged when it ends | On the plan card and in the terms under the cards: the trial's length, what is due today, and the price and period that follow. Shown only when StoreKit says the account is eligible, with StoreKit's length; wording reviewed in English and French |
| Auto-renewal terms | A plain statement that the plan renews automatically until cancelled, and that it can be cancelled any time in Settings |
| Terms of Use (EULA) and Privacy Policy links, in the app and in the App Store metadata | Terms and Privacy links on the paywall; links in Settings; Privacy Policy URL and Terms of Use link in App Store Connect |
| Restore purchases | Restore purchases link on the paywall and row in Settings |
| The offer can be declined | A Close button from the first frame, including when the offer follows the first-run introduction ([ADR-0026](adr/0026-first-run-subscription-offer-and-plans.md)) |
| Manage and cancel | Settings row opening the system sheet (`manageSubscriptionsSheet`), as Apple recommends making the system management page easy to reach |
| Offer codes | Redeem a code link on the paywall and row in Settings (`offerCodeRedemption`) |
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
| **1.0: on device only** | Nothing to us, and no document content to anyone. The app has no networking code of its own, no iCloud or CloudKit entitlement, and its remote-configuration package is not used by any screen (PAP-065; no `URLSession` and no entitlements file in the app target). StoreKit talks to the App Store to load plans and purchases, which is Apple's processing; links the person taps open in Safari; Report a problem opens Mail with what the person chooses to send. Apple's own App Analytics and crash reports are Apple's collection | **Data Not Collected** (PAP-017); the privacy manifest declares no collected data types and no tracking (`App/PDFAlgoPro/Resources/PrivacyInfo.xcprivacy`) |
| **V1.1: on device plus opt-in Private Cloud Compute** | Nothing to us. Documents sync through the user's own iCloud Drive and library metadata through the user's CloudKit private database, which we cannot read. The app reads remote configuration from the CloudKit public database without sending user data. Apple's own App Analytics and crash reports are Apple's collection. When the user opts in, Private Cloud Compute requests go to Apple, which processes them and does not store them (the Private Cloud Compute row below) | **Data Not Collected** for V1 and V1.1 (decision PAP-017 in the [decision register](decision-register.md)), on the Private Cloud Compute assumption below |
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
- **Target declarations on iPhone** (iPad from V2, PAP-067): VoiceOver, Voice Control, Larger Text, Dark Interface,
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

## 1.0 metadata check

Every claim this document makes for the product page, the review and the listing, read against the
1.0 scope (PAP-065 to PAP-067, PAP-070) and the code on `integration` on 2026-10-28; the Rate row
rechecked on 2026-10-29, after #351. "Changed" means
the text above now says what 1.0 does; "Flagged" means the owner decides before the listing is
filled in; "Holds" means the claim is true of the 1.0 build as it stands.

| Claim | Where | Result |
|---|---|---|
| An iPhone and iPad app | Positioning summary | Changed: 1.0 is iPhone-only (PAP-067); iPad is V2 |
| Uses the cloud when the user chooses | Positioning summary; Guidelines 2.1, 3.1.2, 5.1.1, 5.1.2(i) | Changed: 1.0 has no cloud tier and no consent screen (PAP-065); the cloud wording is kept only for later releases |
| Files stay in the user's iCloud Drive | "Why stay?" | Changed: files stay in the app's folder on the iPhone, shown in Files; the iCloud library is V1.1 (PAP-065) |
| Questions across the whole library | Substitute risk | Changed: 1.0 searches the whole library and asks one document at a time |
| Universal purchase across iPhone and iPad | Guideline 3.1.2 | Changed: iPhone only in 1.0 |
| Documents sync through iCloud Drive and CloudKit; remote configuration read from CloudKit | Privacy labels | Changed: a 1.0 row says neither happens; the old row now reads V1.1 |
| "Convert", "convertir" and the Office file extensions as keywords | Keyword field | Holds: already left out for 1.0 (PAP-065) |
| "Redact" or "compress" as keywords | Keyword field rules | Holds: neither is in the fields. Compress ships in 1.0 (PAP-065) as "Reduce file size"; adding "compress" is an owner choice |
| iPad 13-inch screenshots | Screenshots | Holds: not provided for 1.0 (PAP-067) |
| Frame 4, "Fix text in the PDF itself" | Storyboard | Holds as written: the frame is shot only if text editing ships (PAP-066), else the set has nine frames |
| Frame 9, "Merge and reorder pages" | Storyboard | Holds: merge and page reordering are in 1.0 (PAP-065) |
| Frame 10, "Read, edit and scan offline. No account." | Storyboard | Holds: markup, forms and pages are editing even with text editing off; nothing in 1.0 needs a network |
| The word "Edit" in the name, and "editor" as a keyword | Name and subtitle, keyword field | Flagged: true of markup, forms and page editing in 1.0; the owner decides whether "Edit" in the name reads as text editing while PAP-066 keeps text editing off |
| Custom product page deep links, `pdfalgopro://start?intent=` | Custom product pages | Changed: the 1.0 router has no `start` route; the pages ship without a deep link, or the Scan page uses `pdfalgopro://scan` |
| The Edit custom product page, "Edit existing text" first | Custom product pages | Flagged: only if text editing ships (PAP-066) |
| A "Rate PDF Algo Pro" row in Settings | Ratings and reviews; review notes | Holds: in Settings › About since #351; the review notes say its page loads once the app is released |
| "Target declarations on iPhone and iPad" | Accessibility Nutrition Labels | Changed: iPhone only in 1.0 |
| iPad edition, multi-document questions | In-app events | Holds: listed as later events, not 1.0 |
| Redaction, Office conversion, image editing, split and extract, widgets, the iCloud library, the cloud tier | Anywhere in the listing | Holds: none is claimed for 1.0 in this document after these changes |
| The visual refresh | Screenshots | Holds: the frames come from the release candidate as it looks now (PAP-070) |
| Description: "Built by Algorythmos" at the end | Promotional text and description | Holds: the same line is in Settings › About (`AboutView`) |

## Open questions

- **Universal first release?** Closed by PAP-067: 1.0 is iPhone-only, so no iPad screenshots are
  needed; iPad-first stays V2 ([platform strategy](platform-strategy.md)).
- **Naming Microsoft formats.** Whether the description may say "Word, Excel and PowerPoint" as a
  factual description of export formats, or should use file-format names only.
- **Primary App Store language:** closed by PAP-067, English (U.S.). In-app spelling variants stay open.
- **Launch storefronts:** closed by PAP-067, every storefront, with the trader declaration for the EU.
- **Private Cloud Compute and Guideline 5.1.2(i).** Consent is shown for it regardless; confirm the
  wording with Apple's current guidance.
- **Age rating for document chat**, confirmed in the questionnaire.
- **Support language** for French-speaking customers ([operations](operations.md)).
