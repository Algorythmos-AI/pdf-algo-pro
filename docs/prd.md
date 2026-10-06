# Product requirements document

The single source of truth for what PDF Algo Pro does. Each requirement has an ID, a MoSCoW
priority, a phase and at least one pillar. Every Must requirement has Given/When/Then acceptance
criteria. Architecture decisions live in the [ADRs](adr/README.md); sequencing lives in the
[roadmap](product/roadmap.md); how requirements are tested lives in the
[testing strategy](testing-strategy.md).

Owner: Product · Reviewed: each milestone

Any change to a Must requirement is recorded in the [decision register](decision-register.md).

## Problem

People on iPhone, iPad and Mac receive documents that matter (contracts, statements, forms, reports,
medical and insurance papers) and need to understand, complete and act on them quickly. Established
PDF apps already cover reading, annotation, signing, editing and conversion, but their document
intelligence runs in the cloud, usually behind an account, and does not work offline (evidence in
the [competitive moat](competitive-moat.md)). People who handle sensitive documents must either
upload them or do without.

**Why switch:** intelligence that understands documents without taking them off the device, with no
account. **Why pay:** editing, redaction, conversion and deeper intelligence in one honest
subscription, after value has been shown for free. **Why stay:** a private library that can be
searched and questioned, improving every release. These are hypotheses with tests in
[customer research](customer-research.md).

## Vision

The most intelligent native PDF productivity app on Apple platforms: it reads, understands and
works with documents privately on the device, and feels as if Apple built it.

## Goals

| Goal | Pillars | Measured by |
|---|---|---|
| G1 Make any document understandable in under a minute, with answers that show their page | PIL-4 | Answer kept rate; citation accuracy ([success metrics](success-metrics.md)) |
| G2 Keep documents private by default and working offline | PIL-5, PIL-6 | Privacy label; share of intelligence served on device |
| G3 Cover the everyday PDF jobs at a quality that matches the best native apps | PIL-1, PIL-2, PIL-3 | Task success in usability tests; rating |
| G4 Feel native on every Apple surface it supports | PIL-7 | Apple-first checklist complete per feature; accessibility audits |
| G5 Build a sustainable subscription business without dark patterns | all | Trial conversion and renewal against the private financial model |

## Non-goals

See [non-goals](non-goals.md). In short: not a full Acrobat replacement, desktop publishing tool,
document management system, cloud storage provider, CRM, real-time co-editing suite (V1),
DocuSign-class e-signature platform, or Android or web app (V1).

## Personas

Derived from the onboarding intents used across the category and from the segment hypotheses in the
[target market](target-market.md). They are hypotheses until research confirms them.

| Persona | Primary intents | Needs | Segment |
|---|---|---|---|
| Priya, independent consultant | Chat with PDF, Analyse contract, Sign | Understand client agreements fast; sign on the go; keep client files private | S1 |
| Marcus, finance administrator | Extract data with AI, Scan to PDF, Organise pages | Pull amounts and dates from invoices and statements; searchable archives | S2 |
| Helen, household organiser | Scan to PDF, Summarise, Read | Make sense of bills, insurance and medical letters; find them later | S3 |
| Tom, postgraduate researcher | Read, Annotate, Summarise | Read long papers; highlight; ask questions across a library | S4 |
| Aisha, lawyer using a personal iPad | Read, Annotate, Edit text, Redact | Review drafts; redact before sharing; never upload client documents | S2 |

## Success metrics

Defined in [success metrics](success-metrics.md). Public quality targets: crash-free sessions at
least 99.8%; the [performance budgets](performance-budgets.md); page-citation accuracy at least 95%
on the evaluation set; OCR character error rate at most 2% on printed English and French. Business
targets are only defined here; their values are held privately.

## Requirement conventions

- **ID:** `FR-<AREA>-NNN` for functional and `NFR-<AREA>-NNN` for non-functional requirements. IDs
  are never reused.
- **Priority (MoSCoW):** Must, Should, Could, Won't (this phase).
- **Phase:** MVP (iPhone, internal TestFlight), V1 (first App Store release), V1.1, V2 (iPad-first,
  Mac, the Claude tier at general availability; Private Cloud Compute arrives in V1). See the
  [roadmap](product/roadmap.md).
- **Pillars:** PIL-1 Document Reading · PIL-2 Document Editing · PIL-3 OCR & Scanning · PIL-4 AI
  Document Intelligence · PIL-5 Privacy · PIL-6 Offline Capability · PIL-7 Native Apple Experience.
- **Apple-first:** each feature area lists the Apple capabilities it must adopt
  ([ADR-0022](adr/0022-apple-first-capability-baseline.md)). A feature is not done until its
  checklist is complete or an exception is recorded.

## Functional requirements

### Onboarding (FR-ONB)

| ID | Requirement | Priority | Phase | Pillars |
|---|---|---|---|---|
| FR-ONB-001 | On first launch, show three introduction pages, one capability each, in this order: scan to PDF; sign and mark up; ask your document on this iPhone ([PAP-045](decision-register.md)) | Must | V1 | PIL-4, PIL-7 |
| FR-ONB-002 | The introduction can be skipped from every page; it never returns uninvited | Must | V1 | PIL-7 |
| FR-ONB-003 | "What you do most", set in Settings, personalises the home screen (primary action and suggested tools); it is not asked on first launch | Must | MVP | PIL-7 |
| FR-ONB-004 | No account, sign-in or permission request appears during first run. The subscription offer may appear once, at the end of the introduction, with a Close button from its first frame; it never appears at a later launch ([PAP-042](decision-register.md)) | Must | V1 | PIL-5 |
| FR-ONB-005 | "Analyse contract" shows the disclosure "Not legal advice. Check important terms with a qualified professional." before its first use and on every result | Must | V1 | PIL-4 |
| FR-ONB-006 | When the on-device model is unavailable, AI intents explain why (device not eligible, Apple Intelligence off, model not ready) and offer the non-AI tools. Devices without Apple Intelligence get the non-AI tools only until V2; from V2, Pro users on those devices can also opt in to the Claude tier, whose consent screen appears only when they first use it. On first run, where on-device intelligence is unavailable the third introduction page shows organising and protecting documents instead | Must | MVP | PIL-4, PIL-6 |
| FR-ONB-007 | The introduction pages, the offer's list of what Pro adds and the "What you do most" options show only what works in the installed build; a feature that has not shipped is left out rather than marked "coming later" | Must | V1 | PIL-7 |
| FR-ONB-008 | A one-time tip on Home points to the starting actions (scan, import); it stops for good once either is used, it is closed, or it has shown three times | Should | V1 | PIL-7 |

**Acceptance (Must):**

- *FR-ONB-001/002.* Given a fresh install, when the app launches, then the first introduction page
  shows, each page has one Continue button and a Skip control, and Skip from the first page reaches
  Home in at most two actions. Given the introduction was finished or skipped, or settings stored by
  an earlier version, when the app launches again, then neither the introduction nor the offer shows.
- *FR-ONB-003.* Given the user picked "Scan to PDF" in Settings > Home, when the home screen appears,
  then its primary action is Scan. Given nothing was picked, then Home shows its default actions.
- *FR-ONB-004.* Given a fresh install, when the introduction ends, then the offer shows only if the
  products have loaded and the person does not have Pro; its Close button exists as soon as it
  appears and one action on it leads to Home. Given the app is terminated while the offer is up,
  when it launches again, then Home shows and the offer does not. Given the store cannot be reached,
  then the introduction ends on Home. No account prompt, sign-in or permission request appears at
  any point of first run (UI tests).
- *FR-ONB-005.* Given the user chose Analyse contract, when the first analysis runs and whenever a
  result shows, then the disclosure is visible without scrolling.
- *FR-ONB-006.* Given a device where `SystemLanguageModel.availability` is unavailable, when the user
  picks Chat with PDF, then the app states the reason in plain language and offers the non-AI tools;
  it never shows a spinner that does not resolve. From V2, given a Pro user on such a device, the app
  also offers the opt-in Claude tier, and its consent screen appears only when they first use it.
  Given such a device on first run, then the third page shows organising and protecting documents,
  decided before the page is shown; it never changes while on screen.
- *FR-ONB-007.* Given a build in which a feature is switched off or not yet shipped, when the introduction, the offer or the "What you do most" options show, then nothing names that feature and nothing is labelled "coming later".

**Apple-first:** SwiftUI; Dynamic Type at all sizes; VoiceOver labels on every option.

### Library and files (FR-LIB)

| ID | Requirement | Priority | Phase | Pillars |
|---|---|---|---|---|
| FR-LIB-001 | Documents live in the app's iCloud Drive folder (or on the device when iCloud is off) and open in place from Files and other apps without copying | Must | MVP | PIL-1, PIL-6, PIL-7 |
| FR-LIB-002 | Library with folders, tags, recents and favourites; sort and filter | Must | MVP | PIL-1 |
| FR-LIB-003 | Search across titles, tags and document text, including OCR text | Must | MVP | PIL-1, PIL-3 |
| FR-LIB-004 | Import from Files, the Share sheet, drag and drop, and the document camera | Must | MVP | PIL-7 |
| FR-LIB-005 | Documents are indexed in Core Spotlight (titles and text) and exposed as App Intents entities | Must | MVP | PIL-7 |
| FR-LIB-006 | Deleting a document removes it from the index and from derived data (thumbnails, embeddings, extractions) | Must | MVP | PIL-5 |
| FR-LIB-007 | Quick Look previews and thumbnails for documents in Files | Should | V1 | PIL-7 |
| FR-LIB-008 | Document info: title, file name, size, page count, dates, author, producer, PDF version, password and permission state, and whether the document is digitally signed | Should | V1 | PIL-1 |
| FR-LIB-009 | Select many documents at once to move, tag, share, merge or delete them | Must | V1 | PIL-1, PIL-7 |

**Acceptance (Must):**

- *FR-LIB-001.* Given a PDF in Files outside the app's folder, when the user opens it with PDF Algo
  Pro, then it opens in place and edits save to the original file (file coordination test).
- *FR-LIB-003.* Given a scanned document with recognised text, when the user searches for a word
  that appears only in the scan, then the document appears in results within the search budget.
- *FR-LIB-005.* Given an indexed document, when the user searches Spotlight for its title, then it
  appears and opening it launches the app at that document.
- *FR-LIB-006.* Given a document with thumbnails, index entries and saved extractions, when it is
  deleted, then none of these remain (storage inspection test).
- *FR-LIB-009.* Given ten documents, when the user selects three and deletes them, then exactly those three move to Recently Deleted, and the action can be undone.

**Apple-first:** Files integration (open in place, iCloud Drive, drag out); Core Spotlight; App
Intents entities; `Transferable` drag and drop; Share extension.

### Reading (FR-READ)

| ID | Requirement | Priority | Phase | Pillars |
|---|---|---|---|---|
| FR-READ-001 | Open and render PDFs, including large (1,000 pages), encrypted (with password) and damaged files, within the performance budgets | Must | MVP | PIL-1 |
| FR-READ-002 | Continuous and single-page modes; zoom; outline; thumbnails; page jump | Must | MVP | PIL-1 |
| FR-READ-003 | Text selection, copy and find in document | Must | MVP | PIL-1 |
| FR-READ-004 | Read aloud with system voices | Should | MVP | PIL-1, PIL-7 |
| FR-READ-005 | Night, sepia and high-contrast reading themes | Should | V1 | PIL-1 |
| FR-READ-006 | Resume at the last page read | Must | MVP | PIL-1 |
| FR-READ-007 | Handoff of the open document and page between devices | Should | V2 | PIL-7 |
| FR-READ-008 | Read aloud continues across pages until stopped, and resumes where it stopped | Should | V1 | PIL-1, PIL-7 |
| FR-READ-009 | Bookmarks: mark pages, list them and jump to them; stored as standard PDF outline entries or in the library, never lost on save | Must | V1 | PIL-1 |

**Acceptance (Must):**

- *FR-READ-001.* Given the golden corpus (large, encrypted, damaged files), when each opens, then the
  first page appears within budget or a clear error explains the problem; no crash.
- *FR-READ-002/003.* Given a document with an outline, when the user opens the outline and selects an
  entry, then the reader jumps to that page; find highlights every match and steps through them.
- *FR-READ-006.* Given the user closed a document on page 42, when they reopen it, then it opens on
  page 42.
- *FR-READ-009.* Given three bookmarked pages, when the document is saved, closed and reopened, then the three bookmarks are listed and each opens its page.

**Apple-first:** Dynamic Type for all interface text; VoiceOver reading of page text; keyboard
shortcuts (next page, find, zoom); pointer and trackpad support.

### Annotation (FR-ANN)

| ID | Requirement | Priority | Phase | Pillars |
|---|---|---|---|---|
| FR-ANN-001 | Highlight, underline, strike-through, notes, freehand ink, shapes and text boxes, stored as standard PDF annotations | Must | MVP | PIL-1, PIL-2 |
| FR-ANN-002 | Annotations from other apps display and remain editable where the PDF standard allows | Must | MVP | PIL-1 |
| FR-ANN-003 | Annotation list with jump-to-page and export as text | Should | V1 | PIL-1 |
| FR-ANN-004 | Apple Pencil with PencilKit on iPad, including pressure | Must | V2 | PIL-7 |
| FR-ANN-005 | Move, resize, restyle and recolour existing annotations and placed signatures, with undo | Must | V1 | PIL-1, PIL-2 |
| FR-ANN-006 | Stamps: date, initials, tick, cross and custom text, placed as standard PDF annotations | Must | V1 | PIL-2 |

**Acceptance (Must):**

- *FR-ANN-001/002.* Given a PDF annotated in PDF Algo Pro, when it is opened in Apple Preview, then
  every annotation appears; and given a PDF annotated elsewhere, when opened here, then its
  annotations appear (round-trip corpus test).
- *FR-ANN-005.* Given a placed signature, when the user drags it to a new position, resizes it and saves, then it appears at the new position and size in Apple Preview, and one undo restores the previous state.
- *FR-ANN-006.* Given the date stamp, when placed, then it shows the current date in the device's locale format and round-trips through Apple Preview.

### Scanning and OCR (FR-SCAN)

| ID | Requirement | Priority | Phase | Pillars |
|---|---|---|---|---|
| FR-SCAN-001 | Scan with the system document camera (edge detection, multi-page) | Must | MVP | PIL-3, PIL-7 |
| FR-SCAN-002 | On-device text recognition producing searchable PDFs with an invisible text layer, English and French first | Must | MVP | PIL-3, PIL-5, PIL-6 |
| FR-SCAN-003 | OCR existing image-only PDFs on demand, in the background with progress | Must | MVP | PIL-3 |
| FR-SCAN-004 | Recognise tables and data (dates, amounts, emails, phone numbers) for extraction | Should | V1 | PIL-3, PIL-4 |
| FR-SCAN-005 | Control Center control and widget to start a scan | Must | V1 | PIL-7 |
| FR-SCAN-006 | Review a scan before saving: crop, rotate, reorder, retake and delete pages; the app suggests a name and tags from the recognised text, on device, which the user can change | Must | V1 | PIL-3, PIL-4 |

**Acceptance (Must):**

- *FR-SCAN-002.* Given a printed English or French page from the OCR corpus, when it is scanned, then
  the character error rate is at most 2% ([success metrics](success-metrics.md)) and the resulting
  PDF's text is selectable and searchable.
- *FR-SCAN-003.* Given a 100-page image-only PDF, when OCR starts and the user leaves the app, then
  the work continues as a continued-processing task with visible progress and completes.
- *FR-SCAN-005.* Given the control is added to Control Center, when tapped on a locked or unlocked
  device, then the scanner opens after authentication as required.
- *FR-SCAN-006.* Given a three-page scan of an invoice, when the review opens, then the pages can be reordered and one retaken, and the suggested name contains the supplier and date found on the page; nothing leaves the device.

**Apple-first:** VisionKit document camera; Vision `RecognizeDocumentsRequest`; Control Center
control; widget; background continued processing.

### Intelligence (FR-AI)

| ID | Requirement | Priority | Phase | Pillars |
|---|---|---|---|---|
| FR-AI-001 | Summarise a document; the summary cites the pages it draws on | Must | MVP | PIL-4 |
| FR-AI-002 | Ask questions about a document; each answer cites pages, and tapping a citation opens the page with the source text highlighted | Must | MVP | PIL-4 |
| FR-AI-003 | Extract data to structured fields (for example invoice number, dates, amounts, parties), editable before export as CSV or to the clipboard | Must | MVP | PIL-4 |
| FR-AI-004 | Analyse a contract: parties, dates, obligations, renewal and termination terms, with citations and the not-legal-advice disclosure | Must | V1 | PIL-4 |
| FR-AI-005 | Default processing is on device. When a request does not fit the on-device model: in the MVP the app says so and suggests a shorter request or the non-AI tools; the opt-in tiers are offered once they ship (Private Cloud Compute in V1, Claude in V2) | Must | MVP | PIL-4, PIL-5, PIL-6 |
| FR-AI-006 | Private Cloud Compute tier, opt-in, for long documents and harder reasoning | Must | V1 | PIL-4, PIL-5 |
| FR-AI-007 | Claude tier through the relay, opt-in with consent that names the provider and the data sent; revocable in Settings | Should | V2 | PIL-4 |
| FR-AI-008 | Ask across the whole library with on-device retrieval; citations name the document and page | Should | V1.1 | PIL-4, PIL-6 |
| FR-AI-009 | Every AI feature can be hidden in Settings; hidden AI never appears uninvited | Must | MVP | PIL-5, PIL-7 |
| FR-AI-010 | AI output is labelled as AI-generated, and answers that cannot be grounded say "not found in this document" rather than guessing | Must | MVP | PIL-4 |
| FR-AI-011 | Document content is treated as untrusted: instructions inside a document never change app behaviour or trigger actions | Must | MVP | PIL-4, PIL-5 |
| FR-AI-012 | Translate a document on device | Could | V1.1 | PIL-4, PIL-6 |
| FR-AI-013 | Writing Tools available in all text fields | Must | MVP | PIL-7 |
| FR-AI-014 | Follow-up questions in the same conversation; each citation stores the quoted text and a fingerprint of its page, so it still opens the right passage after pages move, or says the document changed | Must | V1 | PIL-4 |
| FR-AI-015 | Invoice and receipt templates extract fields and line items with Vision tables; values are checked against the page, dates and amounts follow the locale, line items must add up to the total, and the result is saved as a CSV file that is safe to open in spreadsheets | Should | V1 | PIL-3, PIL-4 |
| FR-AI-016 | Due soon: deadlines and amounts found in documents appear in a widget; nothing is added to Reminders or Calendar until the user confirms | Should | V1.1 | PIL-4, PIL-7 |
| FR-AI-017 | Suggest content to redact: pattern rules (account and card numbers, IBANs, emails, phone numbers) in V1; on-device AI suggestions, judged on recall, from V1.1; the user confirms every redaction | Must | V1 | PIL-4, PIL-5 |
| FR-AI-018 | Siri and Shortcuts actions that return results (summary, answer, extracted fields): on device only, labelled as AI output, and requiring authentication when App Lock is on | Should | V1 | PIL-4, PIL-7 |

**Acceptance (Must):**

- *FR-AI-001/002.* Given the evaluation set, when summaries and answers are generated, then at least
  95% of citations point to a page that contains the supporting text
  ([AI evaluation framework](ai-evaluation-framework.md)); tapping a citation opens that page with
  the text highlighted.
- *FR-AI-003.* Given a synthetic invoice from the corpus, when the user extracts data, then the
  fields meet the extraction accuracy threshold and every field is editable before export.
- *FR-AI-005.* Given airplane mode on an eligible device, when the user asks a question about a
  20-page document, then the answer is produced on device within the AI latency budget.
- *FR-AI-006.* Given the user has not opted in, when a request exceeds the on-device context, then no
  data leaves the device and the app explains the Private Cloud Compute option; after opting in, the
  request succeeds and the consent is recorded locally.
- *FR-AI-009.* Given AI features are hidden, when the user browses every screen, then no AI entry
  point, suggestion or promotion appears.
- *FR-AI-010.* Given a question whose answer is not in the document, when asked, then the answer
  says it was not found and cites nothing.
- *FR-AI-011.* Given a corpus PDF containing hidden prompt-injection text, when summarised or
  questioned, then no instruction in it is followed and no tool or action runs (red-team suite).
- *FR-AI-004.* Given a contract from the corpus, when analysed, then each listed term cites its page
  and the disclosure is shown.
- *FR-AI-014.* Given an answer citing page 4, when the user asks a follow-up that depends on it, then the answer uses the earlier context and cites pages; and given page 4 is then moved to position 2, when the citation is tapped, then page 2 opens with the passage highlighted.
- *FR-AI-017.* Given a document containing an IBAN and an email address, when the user asks for suggestions, then both are proposed, and nothing is redacted until the user confirms.

**Apple-first:** Foundation Models (on device, Private Cloud Compute); Writing Tools; App Intents
("Summarise document", "Ask about document") for Siri and Shortcuts; Visual Intelligence where
applicable.

### Editing (FR-EDIT)

| ID | Requirement | Priority | Phase | Pillars |
|---|---|---|---|---|
| FR-EDIT-001 | Edit existing text (font matching where possible), images and links | Must | V1 | PIL-2 |
| FR-EDIT-002 | Add text, images and shapes | Must | V1 | PIL-2 |
| FR-EDIT-003 | Fill forms (AcroForms), with AutoFill for contact fields | Must | MVP | PIL-2, PIL-7 |
| FR-EDIT-004 | Sign with saved ink signatures stored in the Keychain | Must | MVP | PIL-2, PIL-5 |
| FR-EDIT-005 | True redaction that removes content, including text under the redaction and metadata | Must | V1 | PIL-2, PIL-5 |
| FR-EDIT-006 | Password-protect and remove protection | Must | V1 | PIL-5 |
| FR-EDIT-007 | Undo and redo for every edit; autosave | Must | MVP | PIL-2 |
| FR-EDIT-008 | Revert history: before any save that changes a document, a copy of the previous version is kept for 30 days within a storage limit, and "Revert to before…" restores it; redaction never keeps one; if a copy cannot be kept, the app offers "Save as copy" or cancel instead | Must | MVP | PIL-2, PIL-5 |

**Acceptance (Must):**

- *FR-EDIT-001.* Given a corpus PDF, when a word is edited and the file is saved, then the text
  extracted from the saved file contains the new word and not the old one, and the layout of the
  rest of the page is unchanged (visual diff within tolerance).
- *FR-EDIT-003.* Given a form PDF, when fields are filled and the document is closed or the app
  moves to the background, then the saved file holds every entry, as read by another PDF reader
  (`PDFEngineTests.formEntriesAreSaved`). **AutoFill:** PDFKit has no public API to set a text
  content type on a form field (the Xcode 26.5 SDK's PDFKit headers define none), so the app cannot
  request AutoFill itself. Contact AutoFill in forms is whatever the system offers inside PDFKit's
  page view, checked on a device for each release. Field-level control is a V1 question, to be
  revisited if PDFKit adds it or a custom form overlay is built.
- *FR-EDIT-004.* Given a saved signature, when the app is reinstalled on the same device with the
  same Apple Account, then the signature follows Keychain rules and is never stored inside
  documents except where placed.
- *FR-EDIT-005.* Given a redacted area, when the saved file is inspected with text extraction and
  object inspection, then no redacted text, image data or metadata remains (redaction test suite).
- *FR-EDIT-007.* Given ten sequential edits, when the user undoes ten times, then the document equals
  the original.
- *FR-EDIT-008.* Given a document edited and saved, when the user chooses "Revert to before…", then the previous version is restored byte for byte; and given a save interrupted at any step (fault injection), when the app relaunches, then either the original or the new version opens, never neither.

**Apple-first:** PencilKit for signatures on iPad; AutoFill; Keychain; undo through the system undo
manager and keyboard shortcuts.

### Organise and convert (FR-ORG)

| ID | Requirement | Priority | Phase | Pillars |
|---|---|---|---|---|
| FR-ORG-001 | Merge, split, reorder, rotate, delete and extract pages | Must | V1 | PIL-2 |
| FR-ORG-002 | Convert PDF to Word, Excel and PowerPoint on device; if the chosen SDK cannot convert on device, conversion moves to V1.1, and V1 has no cloud conversion (PAP-032) | Must | V1 | PIL-2, PIL-5 |
| FR-ORG-003 | Create PDFs from images, documents and web pages through the Share sheet | Should | V1 | PIL-2, PIL-7 |
| FR-ORG-004 | Compress PDFs with presets (for example "for email"), always saving a copy by default | Must | V1 | PIL-2 |
| FR-ORG-005 | Compare two versions of a document | Could | V1.1 | PIL-1, PIL-4 |
| FR-ORG-006 | Flatten annotations and form fields, on share or into a copy | Must | V1 | PIL-2 |
| FR-ORG-007 | Export pages as images (PNG or JPEG) | Must | V1 | PIL-2, PIL-7 |
| FR-ORG-008 | Create a PDF from photos chosen in the app | Must | V1 | PIL-2, PIL-7 |

**Acceptance (Must):**

- *FR-ORG-001.* Given two 100-page PDFs, when merged, then the result has 200 pages in the chosen
  order, annotations are preserved, and the merge completes within budget.
- *FR-ORG-002.* Given a corpus document, when converted to Word, then the output opens in Pages and
  Microsoft Word with text and tables preserved within tolerance, and no network connection is made.
- *FR-ORG-004.* Given a 50-page image-heavy corpus PDF, when compressed with the email preset, then a copy is saved that is smaller than the original, opens, and keeps its text searchable; the original is unchanged.
- *FR-ORG-006.* Given a filled form with annotations, when shared flattened, then the shared file shows the same content in Apple Preview with no editable fields or annotations.
- *FR-ORG-007/008.* Given three pages exported as PNG, when re-imported with "PDF from photos", then the new PDF has three pages in the same order.

**Apple-first:** Share and Action extensions; drag and drop of pages between documents
(`Transferable`); multi-window on iPad.

### Subscriptions (FR-STORE)

| ID | Requirement | Priority | Phase | Pillars |
|---|---|---|---|---|
| FR-STORE-001 | Free tier covers reading, annotation, form filling, signing, organising pages and passwords without limit, and a daily allowance of scans saved and of on-device intelligence requests ([PAP-044](decision-register.md)) | Must | V1 | PIL-7 |
| FR-STORE-002 | Pro subscription (weekly and annual, with an introductory free trial on the weekly plan) through StoreKit 2 ([PAP-043](decision-register.md)) | Must | V1 | PIL-7 |
| FR-STORE-003 | The paywall states price, period, trial length and renewal terms through StoreKit's own views, shows both plans, links to Terms and Privacy, and can be closed in one action from the moment it appears; Restore Purchases and Manage Subscription are always available | Must | V1 | PIL-7 |
| FR-STORE-004 | Losing Pro never locks the user out of their own documents or annotations | Must | V1 | PIL-5 |
| FR-STORE-005 | One subscription across iPhone, iPad and Mac (universal purchase) | Must | V2 | PIL-7 |
| FR-STORE-006 | A trial reminder one day before the trial ends: a local notification if the user allows it, otherwise an in-app notice | Must | V1 | PIL-7 |
| FR-STORE-007 | After a purchase, a confirmation screen says what is now available and, during a trial, the date it ends, and offers the trial reminder; it is the only place notification permission is asked | Must | V1 | PIL-7 |
| FR-STORE-008 | The free allowance is checked before a metered action starts and counted only when the action succeeds; reaching it opens the paywall and discards nothing the user has made | Must | V1 | PIL-5, PIL-7 |

**Acceptance (Must):**

- *FR-STORE-003.* Given the paywall, when reviewed against [Guideline 3.1.2](https://developer.apple.com/app-store/review/guidelines/#subscriptions)
  and the [App Store strategy](app-store-strategy.md) checklist, then every required disclosure is
  present (UI test and release checklist).
- *FR-STORE-001/008.* Given a free user whose scans for the day are used, when they start a scan,
  then the paywall opens before the camera does. Given a scan or a request that fails, then the
  allowance is unchanged. Given a new calendar day, then the allowance is whole again. Given Pro,
  then no allowance applies. Given an App Intent that scans or summarises, then the same rule holds.
- *FR-STORE-002.* Given a person who is not eligible for the introductory offer, when the paywall
  shows, then no text of the app's own mentions a trial; trial wording comes only from StoreKit.
- *FR-STORE-004.* Given a lapsed subscription or a used allowance, when the user opens any document,
  then it opens, reads, annotates, saves, shares and exports; only Pro actions and new metered
  actions are unavailable.
- *FR-STORE-006.* Given a trial that ends tomorrow, when that day comes, then the user is reminded by notification (if allowed) or on next launch, with the date and a link to Manage Subscription. Given the trial was cancelled, refunded or became paid before then, then no reminder is pending.
- *FR-STORE-007.* Given a purchase that completes, when the entitlement grants Pro, then the confirmation shows in the same presentation as the paywall, with the trial end date only during a trial. Given a purchase that is pending approval or was cancelled, then the paywall stays and no confirmation or error shows. Given the confirmation is closed, then no rating request follows.

**Apple-first:** `SubscriptionStoreView`; Family Sharing decision recorded in the pricing strategy before the products are created (OQ-5);
App Store Server Notifications V2 (after the relay exists).

### Settings, privacy and support (FR-SET)

| ID | Requirement | Priority | Phase | Pillars |
|---|---|---|---|---|
| FR-SET-001 | Privacy centre showing each cloud tier, its consent state and what it sends; revoke with one tap | Must | V1 | PIL-5 |
| FR-SET-002 | App lock with Face ID or Touch ID | Should | V1 | PIL-5 |
| FR-SET-003 | "Report a problem" composing an email with an opt-in diagnostics bundle that contains no document content | Must | MVP | PIL-5 |
| FR-SET-004 | Opt-in, aggregated usage telemetry: off by default everywhere; sent only after the user opts in ([analytics strategy](analytics-strategy.md)) | Must | V2 | PIL-5 |
| FR-SET-005 | Privacy report: AI requests by tier over the last 30 days and the number of documents sent to cloud AI, kept on the device | Must | V1 | PIL-5 |

**Acceptance (Must):**

- *FR-SET-001.* Given the user opted in to Private Cloud Compute, when they revoke it, then the next
  long request stays on device and asks again.
- *FR-SET-003.* Given a diagnostics bundle, when inspected, then it contains logs and device metrics
  only, with private values redacted, and no document text or file names.
- *FR-SET-005.* Given ten on-device requests and no cloud consent, when the report opens, then it shows ten on-device requests and "documents sent to cloud AI: 0".

## Non-functional requirements

| ID | Requirement | Priority | Phase |
|---|---|---|---|
| NFR-PERF-001 | Meet every budget in [performance budgets](performance-budgets.md) on the reference devices | Must | MVP |
| NFR-PERF-002 | App download size under the budget in performance budgets | Should | V1 |
| NFR-REL-001 | Crash-free sessions at least 99.8% in TestFlight before any release | Must | MVP |
| NFR-REL-002 | No data loss: every save is atomic, and a crash during save leaves the previous version intact | Must | MVP |
| NFR-PRIV-001 | No document content, personal data or identifiers leave the device without the user's explicit, informed opt-in naming the recipient | Must | MVP |
| NFR-PRIV-002 | Privacy manifest complete; App Store privacy label matches actual behaviour, verified each release | Must | V1 |
| NFR-PRIV-003 | No third-party analytics, advertising or crash SDKs ([ADR-0012](adr/0012-on-device-observability.md)) | Must | MVP |
| NFR-SEC-001 | Documents at rest use Data Protection class Complete Until First User Authentication or stronger; signatures in the Keychain | Must | MVP |
| NFR-SEC-002 | Malformed and malicious PDFs never crash the app or execute content (fuzz corpus) | Must | MVP |
| NFR-SEC-003 | Mitigations for every threat in the [threat model](threat-model.md) are traced to tests | Must | V1 |
| NFR-OFF-001 | Reading, annotation, scanning, OCR, search and on-device intelligence work with no network | Must | MVP |
| NFR-A11Y-001 | Every screen passes `performAccessibilityAudit()`; full VoiceOver, Voice Control and Dynamic Type support; contrast at least WCAG AA | Must | MVP |
| NFR-L10N-001 | English and French throughout, using String Catalogs; layouts ready for right-to-left languages | Must | V1 |
| NFR-AI-001 | AI quality gates in the [AI evaluation framework](ai-evaluation-framework.md) pass before every release and every prompt or model change | Must | MVP |
| NFR-AI-002 | AI cost stays within the per-tier budgets in [AI governance](ai-governance.md) | Must | V1 |
| NFR-QUAL-001 | Line coverage at least 80% overall and per first-party target ([testing strategy](testing-strategy.md)) | Must | MVP |

**Acceptance.** Each NFR is verified by the gate named in the [quality gates](process/quality-gates.md)
or the release checklist in [release management](release-management.md).

## Constraints

- iOS and iPadOS 26 minimum, built with the Xcode 27 SDK; iOS 27 APIs only behind availability
  checks ([ADR-0023](adr/0023-ios-26-floor-built-with-xcode-27.md)); Swift 6 with complete strict
  concurrency ([ADR-0001](adr/0001-platform-floor-and-swift-6.md)).
- Existing text is edited natively behind the `PDFTextEditing` boundary for the documents where an
  edit can be proven ([ADR-0025](adr/0025-native-text-editing-for-the-safe-subset.md)).
- Commercial PDF SDK behind the `PDFEngine` boundary; vendor chosen by a scored spike
  ([ADR-0007](adr/0007-pdf-sdk-boundary-and-vendor-selection.md), Proposed).
- On-device model context of 4,096 tokens per session and device eligibility for Apple Intelligence
  ([Managing the context window](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window)).
- App Review Guidelines, including 5.1.2(i) consent for third-party AI and 3.1.2 subscriptions.
- A single maintainer today; scope is sized accordingly and sequenced in the roadmap.

## Release criteria

- **MVP (internal TestFlight):** every Must requirement in phase MVP meets its acceptance criteria;
  NFR gates pass; no open Critical issue.
- **V1 (App Store):** every Must in MVP and V1 passes; external TestFlight complete with crash-free
  sessions at least 99.8% over at least three days; privacy label and manifest verified; release
  checklist signed ([release management](release-management.md)).
- **Later phases:** as above for their Musts, plus the platform exit criteria in
  [platform strategy](platform-strategy.md).

## Open questions

| # | Question | Owner | Resolved by |
|---|---|---|---|
| OQ-1 | Which PDF SDK vendor, and does it convert to Office on device? | Architecture | SDK spike (readiness blocker C1) |
| OQ-2 | The two free-tier allowance numbers: scans saved and on-device intelligence requests per day (shape decided in [PAP-044](decision-register.md)) | Product | Pricing strategy and research R5 |
| OQ-3 | Does Private Cloud Compute need its own consent step under Guideline 5.1.2(i)? Apple's text covers third-party AI; treat it as needing consent until Apple says otherwise | Product | App Review guidance; compliance roadmap |
| OQ-4 | Document identity across renames and iCloud moves | Architecture | Document-identity spike |
| OQ-5 | Family Sharing for the subscription | Product | Pricing strategy |

## Traceability

| Requirement area | ADRs | Tests (testing strategy) |
|---|---|---|
| FR-ONB | ADR-0003, ADR-0004, ADR-0022, ADR-0026 | UI tests (introduction, Skip, the offer's Close button, no offer at a later launch) |
| FR-LIB | ADR-0005, ADR-0006, ADR-0010 | File coordination, Spotlight and deletion tests |
| FR-READ, FR-ANN | ADR-0007 | Golden corpus, round-trip annotation, performance tests |
| FR-SCAN | ADR-0008 | OCR accuracy suite, background task tests |
| FR-AI | ADR-0009, ADR-0020, ADR-0021 | AI evaluation suite, red-team suite, latency tests |
| FR-EDIT, FR-ORG | ADR-0007 | Edit, redaction, conversion and merge tests |
| FR-STORE | ADR-0011, ADR-0026 | StoreKit configuration tests, allowance and entitlement unit tests, paywall UI tests |
| FR-SET | ADR-0012, ADR-0017 | Diagnostics bundle inspection, consent tests |
| NFR-* | ADR-0012, ADR-0013, ADR-0014, ADR-0018 | Gates in the quality gates document |
