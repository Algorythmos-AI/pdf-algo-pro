# Changelog

All notable changes to PDF Algo Pro are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the app follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html) through `MARKETING_VERSION`. Entries are
written for people reading release notes; the build pipeline turns them into TestFlight and App
Store notes (see the changelog strategy).

## [Unreleased]

### Changed
- A new look: red on white. Buttons, tiles and the app icon are now red, and screens stay white
  (or dark in Dark Mode). On a document, what you select is outlined in blue, so that red there
  only ever means a red annotation or Delete.

### Added
- Reading (internal builds): a strip of small pages along the bottom of a document. Tap a small
  page to go to it; the strip steps aside while you edit or mark up, and Layout › Page strip
  puts it away.
- Reading (internal builds): pinching out now stops at the whole page instead of leaving a small
  page adrift.
- Reading (internal builds): with a keyboard, the left and right arrows turn the page, and
  Command with plus, minus and zero zooms in, out and back to the whole page.
- A short introduction the first time you open the app: three pages on what it does, with Skip on
  every one.
- PDF Algo Pro now has a Pro subscription. The app stays free to use, with a daily limit on new
  scans and on summaries and answers; Pro removes it. Settings › Subscription shows your plan and lets you see the plans, manage
  or restore a subscription, and redeem a code. Opening, reading, signing, sharing and exporting
  your documents never need Pro. Pro comes as a yearly plan with a free trial, marked Best Value
  with how much it saves you, or as a weekly plan.
- Editing text (internal builds): move a line of a PDF's own text. Tap Edit, press and hold a line,
  and drag it to where you want it. The line moves in the page itself and can be undone; it is not
  moved on top of other content.
- Settings › About is now a page of its own: the app's version, the privacy policy, terms and
  support, a way to share PDF Algo Pro, and who makes it.
- The app opens on a new Home: scan or import in one tap, pick up the documents you opened last,
  and see how many documents each section holds. Home also says what the app promises, that your
  documents stay on this device, and who makes it.
- Settings › About links to the privacy policy, the terms of use and the support page on
  algorythmos.com, in French when the app is in French. They open in the browser.
- Edit the text already in a PDF (internal builds for now): tap Edit, tap a line, type, tap Done.
  The words change in the page itself, in the same font where the iPhone has it, and the change is
  still there when the file is opened in another app. Each edit can be undone, and the version
  before it is kept. When something can't be changed safely, the app says so and changes nothing.
  Scanned pages say they are images and offer Recognise text; signed documents are edited in a copy.
- App Lock: Settings › Privacy can require Face ID, Touch ID, Optic ID or the passcode to open the app.
  While it is on, the app switcher shows no document and document text stays out of Spotlight.
- Tapping a web, email or phone link in a document now shows its full address and asks before
  opening it. Links to files, other apps or scripts are never opened; their address can be copied.
- More › Annotations lists every highlight, note, drawing, shape and signature by page; choosing one
  opens its page, and the list can be shared as text.
- Extracted fields can be shared as a CSV file that opens correctly in Excel and Numbers: accents are
  kept, and where numbers use a decimal comma (as in French) the columns are separated by semicolons.
- Siri and Shortcuts can summarise a document: "Summarise … with PDF Algo Pro" returns the summary with
  the pages it cites, made on this device, and needs the iPhone unlocked.
- The app may ask for a rating, at most once per version: only after several things went well over at
  least two days, never in the first session or after something went wrong, and only once a document
  or sheet has been closed.
- PDF from photos: hold Import in the library and choose photos; each becomes a page, upright, in a
  new document. No access to your photo library is needed.
- Tools in the reader's More menu: reduce file size into a smaller copy (for email or for printing),
  add or remove a password, share a flattened copy that nobody can change, and share the page on
  screen as an image.
- Organise pages: in Pages, choose Select to rotate pages, move one earlier or later, delete pages,
  or copy them into a new document. Each change can be undone.
- Version history: before each save the app keeps the version it replaces for 30 days, and More ›
  Version history restores any of them; the version being replaced is kept too, so a restore can be
  undone. Settings › Storage shows the space it takes and can delete it.
- Privacy report in Settings: how many AI requests ran on this iPhone or in the cloud over the last
  30 days, and how many documents were sent to cloud AI (none). Only the counts are kept.
- Select several documents in the library to share, favourite, merge into one PDF, or delete them
  together, with Undo.
- Annotations, shapes, drawings, text boxes and signatures can be moved by dragging, resized by
  pinching or from Style, and given another colour; each change is one undo step. VoiceOver users
  can move a selection with its Move actions.
- Stamps in Markup: today's date, a tick, a cross, or your own text such as initials or "Paid".
- Bookmarks: bookmark the page on screen from More; bookmarks are listed in Contents and saved in the
  PDF, so other apps show them too.
- Review a scan before it is saved: rotate, reorder or delete pages, and name it; the name is
  suggested from the first page's headline, recognised on this device.
- Recognising text you start carries on if you leave the app, with its progress shown by the system
  (on the Lock Screen and in the Dynamic Island); you can cancel it from there.
- A digitally signed PDF keeps its valid signature: your changes are saved in a copy marked
  "(edited)", and the app says so.
- If another app changes a document while it is open, the reader shows the new version; if you have
  unsaved changes, you choose to keep yours as a copy or use the other version, so nothing is lost.
- Follow-up questions in the assistant: ask about the answer you just got, and the earlier questions
  and answers stay on screen with their sources. Answers still come only from the document.
- Document info, from a document's menu in the library: file name, size, pages, dates, author, the
  app that made it, PDF version, and whether a password protects it or printing and copying are allowed.
- The native iOS foundation app: onboarding with AI-first options, a library in the Files-visible
  Documents folder with Recently Deleted, search across titles, tags and recognised text (and
  Spotlight), a PDFKit reader with markup, notes, read aloud and on-device text recognition, scanning
  to searchable PDFs, and on-device document intelligence that cites its pages and says when an answer
  is not in the document.
- Repository foundation: licence, agent rules, templates, workflows, rulesets as code, labels,
  milestones, and the process documentation for branching, releases and quality gates.
- Markup: draw with a finger or Apple Pencil; add rectangles, ovals, arrows and text boxes; tap any
  annotation to edit its text or delete it (#66).
- Signatures: draw one and keep it in the Keychain on this device only, or type your name, then
  place it on the page (#59, #66).
- Every save keeps the version from before it, and "Restore the version before the last save" in the
  reader's More menu puts it back (restoring again switches back). A document that won't open offers
  the same. Saving stops with a clear message when the device is too full to save safely.
- Find in the document, go to a page by number, and share or print from the reader (#58).
- A tag editor for documents, and onboarding choices that open the assistant on a chosen PDF (#57).
- A setting to keep what documents say out of Spotlight; titles and tags stay searchable (#61).
- Summaries of crashes and hangs that iOS reports, kept on this device and included in Report a
  problem only when you send it (#61).
- An interim app icon, and a Staging build named "PDF Algo β" for internal testing (#52, #54).

### Changed
- Report a problem now includes the diagnostics summary unless you turn it off in Settings › Help,
  and remembers your choice. The summary never includes your documents, and you can read it in the
  email, and delete it, before you send.
- Drawing: Undo and Redo are in the bar while you draw or mark text, so a line or shape that went
  wrong is taken back with one tap. With a shape tool in hand, dragging a shape that is already on
  the page moves it; dragging on the bare page draws a new one.
- Settings is easier to scan: every row has a symbol, and privacy and security are in one place
  (the privacy report moved there from its own section).
- Report a problem now writes to pdfalgopro@algorythmos.com.
- Editing text (internal builds) is easier to find: the reader's bar has a filled button that says
  Edit, and the first time a document with text is open a short tip points to it. The tip goes
  away for good once Edit is used or the tip is closed. On narrower iPhones the bar no longer shows
  the document's title.
- Scan offers "Choose from Photos" as well as "Choose from Files", since photos of pages are usually
  in the photo library.
- Highlight, Underline and Strike through are tools you pick up: choose one, then select text and it
  is marked, until you tap Done. Choosing one with nothing selected no longer shows an error.
- The reader's More menu is grouped, with the export and password tools under "Export and protect",
  so it fits on the screen.
- Settings opens on what people look for: the ten "What you do most" switches moved to their own
  screen.
- A new app icon: a larger page with a bold "PDF" mark on a crimson-to-violet field. The Staging
  build carries the same icon with a beta badge.
- Search looks through the whole library from any section, so a document is found wherever it is
  filed; in Recently Deleted it searches only deleted documents.
- The start-here card in the library goes once you have opened one of your own documents, instead of
  staying until the third and still saying "Open your first PDF".
- The app icon is layered, so iOS 26 draws it with Liquid Glass in the default, dark, tinted and clear
  appearances.
- Read aloud goes on from page to page to the end of the document, turning the pages as it reads,
  and carries on from the page on screen when you start it again.
- After a wrong password, the password field clears, so the next attempt starts fresh.
- The assistant shows only the latest answer, and every sentence of an answer is checked against
  the page it cites; unsupported parts are left out (#60).
- Deleting permanently asks first; onboarding marks the options coming in a later update; hiding
  AI also hides it on library cards (#57).
- The library index is now backed up with the device; the search index and Spotlight forget
  documents that are removed (#61).
- On iPad the app uses a single window for now (#54).

### Fixed
- Editing text (internal builds): on a long line in small print, the end of the sentence could not
  be reached while typing, because the typing field ran off the side of the screen. The field now
  stays on screen and scrolls along the line as you move through it.
- Editing text (internal builds): on a line wider than the typing field, only the part around the
  caret could be reached, and the rest could not be brought into view. The field can now be swiped
  sideways to either end of the line, and a tap puts the caret where you tap.
- Editing text (internal builds): a line containing "fi" or "fl" drawn as a single joined letter
  could only be covered, not changed. Such lines are now changed like any other, and the editor
  shows ordinary letters.
- Editing text (internal builds), from testers' feedback: every line now gets its own outline, where
  some pages showed one large box around a whole block; a line low on the page is no longer typed
  into unseen under the keyboard; and explanations about fonts and covering are given once, not at
  every line.
- Editing text (internal builds): documents set in a typeface the iPhone does not have, such as
  letters and statements from reporting tools, were refused with "This text can't be changed" on
  every line. Their text can now be changed, in the closest matching font.
- Editing text never ends in a dead end: when the words can't be changed in the page, your text
  is placed over the old text and the app says so, with Undo. Where that is known beforehand, the
  editor says it before you type.
- Editing text (internal builds): after a document was opened a second time, Edit turned on but no
  line was outlined and taps did nothing. Lines are now outlined and one tap opens a line every
  time, including after scrolling away and back, after an edit, and after the app was in the
  background.
- Editing text never sits silent: the reader says when it is still looking for text, when a page
  has nothing that can be edited, and when the work took too long, in which case nothing is changed.
- The app no longer closes when text recognition is started on a scanned document ("Make
  searchable"). Recognition now carries on with its progress shown by the system if you leave the app.
- A stamp or a signature is selected as soon as it is placed, so it can be dragged straight to where
  it belongs. A selected stamp is now called a stamp, not a text box.
- Highlight, Underline and Strike through now work by dragging a finger across the words: the mark
  follows the finger and is made when it lifts. Going over words that are already marked no longer
  darkens them, and marks that touch on a line join into one.
- A highlight keeps the same soft colour after the document is saved and opened again.
- With a markup tool in hand, a sideways drag on a page no longer swipes back to the library.
- A document can be opened again straight after going back from it, and the list then shows what
  changed in it.
- A new text box appears in the middle of the screen with a white background, already selected so it
  can be dragged into place. The selected annotation now has a frame around it, and tapping then
  dragging it at once moves it instead of bringing up the Copy menu.
- In Recently deleted, touching and holding a document offers Restore and Delete now; before, only
  a swipe did.
- The back button on the document list opens the sections (All documents, Recents, Favourites,
  Recently deleted). It did nothing on iPhone: the list bounced straight back.
- The library list follows what you did in the reader as soon as you come back: a new password's
  lock, page counts and thumbnails.
- Drawing shows a hint, like the other markup tools.
- Document and page thumbnails have an edge and a soft shadow, so a white page no longer disappears
  into a white list.
- Stamps and text boxes use a standard PDF typeface, a framed stamp is opaque, and a new stamp no
  longer lands on top of the last one.
- The assistant keeps your question on screen while it works, and Try again asks it again.
- Add a text box and Add note put the text on the page: the prompt cleared its text before it was
  used, so nothing was added.
- After a password is added or removed, the library shows the lock straight away.
- A selected signature is called "Signature", not "Drawing".
- The app builds with the iOS 27 SDK, which adds its own type called `Document`.
- A library index that can't be opened, for example after installing an older build, is set aside
  instead of deleted, so tags, favourites and Recently Deleted dates can be recovered.
- Copying extracted fields as CSV makes any value a spreadsheet would run as a formula (for example
  one starting with "=") show as plain text, so a document can't plant a formula in your sheet.
- Form entries are saved, and protected documents keep their password and restrictions when saved
  (#58).
- Changes are saved when the app moves to the background (#58).
- Settings survive app updates, and onboarding no longer reappears (#55).
- Opening a PDF from the library's folder in Files opens it instead of adding a copy (#61).
- Saving a PDF whose metadata is damaged in a certain way no longer closes the app (#67).
- A cited page, or a page chosen in Contents or Pages, stays on screen after the sheet closes
  (#63, #71).
