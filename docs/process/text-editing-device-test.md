# Text editing device test

The check that editing existing text gets on a real iPhone before the `textEditing` release flag is
turned on in a Release build ([ADR-0025](../adr/0025-native-text-editing-for-the-safe-subset.md)).
CI proves the editor on synthetic documents on the simulator. This checks what only a device and
real documents show: fonts from other apps, how the editor feels, how long an edit takes, and
whether other apps read the result. It adds to the [device smoke test](device-smoke-test.md) and
the [VoiceOver script](voiceover-script.md); how the editor works is in the
[text editing architecture](../pdf-text-editing-architecture.md).

Owner: Quality and PDF engine · Reviewed: whenever the editor's supported cases change, and before the release flag is removed

## Before you start

- Install the Staging build from TestFlight. Text editing is on in Staging and needs no purchase.
- Use documents you made for the test, never a customer's or a real personal one
  ([AGENTS.md](../../AGENTS.md), rule 6). Make each from the app named, with a few lines of text.
- Have Adobe Acrobat Reader, Files (Quick Look) and one other reader installed, to open what you
  export.
- Note the build, device and iOS version in the sign-off table. Record every refusal: which
  document, which text, and what the editor said.

## The five scenarios

| # | Do this | It passes when |
|---|---|---|
| 1 | Open an invoice. Tap Edit, tap "John Smith", type "David Smith", tap Done | Three taps before typing; under 10 seconds from Edit to saved; the name looks like the text around it; the exported file shows "David Smith" in Adobe Acrobat Reader, and searching it for "John" finds nothing |
| 2 | Open a résumé. Change "2024 Data Analyst" to "2025 Senior Data Scientist" | With room on the line, the new title fits and looks like its neighbours. Without room, the editor says it is too long and that nothing changed, and what you typed is still in the field |
| 3 | Open a contract. Fix a typo in the middle of a paragraph | The line keeps both edges; bookmarks open the same pages; More › Info shows the same title and author |
| 4 | Open lecture notes. Highlight a line, add a note, fix a typo on the highlighted line, share | The highlight is still on its line and the note is still there, in this app and in the exported file; Undo steps back through all three in order |
| 5 | Open a scan. Tap Edit | The reader says "This PDF contains images rather than editable text." and offers Recognise text; no text is outlined |

## No dead ends

The pass mark for every document in this plan: **after typing and tapping Done, the words are
changed, or they are covered and the app says so. Never "nothing was changed" with a Done button
that does nothing.**

| # | Do this | It passes when |
|---|---|---|
| N1 | A letter or statement from a reporting tool (a bank, a lender, a utility), set in a typeface the iPhone does not have. Change a name | "The font will be matched as closely as possible." shows before typing; Done changes the words; the new words sit on the same line as their neighbours and look close to them |
| N2 | On any document where Done ends with "Your text covers the old text…" | The message stays until OK or Undo; Undo removes the cover; the next line on that page says "Your text will cover this text" before typing |
| N3 | A line with the words "first", "office" or "file" in a book-style typeface. Change another word on that line | The words change in the page (not "your text covers"), and the editor shows ordinary letters |
| N4 | A letter or form laid out in boxes or a table (a medical or bank letter). Tap Edit | Every line has its own outline; no outline is bigger than a line |
| N5 | Zoom in, then pick the lowest line on the last page and type | What is typed can be seen the whole time: over the line, or in the bar above the keyboard |
| N5a | Pick a line that runs right across the page (a footer or a long sentence), on an iPhone SE-sized and a Pro Max-sized phone | The page does not zoom: every line of the page stays on screen. The field sits exactly on the line, in the page's own size, with the caret after the last letter. Typing past the line wraps down, no wider than the page's text; nothing is cut off at the screen's edge (the defect of 2026-10-08) |
| N5b | With that line open, pinch and scroll the page; turn the phone on its side and back; hide the keyboard and tap the field again | The page moves under the finger and the field moves with its line. The field is never under the keyboard: the page scrolls up to keep it above Cancel and Done. The text is unchanged |
| N5c | Pick the last line on the last page | The page scrolls up far enough that the field is above the keyboard; after Done or Cancel the page settles back |
| N5e | Open a line, then scroll the page well away from it with one finger, slowly and with a flick; pinch in, then out | The page goes where the finger takes it and stays there; it is never pulled back to the line. The field stays on its line and grows and shrinks with the page |
| N5f | With the line scrolled out of sight, type a letter | The page scrolls back so the caret is in view above the keyboard; on a zoomed page it scrolls across too |
| N5i | With a line open, scroll the page slowly so the line goes up under the bar at the top, first part of the way, then all the way. Tap the part of the field still showing. With the line out of sight, type a letter | The field goes under the bar as the page's own text does: none of it shows over the bar, the clock or the battery. While part of it shows, a tap there puts the caret there. The keyboard stays up the whole time, and typing brings the line back below the bar |
| N5g | With a line open, tap the keyboard button in the bar; look over the page; tap it again (or tap the field) and type; tap Done, then open the same line again | The keyboard goes and comes back with the line still open and nothing lost; the line reads what was typed |
| N5h | Open a line and tap Cancel without touching the page; then open one, scroll the page yourself, and tap Done | The first time the page goes back to where it was before the line was opened; the second time it stays where you scrolled it |
| N5d | Read the size of the edited text on screen, then pinch to zoom in | The field matches the page text; zooming in makes both bigger together. Text turned on its side is typed in the bar, which shows Cancel and Done in landscape with up to four lines |
| N6 | Pick five lines in a row on a document in a typeface the iPhone lacks | "The font will be matched…" shows for the first only |
| N7 | After any refusal, Settings › Report a problem | A line "Text editing proof: …" names the check, and "Text editing session: made, covered, refused" counts what happened. Send that, never the document |

## Moving text

In text editing, on a page with some empty space.

| # | Do this | It passes when |
|---|---|---|
| M1 | Press and hold a line, then drag it to an empty part of the page and let go | A picture of the line lifts and follows the finger; on letting go the line is there and gone from where it was; nothing else on the page moved; no keyboard appears |
| M2 | Undo | The line is back where it was |
| M3 | Hold a line and drop it on top of other text | Nothing moves; the reader says there isn't room for it there |
| M4 | Scroll the page with a quick drag that starts on a line | The page scrolls as usual; nothing lifts |
| M5 | Move a line, close the document, open it in another app | The line is at the new place there too |

## Staying dependable

Each of these is done on one document of several pages, without closing the app in between. A row
passes when the lines are outlined and one tap on a line opens its editor.

| # | Do this, then tap Edit and tap a line | Why |
|---|---|---|
| D1 | Open the document, go back to the library, open it again | The defect of 2026-10-05: Edit was on, nothing was outlined, taps did nothing |
| D2 | Scroll to the last page and back to the first | PDFKit puts page overlays away and brings them back |
| D3 | Scroll to the second page and edit there | Not only the first page |
| D4 | Edit a line, tap Done, then edit another line, then the first line again | An edit replaces the page; the new page must be editable |
| D5 | Leave Edit with Done, then tap Edit again | |
| D6 | In Edit, go to the Home Screen, wait a minute, come back | |
| D7 | Pinch to zoom in and out, rotate the phone and back | Outlines stay on their lines |
| D8 | On a form, tap a form field while in Edit | The line under the finger is picked; no form keyboard stays up |
| D9 | On a very large or complex page, tap Edit | Within a few seconds the reader shows outlines or says what it found; it never sits silent |

If any row fails: Settings › Report a problem, and send the summary. It now has lines that begin
"Text editing". They are counts only. Never send the document.

## Every kind of document

For each document: open, edit one line, close the reader, open it again, share the file, and open
the shared copy in Adobe Acrobat Reader. A row passes when the edit is there every time, looks
right, and nothing else on the page moved.

| Document | Made with | Also check |
|---|---|---|
| Generated PDF | Print to PDF on a Mac | The typeface stays the same |
| Word export | Microsoft Word | Whether the editor says the font was matched; whether the match is acceptable |
| Pages export | Pages | The typeface stays the same |
| Google Docs export | Google Docs | Whether the editor says the font was matched |
| Browser PDF | Safari and Chrome, a web page saved as PDF | Text in narrow columns: too-long replacements are refused, not squeezed |
| Invoice | Any | An amount in a right-aligned column keeps its right edge |
| Résumé | Any | Bold headings stay bold |
| Contract | Any, with bookmarks | Bookmarks and links still work |
| Academic paper | LaTeX | Body text edits; formulas are refused or covered, never damaged |
| Scanned PDF | The app's scanner, before and after Recognise text | Scenario 5, both times |
| Encrypted PDF | Add a password in the app | It still asks for the password after the edit, in this app and in Acrobat |
| Signed PDF | A digitally signed test document | The reader asks first; the edit goes into a copy; the original still validates |
| Unusual fonts | A document set in a decorative or brand typeface | The edit is refused, covered or matched, and the editor says which |
| Rotated pages | Rotate a page in the app, then edit it | The outline sits on the text; the edit lands in place |
| Large PDF | 500 pages or more | Entering Edit and picking text feel the same as in a short document; note how long Done takes |

## How it feels

- Hand the phone to someone who has not seen the app and ask them to change a word in a PDF.
  They find Edit without help.
- The first time a document with text is open, a tip under the bar says "Edit this PDF". After
  Edit is used, or the tip is closed, it does not come back: not on the next document and not
  after the app is closed and opened again.
- The tip does not show on a scan, on a signed or restricted document, or over a sheet.
- In dark mode the word on the Edit button is as easy to read as in light mode.
- The outlines appear without the page jumping, and follow the page while it scrolls and zooms.
- The field sits over the text it edits. The keyboard does not cover it.
- After Done, the page is where it was, at the same zoom.
- With VoiceOver on, each piece of text is read once, and a double tap edits it
  ([VoiceOver script](voiceover-script.md)).
- At the largest text size, the bar's buttons and messages are fully readable.
- In French, every message is in French.

## Against other apps

Run scenario 1 on the same invoice in Adobe Acrobat, PDF Expert, UPDF, Foxit PDF Editor and Xodo,
and record what you see. The aim is to be simpler, faster and more trustworthy, not to match
features. No result is assumed here; the table is filled in from the device.

| App | Taps before typing | Seconds from open to saved | Did the result look right | Did it say what it did |
|---|---|---|---|---|
| PDF Algo Pro | | | | |
| Adobe Acrobat | | | | |
| PDF Expert | | | | |
| UPDF | | | | |
| Foxit PDF Editor | | | | |
| Xodo | | | | |

## Sign-off

| Date | Build | Device | iOS | Scenarios passed | Documents passed | Refusals recorded | Issues filed |
|---|---|---|---|---|---|---|---|
