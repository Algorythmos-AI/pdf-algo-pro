# Financial model

How PDF Algo Pro's finances are modelled: structure, drivers, scenario design and the AI cost
method. This public edition contains no amounts; the model itself (parameters, scenarios for 100,
1,000, 10,000 and 100,000 monthly active users, break-even and sensitivity tables) is in a
confidential edition held privately.

Owner: Product · Reviewed: each quarter, after the PDF SDK quote, and at each milestone

## Structure

```text
monthly active users  ×  paid share               =  active paid subscribers
paid subscribers      ×  blended price            =  gross bookings
gross bookings        ×  (1 − Apple commission)   =  net proceeds
net proceeds − Claude usage − relay traffic       =  contribution before fixed costs
contribution − fixed costs                        =  contribution
break-even paid subscribers = fixed costs ÷ (net per subscriber − variable cost per subscriber)
```

The model is code: a script holds every parameter with its source or an `Assumption:` label and
writes the scenario tables, so the document and the numbers cannot drift apart.

## Scenario design

| Dimension | Values |
|---|---|
| Scale | 100, 1,000, 10,000 and 100,000 monthly active users |
| Conversion | low, base and high paid share of active users |
| Commission | Small Business Program rate, and the standard first-year rate as a sensitivity |
| PDF SDK licence | a sensitivity range until the vendor quote arrives (never an invented estimate) |
| AI usage | base, heavy (every subscriber at the fair-use cap) and a cloud-only counterfactual |

## AI cost method

- **On device:** no per-token cost.
- **Private Cloud Compute:** no cloud cost while the eligibility conditions hold
  ([Apple](https://developer.apple.com/private-cloud-compute/)); the model flags when growth would end
  eligibility.
- **Claude (V2, opt-in, Pro only):** tokens per request, cache-hit share and requests per user
  priced at the published rates ([Claude pricing](https://platform.claude.com/docs/en/about-claude/pricing)),
  re-fetched every quarter. The newer tokenizer produces more tokens for the same text, which the
  token assumptions include.

## What the model concludes (qualitatively)

1. The PDF SDK licence is the largest fixed cost and the main driver of break-even, so the SDK spike
   must return a quote before V1 scope is locked. If the quote makes early break-even impossible,
   the MVP can run on PDFKit and license the SDK when V1 editing ships (the phased-licence
   alternative in [ADR-0007](adr/0007-pdf-sdk-boundary-and-vendor-selection.md)).
2. On-device-first intelligence keeps AI cost to a small share of proceeds; a cloud-only design
   would cost more than it earns at scale. This is why routing changes need a model run.
3. Fair-use limits on the Claude tier are required to bound heavy use.
4. Paid acquisition waits for measured lifetime value.

## Assumptions and validation

Every assumption (conversion, plan mix, usage, hosting costs) has a validation plan: research study
R5, beta telemetry, App Store Connect reports and App Store Server Notifications. Assumptions are
replaced with measurements as they become available, and each change is recorded in the decision
register.
