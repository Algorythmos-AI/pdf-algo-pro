# Kill switch

How to turn a shipped feature or an AI provider off for every user without a new build, verify that it
took effect, and turn it back on. The mechanism is remote configuration read from the CloudKit public
database. It is the **designed mechanism and is not implemented yet**; until it ships, the only levers
are the App Store ones in [incident response](incident-response.md). This page is written now so that
the implementation is built to fit the procedure.

Owner: Operations · Reviewed: each milestone, and after every use

## When to use

- A shipped feature is causing harm (crashes, data problems, wrong output) and turning it off is faster
  and safer than waiting for a hotfix.
- An AI provider must be disabled: outage, spend cap reached, a quality or safety regression, or a
  change in the provider's terms ([AI provider failover](ai-provider-failover.md)).
- Users need an in-app notice about a known problem.

Not for launching features: a feature that ships dark and is switched on after review would be a
hidden feature, which App Review Guideline 2.3.1 forbids, and remote configuration must never change
what the app does beyond the code Apple reviewed (Guideline 2.5.2)
([App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)).

## Design

- **Store.** Records in the public database of the app's container `iCloud.com.algorythmos.pdfalgopro`,
  production environment. Apple documents that the public database is available whether or not the
  device has an iCloud account and is readable by all users of the app
  ([publicCloudDatabase](https://developer.apple.com/documentation/cloudkit/ckcontainer/publicclouddatabase)).
- **Who can write.** Users can write records they create, so the configuration record type's security
  roles are set so that app users can read it but not create or modify it; only the maintainer edits it,
  in the [CloudKit Console](https://icloud.developer.apple.com/dashboard/).
- **Shape (proposed).** One record per switch: a key (for example `feature.contract-analysis` or
  `ai.provider.claude`), an enabled flag, an optional minimum and maximum app version it applies to, an
  optional notice text in EN and FR, a reason, and the incident reference.
- **Behaviour in the app.** Read at launch and when the app returns to the foreground; cache the last
  values on the device; if the read fails, use the cached values, and without a cache use the defaults
  compiled into the build (the shipped behaviour).
- **Direction.** A switch can only turn something off or show a notice. It can never turn on a cloud
  tier, widen the data sent to a provider, or bypass consent; those decisions stay on the device, with the
  user (ADR-0009).
- **Propagation.** Changes take effect on the next launch or return to the foreground, not instantly.
  Assumption: most active users pick up a change within 24 hours; measured once implemented.

Open questions for the implementing ADR: which package owns remote configuration (networking is
limited to `Intelligence`, `Commerce` and `Telemetry`); whether Staging reads separate records or a
separate container ([environments](../environments.md#open-questions)); whether a CloudKit subscription
should push changes instead of polling.

## Before you start

- An incident is open, or the owning hat (AI for providers, the feature's owner otherwise) has asked
  for the change, and the Incident lead agrees.
- You can sign in to the CloudKit Console with a role that can edit public-database records in the
  production environment.
- You know the exact key, the app versions affected, and the notice text if one is needed.

## Steps

1. Write the intended change and the reason in the incident record, with the time.
2. Open the [CloudKit Console](https://icloud.developer.apple.com/dashboard/), choose the container
   `iCloud.com.algorythmos.pdfalgopro`, the **Production** environment and the **Public** database.
3. Query the configuration record type for the key.
4. Set the enabled flag to off; set the version range if only some versions are affected; add the notice
   text (EN and FR) if users should be told; fill in the reason and the incident reference.
5. Save, and note the time in the incident record.
6. If Staging uses separate records, make the same change there first when time allows, and check it on
   the Staging build before production.

## Verify

1. On a production build (the App Store or external TestFlight build on a real device), force-quit and
   reopen the app.
2. Confirm the feature is gone or disabled with its notice, or that AI requests no longer go to the
   disabled provider and fall back as described in [AI provider failover](ai-provider-failover.md).
3. Check the app's `OSLog` output for the configuration read (Console on a Mac with the device
   connected), confirming the new value and the time it was fetched.
4. Watch the signal that caused the change (crash reports, provider errors, support email) over the
   following hours.

## Roll back

1. Set the enabled flag back on, clear the notice, and note the reason and time in the incident record.
2. Verify on a production build as above.
3. Keep the record rather than deleting it; an explicit value is easier to audit than a fallback to the
   compiled default.

## Record

- The incident record holds each change: key, old and new value, time, who changed it and why.
- A switch left off for longer than one release gets an issue to fix or remove the feature.
- `docs/working-memory.md` lists any switch that is currently off.
