# App Store Connect subscriptions

How the Pro subscription products are set up and checked in App Store Connect, first for the Staging
app and then for the production app. It records which steps are done, so the next person or agent
continues from there and doesn't start again. The decisions behind it are
[ADR-0026](../../adr/0026-first-run-subscription-offer-and-plans.md) and PAP-043, PAP-049 and PAP-050
in the [decision register](../../decision-register.md).

Owner: Release · Reviewed: after each change to a subscription product, and before the first release

## What stays out of this repository

This repository is public (AGENTS.md hard rule 4). This page holds only the procedure and the state
of each step. Prices, the trial length, App Store Connect app identifiers, the Team ID, bank or tax
details and screenshots of App Store Connect are kept in the confidential pricing edition and the
private companion repository, never here.

## When to use

- Setting up or changing the weekly or annual plan, its introductory offer, Family Sharing, review
  information or localisations.
- Creating or checking the sandbox testers for a purchase test.
- Repeating the setup for the production app, once Staging has passed.

## Before you start

- **A browser you can drive.** A cloud agent session has no browser and can't open App Store
  Connect. Use a Claude Code session on the owner's Mac with Claude in Chrome connected, or have the
  owner click while an agent guides. Any sign-in, password or two-factor prompt is the owner's.
- **The right team and app.** The team at the top right is the company's. The app is "PDF Algo Pro
  Staging" until the owner says Staging has passed.
- **The plan.** The confidential pricing edition holds the values to set: each plan's prices and the
  trial. Shape decided in this repository:
  - One subscription group, "PDF Algo Pro", with both plans on the same level. There is no monthly
    plan, and the annual plan is paid upfront only.
  - The annual plan carries the free trial, for new subscribers in every country or region. The
    weekly plan has no introductory offer (PAP-049).
  - Family Sharing is on for the annual plan and off for the weekly plan (PAP-050). Once on, it can't
    be turned off.
  - Both plans are available in all countries or regions, with English (U.S.) and French
    localisations and a review screenshot.

## Product identifiers

The app derives them from its own bundle identifier
(`Packages/Commerce/Sources/Commerce/ProductCatalog.swift`, called from
`App/PDFAlgoPro/AppContainer.swift`), so the two apps never share a product:

| App | Bundle identifier | Annual plan | Weekly plan |
|---|---|---|---|
| Staging | `com.algorythmos.pdfalgopro.staging` | `com.algorythmos.pdfalgopro.staging.pro.yearly` | `com.algorythmos.pdfalgopro.staging.pro.weekly` |
| Production | `com.algorythmos.pdfalgopro` | `com.algorythmos.pdfalgopro.pro.yearly` | `com.algorythmos.pdfalgopro.pro.weekly` |

The paywall lists the annual plan first (`ProductCatalog.ordered`).

## Guardrails

- **One change at a time.** Record the value before the change, save, reload the page, record the
  value after, and take a screenshot. Screenshots are kept outside this repository.
- **Owner's explicit yes required for:**
  - Add for Review, Submit or Remove from Sale.
  - Turning Family Sharing on.
  - Creating, renaming or deleting a product, group or offer.
  - Monthly with a 12-month commitment, Multiseat, App Store Promotion, offer codes, promotional or
    win-back offers.
  - A price that already matches the plan, and any warning about existing subscribers.
  - Anything under Business or Users and Access, except creating sandbox testers.
  - Anything on the production app before the owner says Staging has passed.
- **Stop and ask** at any dialog the plan doesn't explain. Cancel it; never confirm it.
- **Never submit Staging.** Its products stay at "Ready to Submit"; sandbox purchases work at that
  status.

## Steps

1. **Pre-flight (read-only).**
   - In Business: the Paid Apps Agreement, bank account and tax forms are Active.
   - In the repository: the product identifiers above still match `ProductCatalog.swift`.
   - In TestFlight: the newest Staging build was built from a commit that includes the paywall
     change (#166, merged 2026-10-07 13:11 UTC) or a later one.
2. **The group** (the Staging app's Subscriptions page). Both identifiers, durations and the shared
   level match the plan. The group's display name exists in English (U.S.) and French.
3. **The annual plan**, in this order:
   1. Family Sharing on (with the owner's yes).
   2. Only upfront payment offered.
   3. Prices as in the confidential edition; check the equalised prices in Australia, the United
      Kingdom and one euro storefront.
   4. The free trial for all countries or regions, starting today, with no end date.
   5. The English (U.S.) and French localisations.
   6. The review screenshot and the review notes below.
   7. Available in all countries or regions.
4. **The weekly plan.**
   1. Family Sharing stays off.
   2. Prices as in the confidential edition.
   3. Remove any introductory offer: it is left over from PAP-043, before PAP-049 moved the trial.
   4. The localisations, review information and availability, as for the annual plan.
5. **Final status.** Back on the group page, both plans read "Ready to Submit". If one reads "Missing
   Metadata", the page names the missing field.
6. **Sandbox testers** (Users and Access › Sandbox). One United States and one Australia tester.
   The owner chooses the email address and sets the password.

Review notes for both plans: "Pro removes the daily limits on scans and on-device answers. Opening,
reading, signing, sharing and exporting documents never need Pro."

Localisations:

| Plan | English (U.S.) | French |
|---|---|---|
| Annual | Pro Yearly — Every Pro feature, billed yearly | Pro annuel — Toutes les fonctions Pro, par an |
| Weekly | Pro Weekly — Every Pro feature, billed weekly | Pro hebdomadaire — Toutes les fonctions Pro, par semaine |

## Verify

On an iPhone with the Staging build from TestFlight (never the Debug scheme). A TestFlight build
buys with the tester's own Apple Account and charges nothing
([Testing subscriptions and In-App Purchases in TestFlight](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testing-subscriptions-and-in-app-purchases-in-testflight));
sandbox testers are for builds run from Xcode. Each new Staging build shows first run once by
itself (PAP-053); Settings › Internal testing › Show first run again repeats it. The offer follows
only with "Pro without a purchase" off:

- The annual plan is listed first, marked "Best Value", with a saving that matches the two prices.
  The app works it out as 52 weekly payments against one annual payment, rounded down (PAP-049).
- Buying the annual plan starts the trial; the weekly plan is charged with no trial.
- Restore Purchases brings Pro back after reinstalling.
- A family member gets Pro from the annual plan only.

Then run the store rows of the [device smoke test](../device-smoke-test.md).

Introductory offers count per subscription group. An account that took the old weekly trial isn't
offered the annual trial. The prices shown are those of the account's storefront.

## Record

Update the log below after every session that changes or checks the setup, and the subscription row
in [working memory](../../working-memory.md). Write each entry as the date, the app (Staging or
Production), the step, and the result. Leave out any value from the list above.

| Date | App | Step | Result |
|---|---|---|---|
| 2026-10-08 | — | Pre-flight, repository | Passed: the identifiers derive from the bundle identifier, and the annual plan is listed first. #166 merged 2026-10-07 13:11 UTC; the sandbox test needs a Staging build that includes it |
| 2026-10-08 | — | Pre-flight, Business | Passed: the owner confirmed the agreements, banking and tax forms are active. One Business compliance item (Australia's Sharing Economy Reporting Regime) asks the owner for information. It doesn't block the subscription setup; the owner completes it |
| 2026-10-08 | Staging | Pre-flight, TestFlight | Passed by date: the newest build was uploaded after #166 merged. App Store Connect does not show the commit a build was made from |
| 2026-10-08 | Staging | Steps 2 to 5 | Done in the browser and read back after a reload: identifiers, durations and the shared level; the annual plan's prices from the new base with the United Kingdom and every euro storefront set by hand, its trial, and Family Sharing (already on); the weekly plan's Australian price set by hand and its trial removed; both localisations and the review notes. Apple's automatic prices did not give the plan's United Kingdom and euro figures, and two of the plan's figures are "additional" price points. Both plans read "Prepare for Submission", which is what the web page calls ready to submit. The review screenshot is still a placeholder |
| 2026-10-08 | Staging | Verify, on the simulator | The offer loads the Staging plans from the App Store's sandbox in a Staging build: the annual plan first with its trial, the weekly plan without, and the saving line once the app recognised a week given as seven days (PAP-052). Buying, restoring and Family Sharing still need a device |
| — | Staging | Step 6 | Not needed for TestFlight; sandbox testers are created only if a build is to be tested from Xcode |
| — | Production | Steps 2 to 5 | Locked until Staging passes |
