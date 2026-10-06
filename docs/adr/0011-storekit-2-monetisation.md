# ADR-0011: StoreKit 2 subscriptions without a third-party SDK

**Status:** accepted (2026-09-28); the plans and the paywall's placement are superseded by [ADR-0026](0026-first-run-subscription-offer-and-plans.md) (2026-10-07), and StoreKit 2 without a third-party SDK stands

**Context.** The business model is freemium with a Pro subscription and fair-use AI credits. Subscriptions must meet App Store rules and never block first value.

**Decision.** StoreKit 2 with `SubscriptionStoreView` for the paywall, `Transaction.currentEntitlements` on device, and App Store Server Notifications V2 for server-side state once the relay exists. Monthly and annual plans with a trial; clear disclosures; restore and manage links. No paywall before the user's first successful task. Prices live in the private business documents, not in this repository.

**Alternatives considered.** RevenueCat or similar (third-party SDK and data processor). Custom paywall UI only (more compliance risk).

**Consequences.** Native, private purchase flows. Server-side entitlement checks for cloud AI arrive with the relay.

**Pillars served.** PIL-5, PIL-7

**References.** [StoreKit](https://developer.apple.com/documentation/storekit) · [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
