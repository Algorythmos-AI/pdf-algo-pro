# Kill switch

How to turn a shipped feature, an AI provider or a prompt version off for every user without a new
build, or lower a limit compiled into the app, verify that it took effect, and turn it back on. The
mechanism is remote configuration read from the CloudKit public database. The mechanism is built (the `RemoteConfig`
package, [ADR-0024](../../adr/0024-remote-configuration-package.md)) but reads no records until the
iCloud container and the record type exist. Until then, the only levers are the App Store ones in
[incident response](incident-response.md). This page is written now so that the implementation is
built to fit the procedure. It owns the record schema: other documents link here rather than
restating it.

Owner: Operations · Reviewed: each milestone, and after every use

## When to use

- A shipped feature is causing harm (crashes, data problems, wrong output) and turning it off is faster
  and safer than waiting for a hotfix.
- An AI provider must be disabled: outage, spend cap reached, a quality or safety regression, or a
  change in the provider's terms ([AI provider failover](ai-provider-failover.md)).
- Users should be told why a feature or provider is off; the notice comes with the switch, chosen by
  its `reasonCode`.

Not for launching features or rolling out releases: a feature that ships dark and is switched on after
review would be a hidden feature, which App Review Guideline 2.3.1 forbids, and remote configuration
must never change what the app does beyond the code Apple reviewed (Guideline 2.5.2)
([App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)). Releases roll out
through the App Store's phased release, not remote flags
([release management](../../release-management.md#phased-release)).

## Design

- **Store.** Records in the public database of the app's container `iCloud.com.algorythmos.pdfalgopro`.
  Apple documents that the public database is available whether or not the device has an iCloud
  account and is readable by all users of the app
  ([publicCloudDatabase](https://developer.apple.com/documentation/cloudkit/ckcontainer/publicclouddatabase)).
- **Who can write.** Users can write records they create, so the configuration record type's security
  roles are set so that app users can read it but not create or modify it; only the developer role
  edits it, in the [CloudKit Console](https://icloud.developer.apple.com/dashboard/).
- **Direction.** Remote flags can only turn things **off** or lower a limit. A record can take shipped
  behaviour away; it can never turn on anything the build ships off, raise a compiled limit, turn on
  a cloud tier, widen the data sent to a provider, or bypass consent. Those decisions stay on the
  device, with the user (ADR-0009).
- **Two-step changes.** Every change is made in the container's CloudKit **development** environment
  first and checked on a build that reads it, then made in **production** ([steps](#steps)).

### Record schema

One record per target. A **switch record** turns something off:

| Field | Meaning |
|---|---|
| `target` | What the record switches, named by the scheme below |
| `state` | `enabled` (the compiled behaviour applies), `disabled` (turned off) or `fallback` (for a prompt: use the previous version bundled in the app) |
| `reasonCode` | Chooses the user notice: a localised string in the app's String Catalog, in English and French, shipped and reviewed with the build. The record holds no free text, so nothing typed in the console reaches users |
| `minVersion`, `maxVersion` | The app versions the record applies to; when absent, every version |
| `channel` | `staging` or `production`; when absent, both. TestFlight and App Store builds both read the production environment, so this keeps a change for testers away from customers ([ADR-0024](../../adr/0024-remote-configuration-package.md)) |
| `updatedAt` | When the record last changed; used for audit and cache freshness |

An **operational-setting record** lowers a limit, for example a per-request page cap for a cloud
tier ([engineering playbook](../../engineering-playbook.md#feature-flags)). It has the shape
`{target: "limit.<name>", value: <number>, reasonCode, minVersion, maxVersion, updatedAt}`:

| Field | Meaning |
|---|---|
| `target` | `limit.<name>`: one limit compiled into the app |
| `value` | A number in the limit's unit. The app applies the lower of this value and the compiled limit, so a remote value can only lower a limit compiled into the app, never raise it. A value above the compiled limit, or one that is not a number, is ignored |
| `reasonCode`, `minVersion`, `maxVersion`, `updatedAt` | As for a switch record |

Targets follow one scheme:

| Target | Switches |
|---|---|
| `ai.provider.claude`, `ai.provider.pcc`, `ai.provider.ondevice` | An intelligence tier ([AI provider failover](ai-provider-failover.md)) |
| `ai.prompt.<id>` | One prompt, by its identifier; `fallback` selects the previous bundled version ([prompt management](../../prompt-management.md#rollback)) |
| `feature.<name>` | One shipped feature, for example `feature.analyse-contract` |
| `limit.<name>` | One compiled limit, lowered by an operational-setting record, for example `limit.claude-pages-per-request` |

### Behaviour in the app

- **Fetch policy.** The app fetches the records at every launch, and when it returns to the
  foreground if the last fetch is more than 15 minutes old (`Assumption:` 15 minutes, validated
  against CloudKit request volume and the time-to-effect drill in [verify](#verify)). It keeps the
  last known value of every record on the device.
- **When a fetch fails.** The last known values apply; with none cached, the defaults compiled into
  the build apply (the shipped behaviour).
- **Propagation.** Changes take effect on the next launch, or on a return to the foreground after the
  interval, not instantly. Assumption: most active users pick up a change within 24 hours; measured
  once implemented.

### Implementation

[ADR-0024](../../adr/0024-remote-configuration-package.md) answers the questions this page left open.
- The `RemoteConfig` package owns remote configuration, and it is on the network allow-list.
- Staging uses the `channel` field in the same container.
- The app polls; it doesn't subscribe.
- The record type is `RemoteSwitch`.

## Before you start

- An incident is open, or the owning hat (AI for providers and prompts, the feature's owner
  otherwise) has asked for the change, and the Incident lead agrees.
- You can sign in to the CloudKit Console with a role that can edit public-database records in the
  development and production environments.
- You know the exact `target`, the app versions affected, and the `reasonCode` whose notice users
  should see.

## Steps

1. Write the intended change and the reason in the incident record, with the time.
2. Open the [CloudKit Console](https://icloud.developer.apple.com/dashboard/), choose the container
   `iCloud.com.algorythmos.pdfalgopro`, the **Development** environment and the **Public** database.
3. Query the configuration record type for the `target`.
4. Set `state` to `disabled` (or `fallback` for a prompt), or for a `limit.<name>` record set `value`
   below the compiled limit; set `minVersion` and `maxVersion` if only some versions are affected;
   set the `reasonCode`.
5. Save, then force-quit and reopen a Debug build that reads the development environment
   ([environments](../environments.md#what-each-environment-may-talk-to)) and confirm the change.
6. Repeat steps 2 to 4 in the **Production** environment, save, and note the time in the incident
   record.

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

1. Set `state` back to `enabled` (for a `limit.<name>` record, set `value` back to the compiled
   limit), in the development environment first and then in production, and note the reason and time
   in the incident record. An `enabled` record shows no notice.
2. Verify on a production build as above.
3. Keep the record rather than deleting it; an explicit value is easier to audit than a fallback to the
   compiled default.

## Record

- The incident record holds each change: target, old and new state, `reasonCode`, time, who changed
  it and why.
- A switch left off for longer than one release gets an issue to fix or remove the feature.
- [`docs/working-memory.md`](../../working-memory.md) lists any switch that is currently off.
