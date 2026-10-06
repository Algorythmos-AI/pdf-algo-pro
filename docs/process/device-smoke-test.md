# Device smoke test

The short check each Staging build gets on a real iPhone before anyone relies on it (plan revision 3,
§9, "Devices"). CI proves each change on the simulator. This checks what only a device shows: real
files, real Face ID, real Apple Intelligence, the system's privacy report, and a kill in the middle of
a save. It complements the [VoiceOver script](voiceover-script.md), which covers accessibility, and
the release checklist in [release management](../release-management.md).

Owner: Quality · Reviewed: whenever a build adds a feature that only a device can show

## Before you start

- Install the build from TestFlight on the iPhone that stays on iOS 26 (owner action O2), and, when
  there is one, on the oldest supported iPhone and on an iPhone on iOS 27.
- Use a synthetic or public test document, never a customer's or a real personal one
  ([AGENTS.md](../../AGENTS.md), rule 6).
- About 15 minutes per device. Note the build number, device and iOS version in the sign-off table.

## Every build

1. **Open, mark up, scan, ask.** Open a document, add a highlight and a note, and scan one page to a
   searchable PDF. Then ask a question and open its citation.
2. **Airplane mode.** Turn it on and repeat step 1. Everything works except what needs the network,
   which is nothing in V1.
3. **Kill in the middle of a save.** Make an edit, then swipe the app away from the app switcher at
   once. Relaunch. The document opens, either as it was or with the edit, and never damaged
   (the save fault-injection tests in the [testing strategy](../testing-strategy.md) cover each step on
   the simulator).
4. **App Privacy Report.** In iOS Settings › Privacy & Security › App Privacy Report, PDF Algo Pro
   lists no network domains (plan H10).
5. **Report a problem.** Settings › Report a problem shows a summary with no document names or text.

## When a build includes these

| Feature | Check |
|---|---|
| Signed PDFs (H9) | Edit a signed test PDF: a notice says the changes went into a copy, and the original still validates in Preview |
| Another app's changes (H5) | With a document open, change it from the Files app on a Mac or iPad (iCloud or AirDrop): the reader reloads, or asks when it has unsaved changes |
| Version history (FR-EDIT-008) | Save twice, then More › Version history and restore the first; Settings › Storage shows the space |
| Move and resize annotations (FR-ANN-005) | Drag a shape and pinch a signature; each is one undo step |
| Links in PDFs (T-02) | Tap a web link: the full address shows before anything opens |
| App Lock (FR-SET-002) | Turn it on; the app switcher shows no document; Face ID, and the passcode after a failure, unlock it |
| Siri summary (FR-AI-018) | "Summarise [document] with PDF Algo Pro" on a locked iPhone asks to unlock first |
| Editing existing text (FR-EDIT-001) | Run the five scenarios in the [text editing device test](text-editing-device-test.md); the full document table before the release flag is turned on |
| First run and the offer (FR-ONB-001, FR-ONB-004) | Delete the app and install it again: three pages, Skip on each; after the last, the offer shows the weekly and the annual plan with Close at the top from the first moment, and one tap on Close leads to Home. Quit and open again: no offer. Repeat in Airplane Mode: first run ends on Home with no offer |
| Buying and restoring (FR-STORE-002, FR-STORE-007) | With a sandbox account, buy the plan with the trial: "Welcome to Pro" follows in the same sheet, with the date the trial ends; Settings › Subscription says so too. Delete the app, install it, Restore purchases: the plan is back. Cancel in Manage subscription. With App Lock on, buy again: no second Face ID prompt for the app after the purchase sheet |
| The free allowance (FR-STORE-008) | With "Pro without a purchase" off in Internal testing and no subscription, save scans until the day's are used: the next Scan opens the offer before the camera, and nothing already scanned is lost. Opening, signing, sharing and exporting still work |
| Assistant follow-ups (FR-AI-014) | Ask "What is the total?" then "When is it due?": the answer uses the first question |

## Sign-off

| Date | Build | Device | iOS | Result | Issues filed |
|---|---|---|---|---|---|
