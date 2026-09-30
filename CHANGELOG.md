# Changelog

All notable changes to PDF Algo Pro are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the app follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html) through `MARKETING_VERSION`. Entries are
written for people reading release notes; the build pipeline turns them into TestFlight and App
Store notes (see the changelog strategy).

## [Unreleased]

### Added
- Organise pages: in Pages, choose Select to rotate pages, move one earlier or later, delete pages,
  or copy them into a new document. Each change can be undone.
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
- The assistant shows only the latest answer, and every sentence of an answer is checked against
  the page it cites; unsupported parts are left out (#60).
- Deleting permanently asks first; onboarding marks the options coming in a later update; hiding
  AI also hides it on library cards (#57).
- The library index is now backed up with the device; the search index and Spotlight forget
  documents that are removed (#61).
- On iPad the app uses a single window for now (#54).

### Fixed
- Form entries are saved, and protected documents keep their password and restrictions when saved
  (#58).
- Changes are saved when the app moves to the background (#58).
- Settings survive app updates, and onboarding no longer reappears (#55).
- Opening a PDF from the library's folder in Files opens it instead of adding a copy (#61).
- Saving a PDF whose metadata is damaged in a certain way no longer closes the app (#67).
- A cited page, or a page chosen in Contents or Pages, stays on screen after the sheet closes
  (#63, #71).
