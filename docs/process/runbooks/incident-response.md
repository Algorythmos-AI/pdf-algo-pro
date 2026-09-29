# Incident response

How to recognise, grade, contain, fix, communicate and learn from an incident affecting PDF Algo Pro
users, from a crash spike to a privacy failure. It is written for a solo maintainer who holds every
incident role, and it keeps the same roles so that the process still works when the hats are worn by
different people.

Owner: Operations · Reviewed: after every SEV1 or SEV2, and each milestone

## When to use

Open an incident for anything that harms users of an external build (external TestFlight or the App
Store), or threatens to:

- crashes, hangs or data loss when opening, editing, saving or syncing documents;
- document content leaving the device without consent, redaction that leaves recoverable content, or
  any other privacy failure;
- a vulnerability report received through [SECURITY.md](../../../.github/SECURITY.md);
- an AI tier failing, misbehaving or exceeding its spend cap
  ([AI provider failover](ai-provider-failover.md));
- purchases or entitlements failing;
- the app becoming unavailable on the App Store.

Problems seen only on internal TestFlight (Staging) are ordinary `bug` issues, not incidents.

## Severity levels

| Level | Definition | Examples |
|---|---|---|
| SEV1 | Serious harm to users' data, privacy or security, or the app unusable for most users | Document corruption or loss; content sent to a cloud tier without consent; exploitable vulnerability; crash on launch; redaction leaving recoverable text |
| SEV2 | A core capability broken for many users, with no reasonable workaround | Scanning or OCR failing on a common device; purchases or restores failing; sync silently not working; an AI tier down with no fallback |
| SEV3 | A capability degraded, or broken for few users, with a workaround | Failover to on-device AI working but slower; a crash on one rare file type; wrong text in one language |
| SEV4 | Cosmetic or minor, no data or privacy impact | Layout glitch; typo; misleading but harmless message |

Anything touching privacy or security starts at SEV1 until assessed down.

### Response targets

Assumption: these targets are starting values for a solo maintainer working Sydney business hours
with no on-call rotation. They are validated after the first five incidents or six months after launch,
whichever comes first, by comparing actual times with the targets.

| Level | Start work | Contain (stop the harm growing) | Status updates | Postmortem |
|---|---|---|---|---|
| SEV1 | Within 1 hour of detection in business hours; first thing the next morning otherwise | Same day | Every 4 hours while active | Required, within 5 business days |
| SEV2 | Within 1 business day | Within 2 business days | Daily | Required, within 10 business days |
| SEV3 | At the next weekly triage | Next release | On change | Optional |
| SEV4 | At the next weekly triage | Backlog | — | No |

Two commitments are already published and take precedence: vulnerability reports are acknowledged
within five business days ([SECURITY.md](../../../.github/SECURITY.md)), and support email is
answered within two business days ([SUPPORT.md](../../../.github/SUPPORT.md)).

## Roles (hats)

| Hat | Does |
|---|---|
| Incident lead | Declares the incident, sets severity, decides on containment, owns it until closed |
| Subject expert | Diagnoses and fixes (PDF engine, AI, storage, purchases, as needed) |
| Communications | Replies to affected users, writes public notes and App Store text |
| Scribe | Keeps the timeline in the incident record |
| Security | Joins every privacy or security incident; decides on disclosure and notification duties |

The maintainer holds all of them today. When working alone, keep this order: contain first, then
record the timeline, then communicate, then fix properly. Write a line in the timeline at every
decision; it is the only way the postmortem will be accurate.

## Before you start

- Access: App Store Connect, the CloudKit Console for the [kill switch](kill-switch.md), the AI provider
  console, the repository with admin rights, and the support mailbox.
- Decide where the record lives. Security and privacy incidents use a **draft private security
  advisory** in the repository and are never discussed in public issues. Other incidents use a
  public issue labelled `bug` and `priority:p0` (SEV1) or `priority:p1` (SEV2), with no personal
  data or document content in it.

## Steps

1. **Declare.** Open the record, name the Incident lead, state what is known and the severity.
2. **Assess.** Which versions and platforms, how many users (from crash reports, MetricKit
   diagnostics once implemented, support email, reviews), whether data or privacy is involved.
3. **Contain.** Choose the fastest lever that stops the harm growing:
   - flip the [kill switch](kill-switch.md) for the feature or AI provider (designed, to be implemented);
   - pause the phased release
     ([Release a version update in phases](https://developer.apple.com/help/app-store-connect/update-your-app/release-a-version-update-in-phases));
   - fail over the AI tier ([AI provider failover](ai-provider-failover.md));
   - as a last resort, remove the app from sale; it leaves the App Store within 24 hours, existing users
     keep it and still receive updates
     ([Manage availability](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-for-your-app-on-the-app-store)).
4. **Fix.** Ship through the [iOS hotfix runbook](ios-hotfix.md), with an expedited review for a
   critical bug.
5. **Communicate** (see below) at the cadence for the severity.
6. **Resolve.** Close the incident when the fix is released and the signal has returned to normal;
   restore any kill switch deliberately.
7. **Learn.** Hold the postmortem and file its actions as issues.

## Communication

- **Affected users who wrote in:** reply from the support mailbox with what happened, what to do now,
  and when a fix is expected. Never ask users to send documents.
- **All users:** the What's New text of the fix release says what was fixed in plain words; for a
  serious issue the app can show a notice through remote configuration once the kill switch exists.
  Developer responses to App Store reviews are another channel
  ([Respond to customer reviews](https://developer.apple.com/help/app-store-connect/monitor-ratings-and-reviews/respond-to-customer-reviews)).
- **Security issues:** coordinate disclosure with the reporter; publish the security advisory after
  the fix is available.
- **Personal information:** if personal information may have been exposed, the Security hat assesses
  notification duties, for example under the Australian Notifiable Data Breaches scheme
  ([OAIC](https://www.oaic.gov.au/privacy/notifiable-data-breaches)) and, for users in the EU, the
  GDPR ([Regulation (EU) 2016/679](https://eur-lex.europa.eu/eli/reg/2016/679/oj)), and takes legal
  advice.
- **Third-party outages:** check [Apple System Status](https://www.apple.com/support/systemstatus/),
  [Apple Developer System Status](https://developer.apple.com/system-status/) and the
  [Anthropic status page](https://status.claude.com) before blaming the app.

Plain, factual, no speculation about causes, no blame, no promises of dates you do not control (App
Review timing is Apple's).

## Verify

- The signal that opened the incident (crash signature, error rate, reports) is back to its normal level
  on the fixed version.
- Every containment step is either reversed or has an issue explaining why it remains.
- Affected users who wrote in have had a closing reply.

## Roll back

Containment steps are reversible: resume the phased release, restore the kill switch, make the app
available again. There is no binary rollback on iOS; a bad fix is replaced by another fix.

## Record

The incident record keeps the timeline. SEV1 and SEV2 need a postmortem; security-sensitive detail
stays in the private advisory and is summarised publicly only after the fix ships.

### Postmortem

Blameless: the question is what in the system allowed the failure, not who made a mistake. Copy this
template into the incident record or a follow-up issue:

```markdown
## Summary
One paragraph: what happened, who was affected, how long, current status.

## Impact
Versions, platforms, approximate number of users, data or privacy impact (yes/no, what).

## Timeline (Australia/Sydney time)
- YYYY-MM-DD HH:MM detected by …
- HH:MM declared SEV… by …
- HH:MM contained by … (kill switch / paused release / failover)
- HH:MM fix released as X.Y.Z
- HH:MM resolved

## Root cause and contributing factors
What failed, why the gates did not catch it, what made it worse.

## Detection
How it was found and how it could have been found sooner.

## What went well / what did not

## Actions
- [ ] #issue — owner hat — due milestone (prevent)
- [ ] #issue — owner hat — due milestone (detect)
- [ ] #issue — owner hat — due milestone (respond)
```

Actions are ordinary issues with labels and a milestone; the postmortem is complete when they are
filed, not when they are done.
