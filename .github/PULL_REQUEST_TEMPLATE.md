## What and why

<!-- One or two sentences: what this changes and the reason for it. Link the issue ("Closes #123"). -->

## How it was tested

<!-- Commands run, devices and OS versions, screenshots or recordings for UI changes, the CI jobs that cover it. -->

## Pillars and platforms

<!-- Which pillars this serves (PIL-1 … PIL-7) and which platforms it touches (iPhone, iPad, Mac, visionOS). -->

## Privacy

<!-- Needed only when this changes the privacy manifest, a permission's usage description, the network
     allow-list, a package dependency or networking code (CI checks). Replace the comment on the next
     line with "none, because …" or a link to the website pull request that updates the policy. -->

Privacy policy impact: <!-- none, because …, or a link -->

## Checklist

- [ ] One focused change; the branch targets `integration` (or `main` for a release/hotfix)
- [ ] Tests added or updated for changed behaviour
- [ ] No secrets, credentials, personal data or real documents in the diff
- [ ] Docs, CHANGELOG `[Unreleased]` and `docs/working-memory.md` updated if state or behaviour changed
- [ ] Accessibility checked for UI changes (VoiceOver, Dynamic Type, contrast)
- [ ] No new third-party dependency, or its ADR is linked
