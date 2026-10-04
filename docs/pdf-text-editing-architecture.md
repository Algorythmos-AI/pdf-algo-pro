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
a 400-page document (`TextEditingControllerTests.longDocument`). The save that follows is the
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
| `ReaderTextEditingTests` | The reader model and views: access, commit, cancel, undo, refusals, scanned pages, signed copies, search text |
| `TextEditingAccessTests`, `ReleaseFlagTests` | The flag, the entitlement and their composition, including a Release build |

Edited documents are also exported to the independent readers in CI (qpdf and PDFium), with the
text they must contain. What only a device shows is in the
[device test plan](process/text-editing-device-test.md).

## Known limits

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

## Migration risk

- The save path gains one check and one state reset; an unedited document saves exactly as before.
- `PDFDocumentController` gains an initialiser parameter with a default, so existing callers are
  unchanged.
- Nothing is stored in a new format: an edited document is an ordinary PDF, and the previous
  version is kept by the existing version history (FR-EDIT-008).
- The feature is behind a release flag that is off in Release builds.
