# Release flags

Which features a build shows, how that is decided, and how the App Store build is checked before it
ships. The flags themselves are one typed list in
[`ReleaseFlags.swift`](../../Packages/Core/Sources/Core/ReleaseFlags.swift); this page records what
each is set to and why.

Owner: Release · Reviewed: in every release pull request, and whenever a flag is added or removed

## How a flag is resolved

A feature behind a flag shows when the build is internal (Debug or Staging, which compile in
`INTERNAL_TOOLS`) or when the flag's `compiledDefault` is on. The App Store build is the Release
configuration, so `compiledDefault` alone decides what it shows. Nothing arrives remotely: remote
configuration can only switch a feature off ([kill switch](runbooks/kill-switch.md)).

Every flag has a `removeBy` version. A unit test fails once the app's version reaches it, so a flag
that has shipped is removed within one milestone instead of lingering.

## Flags for 1.0

As decided in PAP-066 ([decision register](../decision-register.md)).

| Flag | Feature | 1.0 | Why |
|---|---|---|---|
| `readingControls` | The page strip, zoom limits and keyboard commands in the reader (FR-READ-002) | On | On in every Staging build since it landed; checked in the owner's runs of builds 25 to 27 |
| `widerRecognition` | Recognition in more languages, found automatically, with a text layer placed word by word (FR-SCAN-002) | On | The accuracy gate scores it with the plain recogniser (`OCRAccuracyTests`, PAP-056) |
| `documentRecognition` | A scanned page read as a document, in reading order (FR-SCAN-004) | On | Scored by the same accuracy gate (PAP-056) |
| `baseFormMatching` | Finding a word in another of its forms, in library search and in the pages chosen for a question (FR-LIB-004) | On | Held to the same retrieval performance budget |
| `documentDragging` | Dragging a document out of the library into another app (ADR-0022) | On | Checked on the simulator only (PAP-057); covered by the device run before the release |
| `textEditing` | Editing the existing text of a PDF, as a Pro feature (FR-EDIT-001, ADR-0025) | Off until its device test is signed off | The one flag that gates a paid feature, and the only one whose [device test](text-editing-device-test.md) still has rows unsigned |

Turning `textEditing` on for 1.0 is its own pull request, made once the full
[text editing device test](text-editing-device-test.md) is signed off on a Staging build made with
Xcode 27. If it is not signed off in time, text editing moves to 1.1, and the offer's list of what Pro
adds, the onboarding intents and the screenshot set change to match (FR-ONB-007).

## The App Store build is checked as it ships

Testers use Staging, where every flag is on and Pro can be granted without a purchase. The App
Store build differs: text editing is off (or locked behind Pro once it ships), and purchases are
real. So before each App Store submission the Release build itself, from external TestFlight, gets
the full [device smoke test](device-smoke-test.md) on a phone: the store rows with a sandbox
account, every flagged feature above, and text editing's off or locked state. The release checklist
in [release management](../release-management.md#the-release-pull-request) has the line.
