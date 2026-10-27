# Device test run

The app's unit tests and UI tests run on a real iPhone from a commit, followed by the manual checks no
test can make. CI proves every change on the simulator: the required `ios` gate with the pinned Xcode
26.6 on iOS 26, and an iOS 27 simulator job built with Xcode 27 beside it
([quality gates](quality-gates.md), [ci.yml](../../.github/workflows/ci.yml)). This run catches what
only a device shows. The [device smoke test](device-smoke-test.md) is a different check: it is made on
a TestFlight build. Both stay.

Owner: Quality · Reviewed: whenever Device.xctestplan or the device scripts change, and each milestone

## What it proves that CI cannot

- **The real camera.** The document camera (`DocumentCamera` in the Scanning package) does not exist
  on the simulator, so the UI tests check scanning without a camera (`ScanUITests`), which a phone
  with a camera may answer differently. A class whose name ends in `DeviceUITests` runs only in this
  plan, so a real-camera test can be added without breaking CI.
- **The Keychain and Face ID on hardware.** App Lock and the stores that use the Keychain run against
  the Secure Enclave, signed with the team's real identity, not CI's ad hoc signature.
- **Speech, print and the system sheets.** Read aloud (`SpeechReader`) uses the phone's voices; print
  opens the real print controller; StoreKit's purchase sheets appear only with a sandbox account.
- **Apple Intelligence.** The on-device model answers only on a device that has it. On CI's
  simulator it neither answers nor says it is unavailable (`StoreScreenshotTests`).
- **Hardware timing.** Animations, the accessibility tree and saving run at a phone's speed, not a
  runner's.

It does not replace CI. Package test targets cannot run on a device: Xcode says "Tool-hosted testing
is unavailable", so `Device.xctestplan` holds only the app-hosted targets, and the package tests stay
CI's. Each run records CI's `ios` conclusion on the same commit.

## How to run it

Before you start: at least 8 GiB free on the Mac, the phone connected with a cable and unlocked,
Developer Mode on, auto-lock set to Never, a Focus on so no notification covers the screen, and
`Config/Team.xcconfig` holding the line `DEVELOPMENT_TEAM = <your Team ID>` (git-ignored, ADR-0015).
For `--purchases`, sign in to a sandbox account in Settings › Developer › Sandbox Apple Account.

```sh
xcrun devicectl list devices                  # the phone's Identifier
scripts/dev/device_tests.sh --check --device <Identifier>   # only the preconditions
scripts/dev/device_tests.sh --device <Identifier>           # or DEVICE_ID=<Identifier> scripts/dev/device_tests.sh
```

| Flag | What it does |
|---|---|
| `--device ID` (or `DEVICE_ID`) | The phone: its Identifier or UDID from `devicectl`, or its name. Never written to a file |
| `--only Target/Class` | Only these tests (comma-separated, as `-only-testing` takes them) |
| `--purchases` | Also `PurchaseDeviceUITests`, when it exists: buys with the sandbox account |
| `--live-model` | Also `LiveIntelligenceDeviceUITests`, when it exists: asks the phone's own model |
| `--keep-dd` | Keeps the build's intermediates (deleted by default to save space) |
| `--no-record` | Does not add a row to the runs table below |
| `--check` | Checks the preconditions and stops |

The script ([device_tests.sh](../../scripts/dev/device_tests.sh)):

1. Checks the preconditions and says how to fix each one that fails: Xcode 27, a Team ID in
   `Config/Team.xcconfig` (never printed), XcodeGen, free disk, and the phone in `devicectl` (paired,
   Developer Mode on). A phone reached over Wi-Fi shows as "available (paired)" rather than "connected":
   the run works, but can drop, so the script warns and goes on. Before each xcodebuild run that needs
   the phone it asks `devicectl` about it, which sets the connection up again: on 2026-10-26 the first
   run gave up on "The tunnel was interrupted while establishing connectivity".
2. Generates the project and the test plans (`xcodegen generate`, then
   [write_testplan.py](../../scripts/ci/write_testplan.py)).
3. Builds for testing with the `Device` plan, Debug, automatic signing
   (`-allowProvisioningUpdates`), into a DerivedData folder outside the repository
   (`DEVICE_TESTS_DERIVED_DATA` overrides it).
4. Runs the tests into a result bundle, then runs the failed tests once more on their own, as CI's UI
   shards do (at most three; [test_shards.py](../../scripts/ci/test_shards.py) `retry-args device`).
   When the UI test runner loses the phone partway (most often over Wi-Fi), xcodebuild ends the run
   and the tests it had not reached never run: the script lists the plan's tests
   (`-enumerate-tests`), runs the ones no result holds, with the ones that failed, and repeats while
   tests are still missing, up to three rounds
   ([device_resume.py](../../scripts/dev/device_resume.py)). A test that never ran in any round fails
   the run. Tests are asked for as `-enumerate-tests` lists them, "()" and all: the app's unit tests use
   Swift Testing, which `-only-testing` finds only with it.
5. Reports with [xcresult_report.py](../../scripts/ci/xcresult_report.py) and exports the
   attachments of every result bundle, the resumed rounds' too: every failed test's screens under
   `failed-attachments/`, and everything the tests kept
   (with `UI_EVIDENCE=all`, quarantined findings too) under `attachments/`.
6. Adds a row to the runs table with [device_run_record.py](../../scripts/dev/device_run_record.py)
   and prints the manual checklist.

Results go to `.build/device-tests/<date>-<time>-<commit>/` (git-ignored; `DEVICE_TESTS_RESULTS`
overrides it): the result bundle, the logs, `summary.md` and the attachments.

`Device.xctestplan` skips, beside the performance classes and the store screenshots: the snapshot suite
(its references are recorded on CI's simulator and always differ on a device) and the StoreKit test
session suite (it needs a run started from Xcode). It sets `UI_DEVICE=1` and `UI_EVIDENCE=all` for
the tests, and has coverage off.

When the UI test runner cannot start ("Timed out while enabling automation mode"), none of the UI tests
run and xcodebuild cannot list them either; the summary says so under "Not listed" and the run fails.
On the phone: wake and unlock it, check that Settings › Developer › Enable UI Automation is on, and run
again; when it still times out, restart the phone.

## Xcode 27 here, Xcode 26.6 in CI

The Mac builds with Xcode 27, the toolchain of [ADR-0023](../adr/0023-ios-26-floor-built-with-xcode-27.md);
CI's required gate still pins Xcode 26.6. So:

- **A new warning is a finding.** The project treats warnings as errors
  (`SWIFT_TREAT_WARNINGS_AS_ERRORS: YES` in `project.yml`). A warning only Xcode 27 raises is fixed in a
  pull request; it is never worked around with `SWIFT_TREAT_WARNINGS_AS_ERRORS=NO`.
- **An accessibility audit finding on iOS 27 is real.** Fix it, or quarantine it with an issue the same
  day, as the [flaky test rules](../testing-strategy.md#flaky-tests) say.
- **Snapshots are excluded.** Their references belong to CI's pinned simulator.
- **Package.resolved may change.** Xcode 27 can rewrite the lockfile while it builds. Restore it with
  `git checkout -- '*Package.resolved'` before committing anything, or CI's lockfile check fails.
- **The row names CI's conclusion.** A pass here and a failure in CI on the same commit is a toolchain
  or runtime difference to investigate, not a pass.

## Manual checklist

After the automated run, on the same build, in this order. The details of each are in the
[device smoke test](device-smoke-test.md).

Items 6, 8 and 9 are also run by `ManualChecklistDeviceUITests` in the `Device` plan: the app killed ten
times at different moments of a save, each time opening the document again undamaged; Print showing the
print controller; Report a problem opening Mail with a summary that names no document, closed unsent.
When that class passed, they are done; check them by hand only when it failed.

1. **Face ID.** Turn on App Lock, lock the phone, open the app: the real Face ID prompt shows, and after
   a failure the passcode unlocks it.
2. **Camera scan.** Scan two pages with the real camera: one searchable PDF with both pages.
3. **Buy and restore.** With a sandbox account, buy the plan with the trial, delete the app, install it
   again, Restore purchases: the plan is back.
4. **Siri summary.** "Summarise [document] with PDF Algo Pro" on the locked phone asks to unlock first.
5. **Privacy and airplane mode.** The App Privacy Report lists no network domains for the app. Turn on
   Airplane Mode and repeat steps 2 and 4: everything works.
6. **Kill in the middle of a save.** Edit, swipe the app away at once, open it again: the document is as
   it was or has the edit, never damaged.
7. **Another app's change.** Change an open document from the Files app on another device: the reader
   reloads, or asks when it has unsaved changes.
8. **Print.** Print a document: the print controller shows its pages.
9. **Report a problem.** Settings › Report a problem opens Mail with a summary that holds no document
   names or text.
10. **VoiceOver.** Run the [VoiceOver script](voiceover-script.md).

## Runs

A row per run, added by the script; the owner fills in the checklist and issues and commits the row in
a `docs:` pull request. The device is its model, never its name or UDID (the repository is public,
[AGENTS.md](../../AGENTS.md) rule 4). A commit recorded as `<sha>-dirty` was tested with changes it does
not hold: a changed tracked file, or an untracked file the build reads (under `App/`, `Packages/` or
`Config/`, or a test plan).

| Date | Commit | Xcode | Device | iOS | Plan and flags | Passed / failed / flaky | Result bundle | CI `ios` | Manual checklist | Issues |
|---|---|---|---|---|---|---|---|---|---|---|
| 2026-10-27 | aeba441 | 27.0 (27A266a) | iPhone 17 Pro Max | 27.0.1 | Device | 120 / 0 / 0 | `.build/device-tests/20261027-062152-aeba441/Device.xcresult` | success | 6, 8 and 9 done by ManualChecklistDeviceUITests; 1–5, 7 and 10 pending | none new; 24 tests quarantined: contrast on iOS 27 glass bar buttons (white text measured at 8.8:1 and 11.7:1 on screen) and 3 findings without an element (#76), 3 contrast checks measured on screen (#294) |
