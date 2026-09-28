# App Store submission

The step-by-step procedure for taking a planned release from `integration` through the release pull
request, external TestFlight and App Review to a phased App Store release, then tagging it. It is the
operational companion to [release management](../../release-management.md), which explains the
policy behind each step. For an urgent production fix use the [iOS hotfix runbook](ios-hotfix.md)
instead.

Owner: Release · Reviewed: after each release

## When to use

- A milestone's scope is complete on `integration` and the Release hat has decided to ship it as
  version `X.Y.Z`.
- Not for hotfixes, and not before the first App Store listing exists (the first submission also
  needs the readiness items for Apple prerequisites and live privacy and support URLs to be closed).

## Before you start

- Every pull request for the release is merged into `integration`, and its checks are green.
- No open `priority:p0` or `priority:p1` issue remains in the milestone, or each one is explicitly
  deferred in the release pull request.
- The Staging build of the current `integration` head is on TestFlight internal and has been used on a
  real iPhone (and iPad, when the release touches iPad).
- The open question on keeping `integration` level with `main` is resolved
  ([branching](../branching.md#keeping-integration-level-with-main)).
- You can sign in to App Store Connect with a role that can submit for review, and you have admin
  rights on the repository for the release workflow.

## Steps

1. **Prepare the version on `integration`.** Branch `chore/release-X.Y.Z` from `integration`. Set
   `MARKETING_VERSION` to `X.Y.Z` in `project.yml`. In `CHANGELOG.md`, move the `[Unreleased]` entries
   into a new `## [X.Y.Z] - YYYY-MM-DD` section (the date the release pull request is opened) and leave
   an empty `[Unreleased]`. Draft What's New in EN and FR and update the wiki release notes page
   ([changelog strategy](../../changelog-strategy.md)). Open the pull request titled
   `release: prepare X.Y.Z` and squash-merge it when green.
2. **Collect the pre-merge evidence** on the Staging build of that commit: performance budgets, golden
   PDF corpus, OCR accuracy, AI evaluation results and a manual VoiceOver pass
   ([quality gates](../quality-gates.md#release-only-gates)). Attach results or links to the release pull
   request.
3. **Open the release pull request** from `integration` into `main`, titled `release: X.Y.Z`, with the
   checklist from [release management](../../release-management.md#the-release-pull-request).
4. **Merge with a merge commit** once every required check, including `promotion-guard`, is green and
   the checklist's pre-merge part is ticked. Do not delete the head branch.
5. **Confirm the Release build.** The merge starts the Xcode Cloud Release workflow (a clean build).
   Check that the build's commit is the merge commit on `main` and note its build number.
6. **Distribute to external TestFlight.** Add the build to the external groups with What to Test notes.
   The first build in a group goes to Beta App Review; later builds may not need a full review
   ([TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview)).
7. **Soak.** Keep the build in external testing for at least 3 days and watch crash reports, TestFlight
   feedback and support email. The stability gate is at least 99.8% crash-free sessions (an assumed
   starting threshold; see [quality gates](../quality-gates.md#release-only-gates)).
8. **Prepare the App Store version** in App Store Connect
   ([Create a new version](https://developer.apple.com/help/app-store-connect/update-your-app/create-a-new-version)):
   select the build; paste What's New in EN and FR (each up to 4000 characters,
   [Platform version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information));
   update screenshots if the UI changed; review the App Privacy answers
   ([Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy))
   and the privacy policy and support URLs; choose **manual release** and turn on **phased release**.
9. **Write App Review notes.** Explain how to reach each changed feature without an account, and, for
   any cloud AI tier, where the consent screen names the provider and the data sent, as App Review
   Guideline 5.1.2(i) requires ([App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/#5.1.2)).
   State that the document-analysis features are not legal advice where they appear.
10. **Submit for review**
    ([Submit for review](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-for-review)).
    Apple reports that most submissions are reviewed within 24 hours
    ([App Review](https://developer.apple.com/distribute/app-review/)); plan for longer.
11. **When approved, tag before releasing.** Check that `main`'s head is still the commit that was
    built, then run the release workflow:

    ```sh
    git fetch origin && git rev-parse origin/main   # must equal the built commit
    gh workflow run release.yml --ref main -f version=X.Y.Z
    gh run watch
    ```

    The workflow tags `main`'s head at dispatch time, so dispatch it before anything else merges into
    `main`.
12. **Release.** In App Store Connect, release the version; phased release starts at 1% of users with
    automatic updates on day 1 and reaches 100% on day 7
    ([Release a version update in phases](https://developer.apple.com/help/app-store-connect/update-your-app/release-a-version-update-in-phases)).
13. **Watch daily** during the phased release: crash reports, MetricKit diagnostics once implemented,
    support email, ratings and reviews. Pause at once on any data-loss or privacy report and open an
    incident ([incident response](incident-response.md)).
14. **Bring `integration` level with `main`** using the agreed mechanism
    ([branching](../branching.md#keeping-integration-level-with-main)).

## Verify

- `gh release view vX.Y.Z` shows the release with the CHANGELOG section as its notes, and the tag
  points at the built commit.
- The wiki shows the mirror of `docs/` at that commit, or the workflow printed the `WIKI_TOKEN`
  warning and the wiki is published by hand later.
- App Store Connect shows the version as Ready for Distribution, then in phased release.
- The App Store build installed on a device reports version `X.Y.Z` and the expected build number.

## Roll back

iOS has no binary rollback: users who installed a version keep it. The levers are:

1. **Before release:** remove the version from review, or do not release an approved build (manual
   release was chosen in step 8), and fix forward.
2. **During phased release:** pause it; Apple allows pauses totalling up to 30 days, and anyone can
   still update manually from the App Store
   ([Release a version update in phases](https://developer.apple.com/help/app-store-connect/update-your-app/release-a-version-update-in-phases)).
3. **Turn the faulty feature off** with the [kill switch](kill-switch.md) (designed, to be implemented).
4. **Ship a fix** through the [hotfix runbook](ios-hotfix.md) and request an expedited review for a
   critical bug ([App Review](https://developer.apple.com/distribute/app-review/)).
5. **Last resort: remove the app from sale.** It disappears from the App Store within 24 hours, while
   existing users keep it and still receive updates
   ([Manage availability](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-for-your-app-on-the-app-store)).

Release tags are immutable (the tag ruleset blocks updates and deletion); a wrong release is corrected
with the next patch version, never by moving a tag.

## Record

- The release pull request holds the checklist, the evidence and the merge.
- The GitHub Release and the `vX.Y.Z` tag are created by the workflow.
- Update [`docs/working-memory.md`](../../working-memory.md) with the shipped version and anything deferred.
- Any exception to a gate is recorded in the decision register ([`docs/decision-register.md`](../../decision-register.md)) with the
  hat that approved it.
