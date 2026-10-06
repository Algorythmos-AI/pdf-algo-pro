# ADR-0026: A closable subscription offer at the end of first run, weekly and annual plans, and a free allowance

**Status:** accepted (2026-10-07)

**Context.** [ADR-0011](0011-storekit-2-monetisation.md) chose StoreKit 2 with `SubscriptionStoreView`, monthly and annual plans, and no paywall before the user's first successful task. On 2026-10-07 the owner reviewed the first run of a competing PDF app on a phone (three introduction pages, then a subscription offer with a trial on a weekly plan, then a confirmation screen) and decided to move to that shape ([PAP-042 to PAP-045](../decision-register.md)). Three facts in the code bear on how:

- `Packages/Commerce` resolves the entitlement from `Transaction.currentEntitlements` and already finishes every verified transaction that arrives on `Transaction.updates`. It has no purchase screen and is given no product identifiers.
- A Release build has nothing to sell: text editing is behind the `textEditing` release flag ([ADR-0025](0025-native-text-editing-for-the-safe-subset.md)), and conversion, redaction and the cloud tiers are not built.
- The Staging app has its own bundle identifier ([ADR-0015](0015-identifiers-and-signing.md)), so it is a separate app in App Store Connect with its own products.

Customer research on willingness to pay and on onboarding has not been run ([customer research](../customer-research.md)), so the commercial effect of this change is an `Assumption:` until measured (see Consequences).

**Decision.**

1. **Where the offer appears.** Once, at the end of the first-run introduction, and afterwards only when the person asks for it: on a Pro action, when the free allowance for the day is used, or from Settings. It is never shown at a later launch. The first-run offer is shown only when the products have loaded, the entitlement is known, and the person does not already have Pro; otherwise first run ends on Home. First run is marked complete before the offer shows, so leaving the app on the offer leads to Home next time.
2. **What stays from ADR-0011.** StoreKit 2 and `SubscriptionStoreView`; no third-party SDK; entitlement decided on the device; prices, trial length and offers set in App Store Connect and absent from this repository. The interface's own words never state a price, a period or a trial: StoreKit's views do, because StoreKit knows the person's storefront and whether they are eligible for the introductory offer.
3. **Honest by construction.** A Close button is on screen from the first frame and closes in one action. Both plans are always visible. No countdown, no delayed Close, no struck-through price, and StoreKit's default plan selection is not overridden. Restore Purchases, Redeem Code, Terms and Privacy are on the offer; Manage Subscription is in Settings.
4. **Plans.** One subscription group with a weekly and an annual plan at one level of service; the introductory free trial is on the weekly plan. Product identifiers are derived from the app's bundle identifier (`<bundle identifier>.pro.weekly`, `<bundle identifier>.pro.yearly`), so the production and Staging apps each match their own products and no identifier is shared between two apps.
5. **Purchases complete through `Transaction.updates`.** The offer supplies no purchase-completion action. Apple documents that "by default, transactions from successful in-app store view purchases will be emitted from `Transaction.updates`" ([`onInAppPurchaseCompletion`](https://developer.apple.com/documentation/swiftui/view/oninapppurchasecompletion(perform:))), which is where `Commerce` already verifies and finishes them. The confirmation screen follows from the entitlement changing to one that grants Pro, in the same presentation, not from a second sheet.
6. **One entitlement store.** The app starts one observable store at launch over `EntitlementProviding`. It follows purchase changes, refreshes when the app becomes active and when a known trial end passes, and a gate waits for the first resolved value instead of treating "not known yet" as "not entitled".
7. **Free allowance.** The free tier meters two things per calendar day, on the device: scans saved and intelligence requests. The allowance is checked before the action starts and counted only when it succeeds. Everything a person does with a document they already have stays free in every entitlement state, as `DocumentOperation` lists and its tests hold (FR-STORE-004). App Intents use the same gate.
8. **Trial reminder.** Due one day before the trial ends (it was two). The pending reminder is removed and scheduled again on every entitlement change, only while the entitlement is a trial, and its wording is true whether or not the person has already cancelled. Notification permission is asked on the confirmation screen, never during the introduction.
9. **Testing.** A StoreKit configuration file under the app's tests carries the two products with test values and English and French names. It is a resource of the test bundle only, never of the app; the `invariants` gate checks where it lives. Its numbers are test data and say nothing about prices. The purchase tests use it through `SKTestSession`, whose environment answers only in a test run started from Xcode: under `xcodebuild test`, as in CI, every call fails with `SKInternalErrorDomain` 3 ([flutter/flutter#184678](https://github.com/flutter/flutter/issues/184678) reports the same), so that suite checks for it and is skipped there, and buying is verified from Xcode and on a device with a sandbox account. UI tests never reach the App Store: they check the triggers, the Close button and where closing leads. Internal builds follow the sandbox store like any other, with one switch in Internal testing, "Pro without a purchase", off by default; they still grant text editing while its release flag is off elsewhere.

**Alternatives considered.**

- *Keep ADR-0011 unchanged* (offer only after a first completed task). Safest for trust and for App Review; the owner judged the first-run offer worth its risks. Remains the fallback: decision 1's conditions make it a one-line change.
- *A hard paywall with no Close.* Rejected: it locks people out of their own files (FR-STORE-004), invites rejection under [Guideline 3.1.2](https://developer.apple.com/app-store/review/guidelines/#subscriptions) and 5.6, and contradicts the privacy and trust positioning.
- *A custom plan picker* (plan cards, "view all plans"). Rejected as in ADR-0011: more compliance risk, and it would put prices and trial wording in our own strings.
- *A persisted "offer seen" setting.* Rejected: it would default to "not seen" for everyone who already finished onboarding and show them an offer at launch.
- *Metering exports, merges or compression.* Rejected: those act on the person's own documents.
- *A purchase-completion action on the store view.* Rejected: the app would then have to finish transactions in a second place.

**Consequences.**

- Founder principle 5 changes from "useful before paid" to "useful without paying": the offer may now come before the first task, and what protects the person is that it closes at once and the free tier works.
- `Assumption:` a first-run offer raises trial starts without raising refunds or one-star reviews about billing. Validation plan: trial start rate, trial-to-paid conversion, refund rate and review text from App Store Connect over the first four weeks after release; if refunds or billing complaints rise, return to the fallback above and record it in the decision register.
- The weekly plan removes a safeguard the pricing strategy relied on. The reminder, the trial end date on the confirmation screen and Manage Subscription in Settings take its place.
- The allowance resets when the app is reinstalled. Closing that needs an account or a server, which the product rules out.
- Before any of this ships, the owner creates the subscription group and products for both apps in App Store Connect and decides Family Sharing, which cannot be turned off once on ([PAP-032](../decision-register.md)).
- Text editing joins Pro when its release flag turns on (ADR-0025's own conditions); until then the offer's list of what Pro adds leaves it out.

**Pillars served.** PIL-5, PIL-7

**References.** [StoreKit](https://developer.apple.com/documentation/storekit) · [SubscriptionStoreView](https://developer.apple.com/documentation/storekit/subscriptionstoreview) · [Auto-renewable subscriptions](https://developer.apple.com/app-store/subscriptions/) · [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) · [Testing In-App Purchases with sandbox](https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox) · [pricing strategy](../pricing-strategy.md) · [PRD](../prd.md)
