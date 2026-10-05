# PDF text editing architecture

How PDF Algo Pro changes the text that is already in a PDF (FR-EDIT-001 in the [PRD](prd.md)):
what the platform allows, how the editor is built, what it can and cannot edit, how an edit is
proven before it reaches a file, and where a commercial PDF SDK would plug in later. The decision
behind it is [ADR-0025](adr/0025-native-text-editing-for-the-safe-subset.md).

Owner: Architecture and PDF engine · Reviewed: each milestone, and whenever the editor's supported cases change

## What "editing" means here

Editing existing text means the page's own content changes: after a save, the text extracted from
the file holds the new words and not the old ones, in this app and in any other reader. That is the
acceptance criterion of FR-EDIT-001 ([PRD](prd.md), editing requirements).

Covering text with a rectangle and placing an annotation on top is not editing. The original words
stay in the file and remain searchable and copyable. The app offers that only as a separate,
labelled fallback (see [Covering text](#covering-text-that-cannot-be-edited)), and the engine
records which of the two happened for every change.

## What the platform allows

These findings come from a spike run on macOS 26.6 and on the iOS 26.5 simulator on 2026-10-04,
kept as tests in `Packages/PDFEngine/Tests/PDFEngineTests`.

| Question | Finding |
|---|---|
| Can PDFKit change a page's content? | No. [`PDFPage`](https://developer.apple.com/documentation/pdfkit/pdfpage) exposes a page's text, annotations and boxes, and nothing that sets its content |
| Can the content be read? | Yes, as bytes. Core Graphics reads streams, and this editor parses a file that PDFKit wrote |
| Does a save keep the original bytes? | No. PDFKit writes with Core Graphics, which draws every page again: operators are rewritten, the page box moves to the origin, and every font becomes a subset holding only the letters used on the page. This happens on every save the app already makes |
| Is the page turned into an image? | No. Text stays text, fonts stay embedded fonts |
| Can a page be replaced in an open document? | Yes. A page from another document can take a page's place; annotations and form fields can be moved onto it once it is in the document, and the page view keeps its zoom and position in the continuous layout |
| Do form fields survive? | Yes, when the new page is inserted before the fields are moved. Moved first, they lose their names |
| Does encryption survive? | Yes. A page copied from an unlocked document is unencrypted in memory, and the save encrypts the document again |

Two consequences shape the design:

- **A document font cannot be used to write new words.** After one save it holds only the letters
  that were already on the page. New text is therefore drawn with Core Text, in the same typeface
  from the device when the device has it.
- **The editor only ever reads files that Core Graphics wrote.** The page being edited is first
  copied by PDFKit into a one-page document. That gives one dialect to parse (a classic
  cross-reference table, no object streams, Flate or plain streams), whatever produced the original.

## How an edit works

1. **Snapshot.** `PDFDocumentController` copies the page, without its annotations, into a one-page
   PDF held in memory only (`snapshot(of:)`).
2. **Read.** `PageAnalysis` parses the snapshot: file structure (`PDFFile`), content operators
   (`ContentStream`), fonts (`TextFont`), and the text runs with their geometry and drawing state
   (`TextInterpreter`). `TextRegionBuilder` groups runs into regions.
3. **Erase.** `TextEraser` removes the region's text-showing operators. Where a later operator
   continues from the pen position, the advance is kept, so every other operator paints exactly
   where it did. The new content is appended as an incremental update.
4. **Redraw.** `TextRedrawer` draws the erased page and then the new text with Core Text, at the
   original position, size, colour, slant and stretch. Core Graphics writes ordinary text operators
   and embeds the font.
5. **Prove.** `EditProof` checks the result (next section). A failure refuses the edit.
6. **Swap.** The controller confirms nothing changed while the work was done, then puts the new
   page where the old one was (`swap(_:for:keeping:links:)`), moves annotations and form fields
   across as the same objects, and repoints bookmarks and links.
7. **Save.** The ordinary save runs: atomic, previous version kept, encryption preserved, signed
   documents saved as a copy. It also checks that each edited page reads in the staged file as it
   does on screen.

Undo calls the same swap with the pages the other way round, so a text edit undoes in order with
annotations and page changes.

Only the page being edited is read. Finding text and making an edit cost the same in a one-page and
a 120-page document (`TextEditingControllerTests.longDocument`; 500 pages in the performance plan). The save that follows is the
app's existing full rewrite and grows with the document, as it does for an annotation.

## The proof

Every edit must pass all of these before the page is swapped. The same checks are the test oracle.

| Check | What it catches |
|---|---|
| The result parses with this engine, Core Graphics and PDFKit | A damaged page |
| The new text reads as typed, where it was put; every other region has the same text in the same place | Changed or moved neighbours, a missing edit |
| PDFKit, reading independently, finds the new text | A mistake in this engine's own reading |
| Rendered pixels outside the edited boxes are unchanged | Anything else on the page changing |
| The space the new text occupies was clear once the old text was erased | New text printing over a rule, a border or other text |
| The new text leaves ink on the page | Text that reads correctly and cannot be seen |
| Each edited page reads in the staged file as it does on screen | PDFKit dropping the edit when it writes |

Tolerances are constants in `EditProof`. `Assumption:` they separate real differences from
rendering noise; they are validated by the invariant tests over every fixture and tuned from the
[device test plan](process/text-editing-device-test.md).

`EditProofTests` builds deliberately wrong results (text missing, a neighbour erased, text printed
over its neighbour, invisible text, text in the wrong place) and requires each to be refused.

## What can be edited

A region is one run of text on one line in one font. A paragraph is several regions; there is no
reflow across lines.

| Class | Cases | What happens |
|---|---|---|
| Direct | The typeface is on the device, or the embedded font has every letter needed | Edited in the page's content, same typeface |
| Limited | The typeface is not on the device and the embedded subset lacks a letter | Edited in the page's content, in the closest standard font |
| Covered only | Transparency, patterns, outline or clipping text modes, layers, a clip the engine does not track, right-to-left or shaped scripts, text something else is drawn over, text the engine cannot read (Type 3 fonts, CJK fonts without their own character map, text inside reusable page objects) | Not edited. Can be covered and replaced when the person asks |
| Image | No text operators, or only invisible recognised text | "This PDF contains images rather than editable text." with the existing Recognise text action |
| Protected | The author does not allow changes | Refused with an explanation |
| Signed | A signature or a certification | Edited in a copy, after confirmation |

**Fit.** Shorter text always fits. Longer text grows into free space on its line, up to the nearest
other content or the margin. A justified line whose words change little is set to the same width.
Text that still does not fit may narrow to no less than 90%, and beyond that the edit is declined.
`Assumption:` the 90% floor and the 3% justification tolerance are not noticeable in body text;
both are validated in the device test plan.

**Alignment.** A region that shares a right edge with others keeps its right edge (amounts in a
column); one that shares a centre keeps its centre; otherwise the start stays put.

**Fallback font.** Deterministic, from the original's traits: fixed-pitch text to Courier, serif
text to Times New Roman, anything else to Helvetica, in the same weight and slant
(`FontMatcher.fallback`).

**Page boxes.** PDFKit moves a page's box to the origin when it copies it. Regions are reported in
the live page's space, and annotations are shifted with the page when it is swapped.

## Covering text that cannot be edited

For "covered only" text the reader can place a filled rectangle and a text box over it. This is
`coverSelectedText(with:)`, not `replaceSelectedText(with:)`, and its outcome is
`.visualReplacement`. The editor says before Done that the original stays in the file underneath.
It is two ordinary annotations, so they can be selected and deleted like any other, and one undo
removes both. It is never used for text that can be edited directly. Removing text for good is
redaction (FR-EDIT-005), which this does not do.

## Untrusted input

PDFs are untrusted. The parser:

- limits nesting depth, operator count, decoded stream size, cross-reference updates and character
  map entries (`TextEditingLimits`);
- checks every length and offset it reads, and bounds every index;
- inflates through a stream that stops at the size limit;
- runs no JavaScript, follows no external reference, and writes no file.

Anything over a limit, malformed or unrecognised makes the page "not editable"; it is never a
crash. `TextEditingHostileInputTests` runs the golden corpus's malformed files and seeded fuzzing
of page content and fonts through the editor. The threat is recorded in the
[threat model](threat-model.md).

## State and concurrency

- One edit is made at a time; a second is refused as stale.
- The proof runs off the main thread. Before the swap the controller checks that the page is still
  in the document and that no page was added, removed or moved meanwhile; otherwise the edit is
  dropped untouched.
- Nothing is written until Done. Text being typed when the app is suspended or closed is lost; the
  document is intact.
- Text is edited in the scrolling layout. PDFKit provides page overlays only there, so a reader in
  the single-page layout switches while text editing is on and switches back afterwards.
- **One way to pick text.** The page view's own tap recognizer picks
  (`PDFReaderHostView.pickText(at:)`). It sees every tap on every page, so picking does not depend
  on PDFKit having given a page an overlay. The overlay (`TextRegionOverlayView`) draws the
  outlines and shields the page's form fields and links from the touch; it never picks.
- **Outlines that cannot go stale.** The provider keeps every overlay PDFKit holds, weakly, and
  never forgets one that PDFKit stops showing: PDFKit shows the same view again later. An overlay
  is refreshed when it is made, when PDFKit is about to show it, when it joins a window, and when
  the visible pages or the zoom change.
- **The page view follows its controller.** A reader that is shown again loads its document again
  and makes a new controller. `PDFReaderView.updateUIView` hands that controller to the view on
  screen, and `PDFReaderHostView.configure(for:)` rebinds: document, observers, mode. The old
  controller lets go of the view. Before this, opening a document a second time left Edit turned
  on with nothing outlined and every tap ignored (the defect found on a phone on 2026-10-05).
- **Time limits.** Finding a page's text and making an edit each race a limit in
  `PDFDocumentController` (`Assumption:` 5 seconds and 15 seconds; checked in the device test
  plan). Past it the reader is told (`PageTextKind.tookTooLong`, `TextEditRefusal.timedOut`) and
  says so. Swift cannot stop running work, so the work is cancelled, which the native parser
  checks for every 512 operators, and an answer that arrives late is discarded: the page swap is
  only on the path that answered in time. The limit sits around the editor, not in it, so it holds
  for any `PDFTextEditing`.
- **Never silent.** While text editing is on and nothing is picked, the reader says one of: tap
  any text; looking for text (after 0.4 seconds); this page is an image; this page cannot be
  edited; no text on this page can be edited; this is taking too long.
- Text editing and drawing are exclusive. While text is picked, taps on the page, Undo and Redo
  wait.
- The search text is brought up to date once, on leaving text editing or closing the reader.
- Which links point at which page is found once per document, a few pages at a time, because
  walking 500 pages takes most of a second.

## The boundary, and where an SDK plugs in

`PDFTextEditing` is the boundary:

```swift
public protocol PDFTextEditing: Sendable {
  func text(ofPage page: Data) async -> EditablePageText
  func applying(_ edits: [TextEdit], toPage page: Data) async -> TextEditResult
}
```

A page crosses it as a one-page PDF, so no PDFKit or vendor type appears. `ContentStreamTextEditor`
is the native implementation. A commercial SDK ([ADR-0007](adr/0007-pdf-sdk-boundary-and-vendor-selection.md))
would be a second implementation, passed to `PDFDocumentController(url:textEditor:)`; the reader
would not change. An SDK would mainly add reflow across lines, right-to-left and shaped scripts,
editing inside reusable page objects, and fonts that are neither on the device nor complete in the
document.

**Extension points kept for later work, not built now:**

- **A writing assistant** reads `EditableTextRegion` values and proposes `TextEdit` values through
  `applyTextEdits(_:onPage:)`, which makes them one undo step and runs the same proof. It never
  touches the file.
- **Editing recognised text on scans** is a different engine behind the same protocol: it would
  return regions for a page of kind `image`.

## Access

Whether text editing is offered is one value, `TextEditingAccess` (`available`, `locked`, `hidden`),
that the reader asks for each time editing starts. The app composes it in `AppTextEditingAccess`
from two things: the `textEditing` release flag (`ReleaseFlag`, off in a Release build) and the Pro
entitlement (`FeatureGate`, [ADR-0011](adr/0011-storekit-2-monetisation.md)). The reader and the
engine import neither Commerce nor StoreKit.

Internal builds (Debug and Staging) turn the flag on and grant access, because there is nothing to
buy in them yet. The onboarding option "Edit PDF text" stays off (`OnboardingIntent.isOffered`)
until the flag is removed, so it can never show while the feature is hidden (FR-ONB-007).

## Testing

| Suite | Covers |
|---|---|
| `TextEditingSyntaxTests` | Lexer, content parser, file structure, character maps, glyph names, erasing with a kept advance |
| `TextEditorTests` | Detection, the five scenarios, alignment, justification, rotation, page rotation, offset boxes, colour, characters, fallback font, batches, stale edits, unsupported drawing |
| `EditProofTests` | The proof refuses each kind of wrong result |
| `TextEditingHostileInputTests` | Malformed and fuzzed input, limits |
| `TextEditingControllerTests` | Save and reopen, undo and redo interleaved with annotations and page changes, forms, outline, metadata, links, encryption, permissions, signatures, covering, save faults, long documents |
| `TextEditingDependabilityTests` | Time limits and discarded late answers, cancellation, picking with no page view, the page view following a new controller, outlines after PDFKit puts them away, repeated edit-save-reopen, the diagnostics record |
| `ReaderTextEditingTests` | The reader model and views: access, commit, cancel, undo, refusals, scanned pages, signed copies, search text, a reloaded document, the "looking", "nothing to edit" and "too long" messages, the diagnostics summary's vocabulary |
| `TextEditingDiagnosticsTests` | The summary lines; reasons reduced to letters |
| `TextEditingUITests` | Journeys on the simulator: edit, undo, cancel; single-page layout; locked and hidden; a document opened a second time; a second line after an edit, after leaving Edit, and after the app was away |
| `TextEditingAccessTests`, `ReleaseFlagTests` | The flag, the entitlement and their composition, including a Release build |

Edited documents are also exported to the independent readers in CI (qpdf and PDFium), with the
text they must contain. What only a device shows is in the
[device test plan](process/text-editing-device-test.md).

## Diagnostics

`TextEditingDiagnostics` (Core) is what the controller records each time it looks for a page's text,
takes a tap, or makes an edit. It goes into Settings › Report a problem
([operations](operations.md)), which the person reads before sending. It holds counts only:

| Recorded | Never recorded |
|---|---|
| Kind of page (text, image, unreadable, timed out) | Any word of the document |
| How many regions are direct, matched-font, or cover-only, and the engine's fixed name for each cover-only reason | Font names, file names, page numbers, positions |
| Milliseconds to find the text and to make the last edit | The text typed |
| Whether the page view is bound to the document, and how many pages show outlines | |
| Taps while editing, and how many picked text; how the last edit ended | |

Reasons are reduced to at most 24 ASCII letters before they are written, so a field filled wrongly
cannot carry a document's words. `ReaderTextEditingTests.diagnostics` asserts every word of the
summary is one the app chose. The record is kept in memory only and replaced each time.

## Known limits

- **A time limit is not speed.** It turns a wait without end into a refusal that says so. The
  snapshot of the page, which PDFKit makes on the main thread, is outside the limit.
- **Form fields under a missing outline.** Where PDFKit has given a page no overlay, a tap that
  picks text may also reach a form field under it; the page view ends form entry before picking.
  There is no seeded form document for a UI journey of this yet.

- **Typefaces.** Fonts that do not ship with iOS (many Word documents use them) fall back to the
  closest standard font unless the page already holds every letter typed.
- **Lines, not paragraphs.** A long replacement on a full line is declined.
- **Paint order.** New text is painted last. Text that had something drawn over it is not edited.
- **Undo history.** Each text edit keeps the page it replaced. Past 64 MB of kept pages
  (`Assumption:` checked on the oldest supported iPhone in the device test plan) the history is
  shortened to its newest half.
- **Accessibility tags.** PDFKit does not carry a tagged PDF's structure through any save, with or
  without an edit.
- **File size.** Each edited page gains a font subset (about 9 kB in the spike's invoice); further
  edits to the same page add a few hundred bytes.

## Where the build differs from the approved plan

The plan was written before the spike. These are the places the code deliberately differs, so
nobody looks for something that is not there.

| Plan | Built | Why |
|---|---|---|
| New text encoded in the document's font and redrawn beside the original operators | New text drawn with Core Text onto the erased page | Every PDFKit save leaves fonts holding only the letters already used (spike) |
| The character map confirmed by a second source before a document font is used | Not needed | Core Text draws from the typed characters; no document character map is trusted for writing |
| Dirty flags split by kind, each checked against its own permission | One rule: editing needs permission both to change the document and to add to it | Core Graphics grants those two together, so they never arrive apart (`permissions` test) |
| The staged file's edited pages compared by text and by render | Compared by text | The render is already proven on the page before the swap; a second full render per save was not worth its cost |
| The overlay's regions as VoiceOver elements | PDFKit's own line elements; activating one picks the line | PDFKit does not expose an overlay's elements, and each line is then read once |
| The onboarding option following the flag | The option stays off until the flag is removed | Simpler, and it cannot show while the feature is hidden (FR-ONB-007) |
| The edit mode recorded as a telemetry event | Returned in the outcome only | The event catalogue is fixed by the analytics strategy; adding an event is its own decision |
| A sourced comparison with other apps | A table to fill in on a device | Claims about other apps need hands-on evidence |
| Reader snapshots | Render tests at a large text size and an audited UI journey | The editor's views are internal to the reader, and a snapshot of a live page view is not stable |
| Real-producer fixture files | Hand-built structures as browsers, TeX and Word write them; real files in the device test | No openly licensed producer output was available to commit |
| Speed measured at 10, 100 and 500 pages | 500 pages in the performance plan; a 120-page comparison in the unit tests | The work is per page by construction, so one large size shows it |

## Migration risk

- The save path gains one check and one state reset; an unedited document saves exactly as before.
- `PDFDocumentController` gains an initialiser parameter with a default, so existing callers are
  unchanged.
- Nothing is stored in a new format: an edited document is an ordinary PDF, and the previous
  version is kept by the existing version history (FR-EDIT-008).
- The feature is behind a release flag that is off in Release builds.
