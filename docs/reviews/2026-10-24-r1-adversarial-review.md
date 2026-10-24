# R1 adversarial review: the paths that can lose, damage or wrongly charge

A structured, read-only review of the code paths that can lose or damage a person's document or
library, lock them out, or charge them wrongly. It is step R1 of the 1.0 robustness track: every
defect found has its own GitHub issue with file and line evidence, a failure scenario, the user
impact, a sketched regression test that must fail before the fix, and a proposed fix. Nothing was
fixed in this review; fixes follow in R3, each with its regression test
([testing strategy](../testing-strategy.md), [quality gates](../process/quality-gates.md)).

Owner: Quality · Reviewed: once, at the commit below; superseded by the R3 fix PRs and the R6 release gate

## Scope and method

- **Commit reviewed:** `integration` at `e49ecc1`, on 2026-10-24.
- **Method:**
  - The code and its existing tests were read area by area, by one reviewer per area.
  - Each claim used for a p1 finding was checked again against the code before it was filed.
  - Where a test needs a device, the logic was traced on paper and the issue says so ("Suspected").
  - One finding (password removal and links) was reproduced with a short PDFKit program on macOS.
- **Status words:**
  - "Confirmed" means the code path was traced end to end.
  - "Suspected" means the path is real but depends on runtime behaviour or timing that was not reproduced.
- **Priorities follow the owner's rule:**
  - **p0:** loses or corrupts a document, or charges wrongly.
  - **p1:** the person is stuck, a lock is bypassed, data is wrong, or a paying person loses what they paid for.
  - **p2:** wrong but recoverable, or minor.
  - **p3:** cosmetic or a guard-rail gap.
  - While a p0 or p1 bug is open, no UI refresh PR merges.

## Result

53 defects, each with its own issue: **0 at p0, 14 at p1, 27 at p2, 12 at p3.**

- **Recognition (p1).** The open reader keeps the document from before recognition replaced the file, so a save in that window writes the old document over the searchable one ([#219](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/219)).
- **App Lock (p1).** The lock can become permanent when the device passcode is removed ([#221](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/221)). Siri and Shortcuts can also read summaries and titles past it ([#222](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/222)).
- **The library index (p1).**
  - It has no file identity, so a rename in the Files app loses tags and earlier versions ([#224](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/224)).
  - A move whose index write fails is not undone ([#225](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/225)).
  - One failed open of the index starts an empty library that is never recovered ([#226](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/226)).
- **Commerce (p1).**
  - A purchase StoreKit can't verify is reported as "nothing has been charged" ([#228](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/228)).
  - Three resolution paths can withhold Pro from a paying person ([#227](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/227), [#229](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/229), [#230](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/230)).
- **The save path itself held.**
  - Staging, validation and the coordinated atomic replace survive a fault at every step.
  - Encryption and permissions are preserved.
  - The defects are around it: copies whose failure marks changes as saved ([#223](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/223)), and password removal re-pointing links ([#235](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/235)).

## Areas: what was checked

### (a) Save path

Read: `PDFDocumentController+Saving.swift`, `PDFDocumentController.swift`, `+Forms`, `+Pages`,
`DigitalSignatures.swift`; `ReaderModel` save, signed copy, conflict and version paths; `FileVersion`,
`FileWatcher`, `BackgroundTime`, `VersionHistorySheet`; `FileDocumentLibrary` versions; the
`SaveFaultTests`, password (D9) and signature tests.

Sound:

- **Temp write and rename.** The file is staged on the same volume (`itemReplacementDirectory`), reopened, page-counted and text-checked. It then replaces the original under `NSFileCoordinator(.forReplacing)`. A fault at each step leaves the original, or the new file plus the kept one (`SaveFaultTests`).
- **Disk full.** A space check runs before writing, with a spare margin, and a write error is reported as a failed save with the file unchanged.
- **Encryption and permissions.** These are kept for the owner password, the user password and owner-only restrictions. Changes the author doesn't allow are refused (D9 tests).
- **Version history.** Each save keeps the version before it, pruned by retention and the quota. A restore keeps the current version first.
- **File replaced underneath (one writer per document).** The reader tells its own save from another app's change by `FileVersion`, and offers keep-mine or use-theirs.
- **Signed documents.** These are saved as a copy, and the original is left byte-for-byte.
- **Save on background.** `saveBeforeSuspending` runs under a background task.

Defects: [#223](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/223), [#233](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/233), [#234](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/234), [#235](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/235), and the conflict-during-save race [#257](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/257).

### (b) Text editing

Read: `TextEditing/*.swift`, `PDFDocumentController+TextEditing.swift`, the text-editing parts of
`ReaderModel`, [the text-editing architecture](../pdf-text-editing-architecture.md) and PAP-039,
and the engine and reader text-editing tests.

Sound:

- **Parser limits.** Every index is bounds-checked, integers are parsed with an overflow check, nesting stops at depth 64, sizes are capped, and the cross-reference walk catches cycles.
- **Malformed operands** (`TJ`, `Tf`, matrices) make a run uneditable instead of crashing.
- **Rewriting.** The final page is always redrawn by Core Graphics and Core Text, so no broken content stream and no document-font glyphs reach the file.
- **Proof.** A failed proof never reaches the document, and late answers are discarded.
- **Undo** puts back the original page object.
- **Rotation.** Rotated pages are handled in one coordinate space.
- **Fonts.** Missing fonts, Type3 and missing ToUnicode give cover-only lines.
- **No dead end (PAP-039).** Cancel and Close are always reachable, within the time limits.
- **Disk.** Nothing touches the disk before Done.

Defects: [#231](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/231), [#232](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/232), [#249](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/249), [#250](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/250), [#251](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/251), [#252](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/252), [#268](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/268), [#269](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/269).

### (c) Library index, Spotlight and migrations

Read: `FileDocumentLibrary`, `LibraryIndex` (with `LibraryMigrationPlan`), `KeychainSignatureStore`,
`LocalSearchIndex`, `SpotlightIndexer`, `DocumentIntake`, the library parts of `LibraryModel` and
`AppContainer`, [ADR-0006](../adr/0006-swiftdata-persistence.md), and the store and library tests.

Sound:

- **One writer.** The library is an actor whose changes run one at a time, in order. There is no extension, so there is no second process.
- **Writes.** File writes are coordinated and atomic.
- **Deletion.** Deleting goes to Recently Deleted for 30 days, with Undo, and a permanent delete is confirmed. No path deletes one document for another.
- **Intake.** An existing document is never deleted because it failed inspection.
- **Spotlight removal** follows delete, purge and reconcile.
- **Keychain.** A read failure is reported, not taken as "no signatures".
- **Backup.** The index is backed up; derived search text is not.
- **iCloud eviction** can't happen today, because the library is the app's own Documents folder. Recorded as a latent risk for any future iCloud container: reconcile would delete an evicted file's entry.

"An older build never wipes a newer store" holds only in the sense that the store's bytes are moved aside. The person still sees an empty library ([#226](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/226)).

Defects: [#224](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/224), [#225](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/225), [#226](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/226), [#237](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/237), [#241](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/241), [#242](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/242), [#243](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/243), [#244](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/244), [#263](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/263).

### (d) Commerce

Read: every file in `Packages/Commerce`, `TrialReminderScheduler`, `MeteredIntelligence`,
`InternalEntitlementOverride`, the commerce parts of `AppContainer` and `AppModel`, `PaywallFeature`,
the Commerce, Paywall and app store tests, and the StoreKit configuration.

Sound:

- **Unverified and revoked transactions** grant nothing, and refunds are recomputed from the updates stream.
- **No cached entitlement** can outlive the real state.
- **The updates listener** starts once and lives for the whole app.
- **Trial status** comes from the transaction's own free introductory offer.
- **A cancelled purchase** is told apart from a failure.
- **The trial reminder** is idempotent and is never scheduled for a non-trial.
- **The allowance**
  - is charged only on success;
  - stores its counts and its day key as one atomic write;
  - is not refilled by setting the clock back a day.
- **The internal override** exists only in INTERNAL_TOOLS builds.
- **The only existing Pro feature** (text editing) is gated.

Not filed as a defect:

- **Contract analysis** is free within the allowance, while the pricing table marks it as a preview for free users. That is the owner's decision to record, either way.

Defects: [#227](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/227), [#228](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/228), [#229](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/229), [#230](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/230), [#245](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/245), [#246](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/246), [#247](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/247), [#248](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/248), [#259](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/259), [#264](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/264), [#265](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/265), [#266](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/266), [#267](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/267).

### (e) Concurrency, cancellation and App Lock

Read:

- every `Task`, `Task.detached`, `.task`, task group, sleep and cancellation site in `App/` and `Packages/*/Sources`;
- `ReaderModel`, `RecognitionCoordinator`, `ContinuedWork`, `AssistantModel`, `ScanModel` and `LibraryModel`;
- `AppLock` and `PDFAlgoProApp`;
- the matching tests.

Sound:

- **The open `PDFDocument`.**
  - It is mutated only on the main actor.
  - Off-main text work uses data snapshots, with identity checks on return.
  - Every `assumeIsolated` and `@unchecked Sendable` site was checked.
- **Background recognition.**
  - The continued-processing task completes exactly once.
  - Per-page checkpoints resume after the app is killed.
- **The assistant** drops late results and never interleaves two answers.
- **App Lock.**
  - Its window covers sheets and alerts.
  - It covers on inactive and locks on background.
  - It never loops the Face ID prompt.
- **A StoreKit purchase** makes the scene inactive, not background, so App Lock doesn't fire. A device check is still needed to confirm the payment sheet shows above the cover.

Defects: [#219](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/219), [#220](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/220), [#221](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/221), [#222](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/222), [#253](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/253), [#254](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/254), [#255](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/255), [#256](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/256), [#257](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/257), [#258](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/258), [#270](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/270), [#271](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/271).

### (f) Error handling

Every `try?` and every `catch` in `App/` and `Packages/Features/*/Sources` was read in context. There are 100 sites: 56 `try?` and 44 `catch`.

- **No `try?` wraps a document save, move, delete or rename.**
- **Every error string a `catch` sets** is bound to an alert, a banner or a phase view.
- **88 sites are acceptable**; they are listed below.
- **The defects** are search or Spotlight refreshes that are never retried, silent drops in photo import and merge, a cancelled sleep that still acts, and misleading messages.

Defects: [#236](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/236), [#237](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/237), [#238](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/238), [#239](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/239), [#240](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/240), [#243](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/243), [#260](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/260), [#261](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/261), [#262](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/262), and [#234](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/234) (a misleading `catch`).

Not covered by (f):

- `Packages/Commerce`, `DocumentStore`, `Search` and `PDFEngine` contain another 45 `try?` sites.
- The ones that matter were read in areas (a) to (d). For example, a failed folder listing during reconcile becomes an empty list, so files aren't picked up but aren't deleted either.

## Findings by priority

### p1 (14)

| Issue | Area | Defect |
|---|---|---|
| [#219](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/219) | Concurrency and App Lock | A save while recognition finishes writes the old document over the searchable file |
| [#220](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/220) | Concurrency and App Lock | Recognition can replace the file while a form field is being typed in, losing the entry |
| [#221](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/221) | Concurrency and App Lock | App Lock locks the person out for good when the device passcode is removed |
| [#222](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/222) | Concurrency and App Lock | Siri and Shortcuts read document summaries and titles while App Lock is on |
| [#223](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/223) | Save path | A failed copy save marks the changes as saved, so they are lost |
| [#224](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/224) | Library | Renaming or moving a PDF in the Files app wipes its tags, favourite, position and earlier versions |
| [#225](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/225) | Library | A file move whose index write fails is not undone, and the user is told nothing changed |
| [#226](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/226) | Library | One failure to open the library index starts an empty library, and nothing puts the old one back |
| [#227](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/227) | Commerce | A refresh that finishes late can overwrite a newer entitlement |
| [#228](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/228) | Commerce | A purchase StoreKit can't verify is reported as "Nothing has been charged" |
| [#229](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/229) | Commerce | A subscriber whose trial just converted can be treated as having an ended trial and lose Pro |
| [#230](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/230) | Commerce | A subscriber in the billing grace period can lose Pro when the renewal state can't be read |
| [#231](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/231) | Text editing | An invisible or missing character in replacement text turns the whole page into cover-only |
| [#232](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/232) | Text editing | A text edit that fails the save check blocks every later save until it is undone |

### p2 (27)

| Issue | Area | Defect |
|---|---|---|
| [#233](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/233) | Save path | Two quick saves of a signed document make two "(edited)" copies |
| [#234](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/234) | Save path | After a save succeeds, an index failure is reported as "the document on disk hasn't changed" |
| [#235](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/235) | Save path | Removing a password re-points links between pages to the first page |
| [#236](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/236) | Error handling | Search and Spotlight are never brought up to date when a refresh fails after a password, text edit or restore |
| [#237](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/237) | Error handling | The Spotlight migration marks itself done even when it re-indexed nothing |
| [#238](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/238) | Error handling | Photos that fail to load are dropped without a word, and if all fail nothing happens |
| [#239](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/239) | Error handling | Merge silently leaves out a document whose file can't be found |
| [#240](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/240) | Error handling | Deleting a second document within 8 seconds can clear its Undo straight away |
| [#241](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/241) | Library | Spotlight keeps a document's old title and tags after a rename or a tag change |
| [#242](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/242) | Library | A different PDF saved under an existing document's name takes over its tags, position and search text |
| [#243](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/243) | Library | An import whose index entry fails comes back as a duplicate, and every failure is called "not a readable PDF" |
| [#244](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/244) | Library | The library index opens, and any migration runs, on the main thread at launch |
| [#245](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/245) | Commerce | The free daily allowance can stay used up indefinitely after a calendar or clock change |
| [#246](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/246) | Commerce | The trial-ends reminder fires at the wrong moment after the person changes time zone |
| [#247](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/247) | Commerce | Restore Purchases says nothing when there is nothing to restore, and blames the Apple ID when offline |
| [#248](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/248) | Commerce | Settings says "Pro, payment problem" during billing retry while Pro is locked |
| [#249](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/249) | Text editing | A text edit being made is silently thrown away if the file changes on disk meanwhile |
| [#250](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/250) | Text editing | A crafted font width table crashes the text editor with an integer overflow |
| [#251](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/251) | Text editing | The cover's colour is sampled from the wrong place on rotated pages and pages whose box is offset |
| [#252](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/252) | Text editing | Table columns on one line are offered and redrawn as one string, collapsing the columns |
| [#253](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/253) | Concurrency and App Lock | When the system ends background recognition, every page recognised so far is thrown away |
| [#254](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/254) | Concurrency and App Lock | The recognition Live Activity shows the document title on the Lock Screen even with App Lock on |
| [#255](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/255) | Concurrency and App Lock | Recognition on a signed document's copy can replace the copy behind the open reader |
| [#256](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/256) | Concurrency and App Lock | A crash just after recognition writes the file makes the next launch add a second text layer |
| [#257](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/257) | Concurrency and App Lock | A conflict noticed mid-save still writes over the other app's version |
| [#258](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/258) | Concurrency and App Lock | Hiding the App Lock window may give keyboard focus to the wrong window |
| [#259](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/259) | Concurrency and App Lock | The assistant charges the daily allowance for a request that was cancelled or replaced |

### p3 (12)

| Issue | Area | Defect |
|---|---|---|
| [#260](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/260) | Error handling | Share or Print does nothing when the file can't be found after a successful save |
| [#261](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/261) | Error handling | The reader's own save can be taken for another app's change when the file's details can't be read |
| [#262](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/262) | Error handling | "Reduce size" with an unreadable file size always makes a copy and shows a nonsense size |
| [#263](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/263) | Library | Changing only the capitalisation of a title adds " 2" to the file name |
| [#264](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/264) | Commerce | A trial reminder can fire for someone who has already paid or been refunded |
| [#265](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/265) | Commerce | Two requests started together can each pass the last free request |
| [#266](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/266) | Commerce | A purchase waiting for approval (Ask to Buy) leaves the button ready for a second request |
| [#267](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/267) | Commerce | The CI check for internal tools in Release builds doesn't look for the entitlement override |
| [#268](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/268) | Text editing | A batch of text edits can report edits as made when none were |
| [#269](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/269) | Text editing | Small text-editing slips: real-number Tr, the undo memory counter, and Undo from the cover notice |
| [#270](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/270) | Concurrency and App Lock | Recognition replaces the file without file coordination |
| [#271](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/271) | Concurrency and App Lock | The assistant can start a request after its sheet has closed |

## Acceptable `try?` and `catch` sites, with reasons

88 of the 100 sites in area (f). Line numbers are at `e49ecc1`.

| Site | What is swallowed | Why it is acceptable |
|---|---|---|
| `TrialReminderScheduler.swift:21` | notification authorisation error | Treated as declined: the toggle turns off and the in-app trial notice is shown instead (FR-STORE-006). |
| `TrialReminderScheduler.swift:32` | scheduling error | Returns false. The caller doesn't record the reminder, and the in-app notice still shows. |
| `ReviewPrompter.swift:29`, `:54` | review-policy decode or encode | A fresh policy is used. The worst case is one extra review request, which the system rate-limits. |
| `AppLock.swift:23` | `evaluatePolicy` error | Fails closed: the app stays locked with Unlock. The lockout case is [#221](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/221). |
| `AppModel.swift:104-117` (6 sites) | seeding UI-test fixtures | Runs only under the UI-test seed launch environment, where a missing seed fails the test visibly. |
| `AppModel.swift:153` | cancellation of `waitForTheStore`'s sleep | Never cancelled today. |
| `AppIntents.swift:73` | library listing for Siri suggestions | Read only: Siri shows no suggestions, and the intent itself throws `documentMissing`. |
| `AppContainer.swift:364` | diagnostics document count | Only diagnostics text. |
| `AppContainer.swift:433-448` (4 sites) | creating folders | Each later use throws on its own path and is reported there (save, search index, checkpoints). |
| `AppContainer.swift:456` | excluding a derived folder from backup | Retried every launch. The worst case is backing up a derived folder. |
| `ReaderModel.swift:180` | file version on load | A nil version causes at most one reload, with no unsaved changes. |
| `ReaderModel.swift:280` | `recordOpened` | Only the last page and the opened date. It is retried on every page change and on close. |
| `ReaderModel.swift:749`, `ReaderView.swift:47`, `TextEditViews.swift:483`, `LibraryView.swift:146` | cancellation of a short sleep | Each is followed by a cancellation or state check. |
| `ReaderModel.swift:1085`, `:1167` | removing a temporary file | Best-effort cleanup; the system purges tmp. |
| `ReaderModel.swift:1142` | file version in `fileChangedOnDisk` | Doing nothing is correct: the next presenter event checks again. |
| `ReaderModel.swift:1412` | reading stored page text for the assistant | Falls back to the live text layer. |
| `RecognitionCoordinator.swift:206-223` (6 sites) | reading checkpoint format, version and pages | A missing or corrupt checkpoint means recognising again: slower, but correct. |
| `RecognitionCoordinator.swift:232` | writing a page checkpoint | Only an optimisation; the final write uses `try`. |
| `RecognitionCoordinator.swift:238`, `:243` | removing or listing checkpoints | Best-effort cleanup, and nothing resumes. Leftover folders are a p3 note under [#256](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/256). |
| `LibraryModel.swift:267`, `:493` | file URL for details or a thumbnail | The sheet shows its "can't be read" state, or a placeholder thumbnail. |
| `ScanModel.swift:77` | recognition for a title suggestion | Keeps the default "Scan <date>" title. |
| `catch` `EvaluationSection.swift:161` | writing the evaluation report | Internal tools only; the share link is hidden. |
| `catch` `PDFAlgoProApp.swift:41` | `Tips.configure` | Tips are optional; logged. |
| `catch` `ContinuedWork.swift:130` | `BGTaskScheduler.submit` | Falls back to ordinary background time. |
| `catch` `LibraryModel.swift:135-173` (5 sites) | purge, reconcile, refresh, index removal, prune | Background housekeeping. Counted in telemetry and retried at the next launch; prune is skipped when listing fails. |
| `catch` `LibraryModel.swift:242` | search | Shown as "search unavailable". |
| `catch` `AppIntents.swift:54-60` (4 sites) | intelligence errors | Rethrown as intent failures, which Siri shows. |
| `catch` `ReaderModel.swift:204` | load | Shown as the failed phase. |
| `catch` `ReaderModel.swift` (12 sites: 426, 957, 970, 981, 1063, 1065, 1175, 1224, 1268, 1282, 1302, 1304) | extract, signatures, save, restore, flatten, image, compress | Each sets `errorMessage`, which the reader's alert shows. |
| `catch` `ReaderModel.swift:1071` | save | Shown. Its misleading wording is [#234](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/234). |
| `catch` `RecognitionCoordinator.swift:167`, `:170` | recognition cancel or failure | Reaches the reader's message, apart from the cancel case in [#219](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/219). |
| `catch` `AssistantModel.swift:142-148` (4 sites) | intelligence outcomes | Rendered as the assistant's phase. |
| `catch` `SettingsModel.swift:140` | deleting kept versions | Shown in Settings' alert. |
| `catch` `LibraryModel.swift` (6 sites: 209, 324, 350, 447, 451, 502) | reload, sample, photos, merge, actions | Each sets `errorMessage`, which the library's alert shows. |
| `catch` `LibraryModel.swift:303` | import | Counted, then shown. Its wording is [#243](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/243). |
| `catch` `ScanModel.swift:173`, `:175` | scan build or add | Shown as the failed phase. |

## What comes next

- **R3** fixes the open defects, p1 first. Each fix PR adds the sketched regression test, shows it failing before the fix, and links a green CI run.
- **The suggested order:**
  1. Recognition hand-over: [#219](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/219), [#220](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/220) and [#255](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/255). They share one fix in `RecognitionCoordinator.run`.
  2. App Lock: [#221](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/221) and [#222](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/222).
  3. Library identity and index safety: [#224](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/224), [#225](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/225) and [#226](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/226). These need a schema V2 and the index seam from ADR-0006.
  4. Commerce resolution: [#227](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/227) to [#230](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/230).
  5. Copy saves and text editing: [#223](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/223), [#231](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/231) and [#232](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/232).
- **Device checks for R4:**
  - a purchase with App Lock on;
  - App Lock window focus ([#258](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/258));
  - a form field typed during recognition ([#220](https://github.com/Algorythmos-AI/pdf-algo-pro/issues/220)).
