# Unit economics

What one paid subscriber earns and costs, as formulas and drivers. This public edition explains the
method and why the architecture matters to the business; amounts, assumptions and results are in a
confidential edition held privately.

Owner: Product · Reviewed: each quarter, and whenever a price, commission or AI price changes

## Revenue per paid subscriber

```text
gross per subscriber-year  = annual mix × annual price + (1 − annual mix) × monthly price × 12
net per subscriber-year    = gross × (1 − Apple commission)
```

Apple's commission is 15% for developers in the
[Small Business Program](https://developer.apple.com/app-store/small-business-program/), and otherwise
30% in a subscriber's first year and 15% after a year of paid service
([auto-renewable subscriptions](https://developer.apple.com/app-store/subscriptions/)).

## Variable cost per paid subscriber

| Driver | How it is costed |
|---|---|
| On-device intelligence | No per-token cost |
| Private Cloud Compute | No cloud cost while the developer is in the Small Business Program, under 2 million first-time downloads and holds the entitlement ([Apple](https://developer.apple.com/private-cloud-compute/)) |
| Claude tier (V2, opt-in, Pro only) | opt-in share × requests per month × 12 × cost per request, where cost per request = input tokens × input price (split into cache hits and misses) + output tokens × output price, at published [Claude pricing](https://platform.claude.com/docs/en/about-claude/pricing) |
| Relay traffic (V2) | per active user |
| Payments and refunds | Included in Apple's commission |

## Fixed costs

Apple Developer Program membership
([99 USD per year](https://developer.apple.com/support/compare-memberships/)), the PDF SDK licence
(quoted privately by vendors; the largest fixed cost), relay hosting from V2, and small operating
costs. The founder's time is excluded from contribution.

## Why the architecture is the business model

Running intelligence on the device first means most requests cost nothing to serve. A cloud-only
design would make every free user a variable cost and would force intelligence behind the paywall.
The on-device-first routing in [model selection](model-selection.md) is therefore both the privacy
promise and the reason the free tier can include intelligence. Any routing change that sends free
users to a paid API needs a new run of the financial model.

## LTV and CAC

- **LTV** = net per subscriber-year × average subscriber lifetime, measured from renewal data
  (App Store Server Notifications).
- **CAC** starts near zero (organic App Store search, product page optimisation, the website); paid
  acquisition begins only when measured LTV supports it, with CAC held well below LTV.

## Sensitivities

1. The PDF SDK licence (dominates break-even).
2. Conversion from active users to paid.
3. Commission tier, including the loss of free Private Cloud Compute outside the Small Business
   Program.
4. Claude usage, bounded by fair-use limits at the relay.

See the [financial model](financial-model.md) for how these drivers combine into scenarios.
