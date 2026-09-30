# Pricing strategy

The principles behind what PDF Algo Pro charges and how it is packaged. This public edition holds
the principles, the packaging shape and the rules for the paywall; price points, trial experiments
and regional pricing decisions are in a confidential edition held privately.

Owner: Product · Reviewed: before V1 submission, then each quarter

## Principles

1. **Value before the paywall.** No paywall, account or sign-in before the first completed task
   (FR-ONB-004 in the [PRD](prd.md)).
2. **The free tier is honestly useful.** Reading, annotation, form filling, signing, scanning with
   on-device OCR and a fair allowance of on-device intelligence are free (FR-STORE-001).
3. **Never hold files hostage.** Losing Pro never locks the user out of their documents or
   annotations (FR-STORE-004).
4. **One subscription, all Apple devices.** Universal purchase when iPad and Mac ship (FR-STORE-005).
5. **No dark patterns.** Clear trial terms, a reminder before a trial converts, easy cancellation,
   no weekly plans, no disguised upsells ([founder principles](founder-principles.md)).
6. **Price on value, not on cost.** On-device-first intelligence keeps AI cost low
   ([unit economics](unit-economics.md)), so prices follow willingness to pay, tested in
   [customer research](customer-research.md).

## Packaging

| Capability | Free | Pro |
|---|---|---|
| Read, annotate, fill forms, sign | Yes | Yes |
| Scan with on-device OCR; searchable PDFs | Yes | Yes |
| Search, Spotlight, App Intents, widgets | Yes | Yes |
| On-device intelligence (summarise, ask, extract) | Daily allowance (whether on-device Q&A is unlimited is decided at checkpoint CP2) | Fair use |
| Private Cloud Compute for long documents (opt-in) | — | Yes, within Apple's per-user quota |
| Analyse contract | Preview | Yes |
| Password protection and removal ([PAP-032](decision-register.md)) | Yes | Yes |
| Edit text, images and links; redaction | — | Yes |
| Organise pages (merge, split, reorder, rotate, delete, extract) | Yes | Yes |
| Compress presets, flatten, stamps, bookmarks, pages as images, PDF from photos | Yes | Yes |
| Invoice and receipt templates to CSV (V1) | — | Yes |
| Convert to Word, Excel and PowerPoint | — | Yes |
| Ask across the library (V1.1); Claude tier (V2, opt-in) | — | Yes, fair use |

## Decision: a single paid tier at launch

- **Rationale.** One tier is simple to explain and to present under
  [Guideline 3.1.2](https://developer.apple.com/app-store/review/guidelines/#subscriptions); separate AI
  add-ons, common in the category, contradict the positioning that intelligence is the product.
- **Trade-offs.** Less price discrimination; heavy users of cloud intelligence are bounded by
  fair-use limits.
- **Alternatives considered.** Pro plus an AI add-on; two paid tiers from day one; a lifetime
  licence (open-ended liability for ongoing AI and SDK costs).
- **Risks.** Conversion depends on the free allowance being right; it is an open question
  (OQ-2 in the PRD) answered by research and experiments.
- **Future scalability impact.** A higher tier or credit packs can be added in V2 once cost per user
  is measured, without changing existing subscribers' terms.

## Plans and trials

Pro is offered as monthly and annual auto-renewing subscriptions through StoreKit 2
([ADR-0011](adr/0011-storekit-2-monetisation.md)), with a free trial on the annual plan. Offers
(introductory, win-back) are used sparingly and only after baseline conversion is known. Price
changes are recorded in the decision register with their evidence.

## Paywall rules

- Appears only after first value, on a Pro action, or from Settings; never on launch.
- States price, period, trial length and auto-renewal terms, and links to the Terms of Use and
  Privacy Policy; Restore Purchases and Manage Subscription are always visible.
- Explains in plain words what Pro adds, highlighting the action the user just tried.
- Can always be dismissed.
