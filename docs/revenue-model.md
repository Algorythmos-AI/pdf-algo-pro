# Revenue model

How PDF Algo Pro makes money: the mechanics from download to renewal, what drives churn and where
expansion comes from. This public edition holds the mechanics; figures and targets are in a
confidential edition held privately.

Owner: Product · Reviewed: each quarter

## Model

Freemium with one auto-renewing subscription (Pro), sold only through the App Store with StoreKit 2
([ADR-0011](adr/0011-storekit-2-monetisation.md)). No advertising, no data sales, no third-party
offers. Packaging is in the [pricing strategy](pricing-strategy.md).

## Decision: subscription over one-time purchase

- **Rationale.** Intelligence, platform updates and the PDF SDK licence are recurring costs, and an
  auto-renewing subscription must "provide ongoing value" under
  [Guideline 3.1.2(a)](https://developer.apple.com/app-store/review/guidelines/#subscriptions), which
  suits a product that improves every release.
- **Trade-offs.** Subscription fatigue is a real theme in the category; mitigated by an honestly
  useful free tier and by never locking users out of their files.
- **Alternatives considered.** Paid upfront; a one-time unlock with paid upgrades; a lifetime
  licence.
- **Risks.** Low conversion if the free tier is too generous; tested before launch.
- **Future scalability impact.** Universal purchase extends one subscription to iPad and Mac;
  higher tiers can be added once cost per user is measured.

## Funnel

1. Discovery: App Store search and browse, Custom Product Pages per intent, the website, In-App
   Events ([App Store strategy](app-store-strategy.md)).
2. Install and first value: onboarding intent, first completed task, no paywall before it.
3. Paywall exposure: on a Pro action, from Settings, or once after a few completed tasks.
4. Trial on the annual plan, with an in-app reminder before it converts.
5. Paid: annual or monthly; universal across devices from V2.
6. Renewal: App Store auto-renewal with billing retry and grace period.
7. Lapse: documents stay fully readable and exportable; win-back offers are rare.

## Apple commission and taxes

Commission follows Apple's published terms (Small Business Program or standard subscription rates;
[Small Business Program](https://developer.apple.com/app-store/small-business-program/),
[subscriptions](https://developer.apple.com/app-store/subscriptions/)). Apple collects and remits
applicable sales taxes on App Store sales. New EU business terms apply from 2026-10-01 and are
reviewed before EU storefronts are chosen
([Apple developer news](https://developer.apple.com/news/?id=gmws0jgp)).

## Churn drivers and levers

| Driver | Lever |
|---|---|
| The one-off task is done | Library intelligence, scanning and system integration create repeat use |
| Price and value mismatch | Clear value on the paywall; annual plan; regional pricing |
| Billing surprise | Trial reminder; honest copy; no weekly plans |
| Quality regressions | Release gates; phased release; fast hotfixes |
| Involuntary churn | Grace period and billing retry |
| A better alternative | Quarterly competitive review ([competitive moat](competitive-moat.md)) |

## Expansion

iPad and Mac through universal purchase; library-wide questions and the opt-in Claude tier in V2;
a higher tier or credit packs only if measured demand supports it. Teams and volume purchasing are
out of scope ([non-goals](non-goals.md)).

## Measurement

Trials, conversions, renewals, refunds and churn come from App Store Connect and App Store Server
Notifications; definitions are in [success metrics](success-metrics.md).
