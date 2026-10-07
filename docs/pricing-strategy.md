# Pricing strategy

The principles behind what PDF Algo Pro charges and how it is packaged. This public edition holds
the principles, the packaging shape and the rules for the paywall; price points, trial experiments
and regional pricing decisions are in a confidential edition held privately.

Owner: Product · Reviewed: before V1 submission, then each quarter

## Principles

1. **Useful without paying.** No account or sign-in, ever. The subscription offer may be shown once
   at the end of the first-run introduction and closes in one action; the free tier works without
   it (FR-ONB-004 in the [PRD](prd.md), [PAP-042](decision-register.md)).
2. **The free tier is honestly useful.** Reading, annotation, form filling, signing, organising
   pages and passwords are free without limit; scanning with on-device OCR and on-device
   intelligence are free within a daily allowance (FR-STORE-001, [PAP-044](decision-register.md)).
3. **Never hold files hostage.** Losing Pro never locks the user out of their documents or
   annotations (FR-STORE-004).
4. **One subscription, all Apple devices.** Universal purchase when iPad and Mac ship (FR-STORE-005).
5. **No dark patterns.** Clear trial terms, a reminder before a trial ends, easy cancellation, both
   plans always shown, a Close button from the first frame, no countdowns, no struck-through prices,
   no disguised upsells ([founder principles](founder-principles.md)). A weekly plan is offered
   ([PAP-043](decision-register.md)); the reminder, the trial end date on the confirmation screen and
   Manage Subscription in Settings are what guard against a billing surprise.
6. **Price on value, not on cost.** On-device-first intelligence keeps AI cost low
   ([unit economics](unit-economics.md)), so prices follow willingness to pay, tested in
   [customer research](customer-research.md).

## Packaging

| Capability | Free | Pro |
|---|---|---|
| Read, annotate, fill forms, sign | Yes | Yes |
| Scan with on-device OCR; searchable PDFs | Daily allowance of scans saved | Unlimited |
| Search, Spotlight, App Intents, widgets | Yes | Yes |
| On-device intelligence (summarise, ask, extract) | Daily allowance of requests | Unlimited |
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
- **Risks.** Conversion depends on the two allowance numbers being right; they are an open question
  (OQ-2 in the PRD) answered by research and experiments. An allowance that is too small makes the
  free tier feel like a trial, which principle 2 forbids.
- **Future scalability impact.** A higher tier or credit packs can be added in V2 once cost per user
  is measured, without changing existing subscribers' terms.

## Plans and trials

Pro is offered as weekly and annual auto-renewing subscriptions through StoreKit 2
([ADR-0026](adr/0026-first-run-subscription-offer-and-plans.md)), with an introductory free trial
on the annual plan and none on the weekly plan ([PAP-049](decision-register.md)). The trial's length
and both prices are set in App Store Connect and recorded in the confidential edition. The offer
lists the annual plan first and marks it "Best Value" with its saving against paying weekly for a
year, worked out on the device from StoreKit's prices for the person's storefront and rounded down. Family Sharing is decided before the products are created, because it
cannot be turned off afterwards ([PAP-032](decision-register.md)). Offers
(introductory, win-back) are used sparingly and only after baseline conversion is known. Price
changes are recorded in the decision register with their evidence.

## Paywall rules

- Appears once at the end of the first-run introduction, then only on a Pro action, when the day's
  allowance is used, or from Settings; never at a later launch, and not at all on first run when
  the store cannot be reached or the person already has Pro.
- States price, period, trial length and auto-renewal terms, and links to the Terms of Use and
  Privacy Policy; Restore Purchases and Manage Subscription are always visible.
- Explains in plain words what Pro adds, naming only what the installed build does and highlighting
  the action the user just tried.
- Can always be dismissed, in one action, from the moment it appears.
- The app's own words never state a price, a period or a trial; StoreKit's views do, so they are
  right for the person's storefront and their eligibility for the introductory offer. The one
  exception is the annual plan's saving, computed from StoreKit's prices ([PAP-049](decision-register.md)).
- A metered action is refused before it starts, never after the work is done.
