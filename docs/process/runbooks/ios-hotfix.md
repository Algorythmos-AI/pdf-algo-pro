# iOS hotfix

The procedure for fixing a production problem out of band: branch from `main`, ship the smallest safe
fix through external TestFlight and an expedited App Review, tag it, and bring the fix back onto
`integration`. It assumes an incident is already open; the branch mechanics are summarised in
[branching](../branching.md#hotfix-flow).

Owner: Release · Reviewed: after each hotfix

## When to use

- A SEV1 or SEV2 incident ([incident response](incident-response.md)) needs a code change in the App
  Store build and cannot wait for the next release train.
- Not for new features, refactors or anything that can ride the next release pull request.
- If the [kill switch](kill-switch.md) can turn the faulty behaviour off, flip it first; the hotfix then
  removes the cause without time pressure.

## Before you start

- The incident issue (or private security advisory) exists and names the Incident lead.
- The problem is reproduced on the version users have, built from `main` at its release tag.
- If a phased release of the faulty version is in progress, it is paused (see step 1).
- You know the current production version `X.Y.Z`; the hotfix will be `X.Y.(Z+1)`.

## Steps

1. **Contain.** Pause the phased release if one is running
   ([Release a version update in phases](https://developer.apple.com/help/app-store-connect/update-your-app/release-a-version-update-in-phases))
   and flip any relevant kill switch.
2. **Branch from `main`:**

   ```sh
   git fetch origin
   git switch -c hotfix/<short-description> origin/main
   ```

3. **Fix minimally.** Change only what the fix needs, add a regression test that fails without the fix,
   and keep every gate green. Set `MARKETING_VERSION` to `X.Y.(Z+1)` in `project.yml` and add a
   `## [X.Y.(Z+1)] - YYYY-MM-DD` section to `CHANGELOG.md` with a `### Fixed` entry.
4. **Open the pull request into `main`** with a conventional title, for example
   `fix(pdf): crash when opening encrypted files`. `promotion-guard` accepts the `hotfix/` prefix. Link
   the incident. Squash-merge once every required check passes; no check is skipped for urgency
   ([quality gates](../quality-gates.md#never-disable-or-skip-a-gate)).
5. **Verify the build.** The merge starts the Xcode Cloud Release workflow. Install the build from
   external TestFlight on a real device and confirm the fix and the main flows (open, read, annotate,
   scan, save).
6. **Submit with an expedited review.** Create version `X.Y.(Z+1)` in App Store Connect, write What's
   New in EN and FR, submit it, then request an expedited review, including the steps to reproduce the
   bug on the current version as Apple asks
   ([App Review](https://developer.apple.com/distribute/app-review/)).
7. **Tag.** On approval, confirm that `main`'s head is the built commit and run
   `gh workflow run release.yml --ref main -f version=X.Y.(Z+1)`.
8. **Release.** Phased release is the default. For a SEV1 fix the Release hat may choose **Release to
   All Users**, which Apple allows at any time
   ([Release a version update in phases](https://developer.apple.com/help/app-store-connect/update-your-app/release-a-version-update-in-phases)).
9. **Back-merge into `integration`:**

   ```sh
   git fetch origin
   git switch -c chore/back-merge-1.2.1 origin/main     # use the hotfix version
   git merge origin/integration                         # resolve conflicts here, if any
   git push -u origin chore/back-merge-1.2.1
   gh pr create --base integration --title "chore: back-merge 1.2.1 into integration" --fill
   ```

   Squash-merge it. The CHANGELOG on `integration` must end with an empty `[Unreleased]` above the new
   hotfix section.

## Verify

- The App Store version is `X.Y.(Z+1)`, and the signal that opened the incident (crash signature,
  support reports, diagnostics) is falling.
- `gh release view vX.Y.(Z+1)` shows the tag on the hotfix commit.
- `integration` contains the fix (the back-merge pull request is merged) and its Staging build passes.
- Any kill switch flipped in step 1 is either restored or has an issue explaining why it stays off.

## Roll back

- A bad hotfix is not reverted on devices; there is no binary rollback. Pause its phased release, use
  the kill switch, and ship another hotfix.
- If the fix is wrong before approval, remove the version from review and start again from step 3.
- Release tags cannot be moved or deleted (tag ruleset); the next patch version supersedes a bad one.

## Record

- The incident issue gets the timeline, the pull request, the version and the release time.
- A postmortem follows for SEV1 and SEV2 ([incident response](incident-response.md#postmortem)).
- `docs/working-memory.md` records the new production version.
