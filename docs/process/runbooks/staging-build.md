# Staging build

The step-by-step procedure for cutting a Staging build from `integration` and getting it to testers
in TestFlight. It is the operational companion to the Staging section of
[environments](../environments.md), which explains what the Staging app is, and to the
[device smoke test](../device-smoke-test.md), which is what a person then does on a phone. For the
App Store use the [App Store submission runbook](app-store-submission.md) instead.

Owner: Release · Reviewed: after each Staging build that went differently from what is written here

## What starts a build, and what does not

- Merging into `integration` does not start a build. The Xcode Cloud workflow "Staging" has one
  start condition: by hand, on the branch `integration`.
- The maintainer starts it in App Store Connect or in Xcode. An agent may start it through the
  App Store Connect API when the maintainer has said so for that build (PAP-030, PAP-031).
- The workflow builds whatever the branch's newest commit is at that moment. A commit cannot be
  chosen. So nothing else merges while a build is being started.
- "Build 1" in the decision register is a milestone (issue #47). It is not Xcode Cloud's build
  number, which counts every run.

Account details, identifiers and tester names are not written in this repository
([AGENTS.md](../../../AGENTS.md), rule 4). They are in App Store Connect.

## Before the build

1. **Check the commit by hand.** Build the newest commit of `integration` and use it on the
   simulator, as the maintainer's standing rule asks. Two things only show on the configuration
   that ships:
   - Build the Staging configuration, not Debug. Launch arguments exist in Debug only, so a
     walk-through that leans on them is a walk-through of another app.
   - To see first run again as an update would show it, build once with one build number, finish
     first run, then build with another number and install it over the first.
2. **Drag slowly and hold.** A flick hides what a slow drag shows. A test or a hand that only
   flicks the page will pass while the page does not follow a finger (issue #188).
3. **Edit on a later page.** A document of one page hides anything that loses the reader's place.
4. **One simulator at a time.** Two booted simulators on a small Mac fill the disk with swap, and
   UI tests then time out for reasons that have nothing to do with the app.
5. **A defect on a screen the build changes stops the build.** It is fixed by pull request first.

## Tester notes

- The notes come from `TestFlight/WhatToTest.<locale>.txt` at the commit that is built. They must
  be merged before the build is started.
- A change to those files alone runs no iOS job in CI, so it is quick.
- There is one file for each locale testers use, and one for the app record's primary language.
  A locale with no file arrives empty, and its testers see no notes.
- The first block says what is new in this build, from `CHANGELOG.md` `[Unreleased]`. A "Known
  issues" block says what is known to be broken. No issue numbers or internal names
  ([changelog strategy](../../changelog-strategy.md)).
- CI holds the files to this: [`scripts/ci/check_tester_notes.py`](../../../scripts/ci/check_tester_notes.py),
  in the required `docs` check.

## Starting and checking the build

1. In the same minute, confirm: `integration`'s newest commit is the one that was checked; its CI
   run is green; no pull request into `integration` is open; no Xcode Cloud run is in progress.
2. Start the workflow on `integration`.
3. Read the run's source commit as soon as it is reported. If it is not the commit that was
   checked, say so, add the build to no group, and stop.
4. When the run has succeeded and the build is processed, check all of these before calling it
   ready:
   - the build number and version;
   - that the build is in the internal testers' group. The group's "all builds" setting has
     skipped builds before; the group's own list of builds is the check, and a missing build is
     added;
   - that the notes arrived for every locale and read the same as the files.

## External testers

- A build goes to the external group only on the maintainer's word for that build.
- It is added to the group and submitted to Beta App Review. Until that is approved, external
  testers cannot install it, whatever the group shows.

## Afterwards

- The maintainer runs the [device smoke test](../device-smoke-test.md) and, when text editing
  changed, the [text editing device test](../text-editing-device-test.md).
- What they report is written into those documents' sign-off tables as they said it. A run that
  covered part of a table is recorded as part.
