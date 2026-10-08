# ADR-0027: The app's own paywall over StoreKit 2 purchases

**Status:** accepted (2026-10-08)

**Context.** [ADR-0026](0026-first-run-subscription-offer-and-plans.md) kept `SubscriptionStoreView` for the plans and rejected a plan picker of the app's own, because it would put prices and trial wording in the app's strings, and it gave the offer no purchase-completion action so that transactions were finished in one place. On 2026-10-08 the owner saw the offer on a phone with the real Staging plans and asked for a paywall with the app's own plan cards, the trial stated as what is due today and what follows, and a record of a purchase being started, failing or waiting ([PAP-056](../decision-register.md)). Three facts bear on how:

- `SubscriptionStoreView` draws the plans, the button and its wording itself. The app cannot lay them out, cannot learn that a purchase failed or is pending without taking over completion, and saw its "Best Value" line missing with the real products until a week given as seven days was recognised ([PAP-052](../decision-register.md)).
- `Packages/Commerce` already holds the one entitlement authority (`EntitlementStore` over `Transaction.currentEntitlements` and `Transaction.updates`) and finishes the transactions that arrive as updates.
- StoreKit 2 gives everything the screen needs as data: a product's name, price and period, its introductory offer, and whether this account is eligible for it ([`Product.SubscriptionInfo`](https://developer.apple.com/documentation/storekit/product/subscriptioninfo), [`isEligibleForIntroOffer`](https://developer.apple.com/documentation/storekit/product/subscriptioninfo/iseligibleforintrooffer)).

**Decision.**

1. **The offer is the app's own screen.** It shows what Pro adds, two plan cards, what is paid and when for the selected plan, one button, and Restore Purchases, Redeem Code, Terms and Privacy. The annual plan is selected when the offer opens and is marked "Best Value" with its saving.
2. **StoreKit 2 stays the authority.** Product names, prices, periods, the introductory offer, eligibility for it, the result of a purchase, verification, entitlement and restoring are StoreKit's. The screen formats what StoreKit gives and adds no figure of its own, except the annual plan's saving, worked out from StoreKit's two prices and rounded down (PAP-049, unchanged).
3. **A trial is shown only when it would be given.** `TrialOffer` exists only when the plan has a free introductory offer and StoreKit says the account is eligible. Its length comes from the offer; no length is written in the app. With no `TrialOffer`, no trial wording can be drawn.
4. **What is paid is said in full.** With a trial: its length, the amount due today (zero, in the storefront's currency), the price that follows and how often. Without: the price and how often. Always: that it renews until cancelled, and how to cancel.
5. **The App Store confirms every purchase.** The button calls `Product.purchase()`; the App Store's own sheet follows. `Commerce` finishes the verified transaction it is handed, so every transaction is still finished in one package: this one, and those arriving on `Transaction.updates`. This replaces ADR-0026, decision 5.
6. **Pro follows only from the entitlement.** After a purchase the entitlement is read again, and the confirmation shows because the entitlement grants Pro, as it does for a purchase approved later or restored. The screen never treats its own state as a subscription.
7. **Every way a purchase can end is handled.** Cancelled: the offer stays, with nothing said. Pending: a notice that nothing has been charged. Failed or unverified: a notice, and the button is ready again. Plans that cannot be loaded: a message, Try again and Close, never an empty sheet.
8. **Someone who has Pro is told so.** The offer opened by an account that has Pro says it, sells nothing, and offers Continue and Manage Subscription.
9. **What stays from ADR-0026.** Close on screen from the first frame and closing in one action; both plans always visible; no countdown, no delayed Close, no struck-through price, no urgency; where and when the offer appears (decision 1); the free allowance; the trial reminder.

**Alternatives considered.**

- *Keep `SubscriptionStoreView` and restyle around it.* Least code and least App Review risk; it was built first (PAP-052) and the owner judged the result short of what was wanted. It cannot report a failed or pending purchase without the app taking over completion.
- *A third-party paywall SDK.* Rejected: AGENTS.md rule 7, and it would send purchase data off the device.
- *Showing the trial whenever the product has one.* Rejected: an account that has used its introductory offer would be promised a trial the App Store would not give.
- *A purchase-completion action on the store view.* It gives failure and pending, but keeps Apple's layout and still moves finishing into the app's hands; the app's own screen gives both.

**Consequences.**

- Prices and trial wording are now in the app's strings as formats around StoreKit's values, in English and French. The disclosure checklist in the [App Store strategy](../app-store-strategy.md) is the review for each change to the screen, and a UI test asserts that an account with no trial to take is shown none.
- `Assumption:` the app's own paywall passes App Review under [Guideline 3.1.2](https://developer.apple.com/app-store/review/guidelines/#subscriptions) as written. Validation: the first production submission; the fallback is `SubscriptionStoreView`, which the model's states still fit.
- The purchase path can be driven in UI tests through a fixture store, so the journey from first run through a purchase to Home is tested end to end for the first time. The App Store's own sheet, real prices and real eligibility are still checked only on a device ([device smoke test](../process/device-smoke-test.md)).
- StoreKit's default plan selection is no longer what opens selected: the annual plan is. This changes ADR-0026, decision 3, in that one respect.

**Pillars served.** PIL-5, PIL-7

**References.** [In-App Purchase](https://developer.apple.com/documentation/storekit/in-app-purchase) · [Product.purchase(options:)](https://developer.apple.com/documentation/storekit/product/purchase(options:)) · [Auto-renewable subscriptions](https://developer.apple.com/app-store/subscriptions/) · [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) · [ADR-0011](0011-storekit-2-monetisation.md) · [ADR-0026](0026-first-run-subscription-offer-and-plans.md)
