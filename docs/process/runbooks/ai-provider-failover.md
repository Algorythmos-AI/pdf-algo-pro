# AI provider failover

What happens, and what the maintainer does, when a cloud AI tier fails: the Claude tier, Apple Private
Cloud Compute, or the on-device model itself. It covers outages, rate limiting, spend caps,
attestation failures and quality regressions, the signals that reveal them, the messages users see, and
how service is restored. Routing rules are decided in ADR-0009 (tiered AI and consent) and ADR-0021
(provider routing and failover); this runbook is the operational side and must agree with them.

Owner: AI · Reviewed: each milestone, and after every failover

## When to use

- Requests to the Claude tier fail, slow down or are refused.
- Private Cloud Compute is unavailable.
- The provider's spend cap or a self-set spend limit is reached.
- The AI evaluation suite or user reports show a quality or safety regression from a provider.
- A provider's terms or data-processing position changes and the tier must be withdrawn.

## How the tiers fail over

The tiers, in order of escalation, are the on-device `SystemLanguageModel`, Apple's Private Cloud
Compute model, and Claude through Anthropic's `ClaudeForFoundationModels` package (decision D2 of the
planning brief). Every cloud tier is opt-in, with consent that names the provider and the data sent
([App Review Guidelines 5.1.2](https://developer.apple.com/app-store/review/guidelines/#5.1.2)).
When a request routed to a cloud tier fails, it falls back down the ladder:

1. **Claude → Private Cloud Compute**, only if the user has consented to Private Cloud Compute and
   the task fits its limits (a 32K-token context, decision D2).
2. **→ on-device model**, if it is available on the device and the task fits its limits.
3. **→ a clear "not available right now" message**, with every non-AI feature still working offline.

Rules that never bend:

- Never fall back to a tier the user has not consented to, and never send more data than the consent
  described.
- The user can see which tier produced an answer; a fallback is never silent about where the data went.
- A failover never deletes or alters the user's documents or the answer history.

### Circuit breaker

Each cloud tier has a circuit breaker on the device (and, once it exists, in the
`pdf-algo-pro-backend` relay):

- **Closed:** requests flow normally.
- **Open:** after repeated failures the tier is skipped for a cool-down period, and requests go straight
  to the next tier.
- **Half-open:** after the cool-down, one request probes the tier; success closes the breaker, failure
  reopens it.

Assumption: the breaker opens after 3 consecutive failures or when more than half of requests fail in
a 2-minute window, and the cool-down is 5 minutes, doubling up to 1 hour. These values are tuned from
real error data during beta; ADR-0021 records the final ones.

## Detection signals

| Signal | Where | What it suggests |
|---|---|---|
| HTTP 429 `rate_limit_error` with a `retry-after` header | Claude tier errors on the device, relay logs later | Rate limited; wait and retry ([Rate limits](https://platform.claude.com/docs/en/api/rate-limits)) |
| HTTP 429 `rate_limit_error` without `retry-after`, `error_code` `enforced_spend_limit_reached` | Same | The organisation's tier spend cap is reached; retries fail until access resumes ([Rate limits](https://platform.claude.com/docs/en/api/rate-limits)) |
| HTTP 400 `invalid_request_error`, message beginning "You have reached your specified … API usage limits" | Same | A spend limit set on the organisation or workspace is reached ([Rate limits](https://platform.claude.com/docs/en/api/rate-limits)) |
| HTTP 529 `overloaded_error`, 500 `api_error`, 504 `timeout_error` | Same | Provider overload or outage ([Errors](https://platform.claude.com/docs/en/api/errors)) |
| App Attest unsupported or assertion failures | Device | This device cannot use the Claude tier in beta; Apple notes that not all devices support App Attest ([Establishing your app's integrity](https://developer.apple.com/documentation/devicecheck/establishing-your-app-s-integrity)) |
| Private Cloud Compute or on-device model unavailable | Device | Model availability depends on device and region support for Apple Intelligence ([SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)) |
| Status pages | [Anthropic status](https://status.claude.com), [Apple System Status](https://www.apple.com/support/systemstatus/) | Wider outage confirmed |
| Spend approaching the limit | Provider console usage page | Plan a limit change or a switch-off before the cap is hit |
| Evaluation regression, user reports of wrong or unsafe answers | AI evaluation suite (ADR-0020), support email, TestFlight feedback | Quality or safety problem; treat as an incident |

Device-side error counts are recorded with `OSLog` and signposts, never with document content (decision
D8). Aggregated first-party counters arrive only with `pdf-algo-pro-backend` (decision D9).

## Before you start

- Open an incident if users are affected ([incident response](incident-response.md)); SEV2 when a tier
  is down with no fallback, SEV3 when fallback works.
- Have access to the provider console, the CloudKit Console for the [kill switch](kill-switch.md) and
  the status pages.

## Steps

1. **Confirm.** Match the symptoms to a row in the signals table and check the status pages.
2. **Let the breaker work.** For transient rate limiting or overload, the circuit breaker and fallback
   need no action; watch for 30 minutes (Assumption: long enough to see whether a transient event
   clears) and record what happened.
3. **Disable the tier** with the [kill switch](kill-switch.md) (`ai.provider.claude` or the Private
   Cloud Compute key) when the problem is not transient: a confirmed outage, a spend cap, a quality or
   safety regression, or a terms problem. Add a user notice if many users are affected.
4. **Spend cap or limit reached.** Disable the Claude tier first, so users see a clean "not available"
   message rather than repeated failures. The Claude tier in beta authenticates with App Attest, whose
   tokens carry no user identity, so there is no per-user quota yet (decision D2); a spend event means
   aggregate demand, and the fix is a limit decision by the owner of the budget, taken privately. Fair-use
   credits per user need the `.proxied` relay required before general availability.
5. **Quality or safety regression.** Disable the tier, run the evaluation suite against the last known
   good configuration, and roll back the prompt version (prompts are versioned and eval-gated,
   ADR-0020) through a normal pull request and release.
6. **Communicate** as the incident severity requires.

## User-facing messages

Principles: say what the user can do now; name the provider when it matters for consent; never mention
spend, quotas or internal causes; never imply the user did something wrong. Strings live in the String
Catalog in EN and FR; these are the EN source texts (proposed):

- Fallback succeeded: "Claude isn't available right now, so this answer was prepared on your iPhone.
  It may be shorter."
- Fallback to Private Cloud Compute: "Claude isn't available right now, so this answer used Apple
  Private Cloud Compute, as you allowed in Settings."
- No tier can serve the request: "This needs Claude, which isn't available right now. Try again later.
  Everything else in PDF Algo Pro works as usual."
- Tier switched off for a while: "Claude is temporarily unavailable in PDF Algo Pro. Summaries and
  answers on your iPhone still work."
- On-device model unavailable: "On-device intelligence isn't available on this iPhone or in this
  region. You can turn on a cloud option in Settings, or keep using every other tool."

## Verify

- New requests route as expected: the disabled tier receives nothing, and answers show the tier that
  produced them.
- Error rates for the affected tier have stopped rising.
- Non-AI features are unaffected (open, read, annotate, scan, search).

## Roll back

Restoring the provider is the roll back:

1. Confirm on the status page, or with a probe from a Staging build, that the provider is healthy.
2. Turn the kill switch back on and remove the notice.
3. Watch error rates for an hour after restoring; if they rise, switch it off again.
4. For a quality rollback, the fixed prompt version reaches users through a release; the kill switch
   stays off until then.

## Record

- The incident record: timeline, signals, switch changes, and user impact.
- Breaker thresholds that proved wrong become an issue labelled `ai` against ADR-0021.
- A regression that the evaluation suite missed becomes a new evaluation case (ADR-0020).
