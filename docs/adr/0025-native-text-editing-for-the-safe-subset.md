# ADR-0025: Native text editing for the documents where it is safe, behind our own boundary

**Status:** proposed (2026-10-04)

**Context.** Editing existing text (FR-EDIT-001) is a Must for V1 and the main paid capability ([PRD](../prd.md)). [ADR-0007](0007-pdf-sdk-boundary-and-vendor-selection.md), still proposed, assigns it to a commercial SDK and calls an in-house editor "years of work"; readiness blocker C1 (the vendor spike, licence and telemetry audit) is open, so no SDK can be added yet ([readiness review](../readiness-review.md)). The owner asked for the strongest editing the platform's own frameworks allow now, with a boundary that lets a fuller engine replace it later, and without labelling an overlay as editing.

A spike on macOS 26.6 and the iOS 26.5 simulator (2026-10-04, recorded in the [text editing architecture](../pdf-text-editing-architecture.md)) found:
- PDFKit cannot change a page's content ([`PDFPage`](https://developer.apple.com/documentation/pdfkit/pdfpage) has no API for it).
- Every PDFKit save draws the document again through Core Graphics: text stays text, and each font becomes a subset holding only the letters used. A document font therefore cannot spell new words after one save.
- A page can be replaced in an open document while annotations, form fields, bookmarks, links and encryption survive.

**Decision.**
- **Build a narrow native editor now.** It erases the old text from a page's content and draws the new text with Core Text, on one page at a time, and proves each result before it reaches the document. It edits only what it can prove; everything else is refused. This is a bounded piece of work, not a general PDF engine: it reads only files that Core Graphics wrote, never writes fonts or encodings itself, and has no layout engine.
- **Keep our own boundary.** The `PDFTextEditing` protocol in `PDFEngine` takes and returns a one-page PDF and plain values. `ContentStreamTextEditor` implements it. A commercial SDK, if ADR-0007 is accepted, becomes a second implementation without changes to the reader.
- **Never call covering text editing.** Covering is a separate, explicit operation with its own outcome, offered only for text the editor refuses.
- **ADR-0007 stays proposed** for what this does not do: reflow across lines, right-to-left and shaped scripts, images and links, true redaction (FR-EDIT-005) and Office conversion. Blocker C1 still governs any SDK.

**Alternatives considered.**
- **Wait for the SDK.** Leaves the main paid capability unbuilt behind a blocker with no date, and gives no evidence of how far the platform alone goes.
- **Edit the file's bytes directly and reload.** The next ordinary save would redraw the file through Core Graphics anyway, and undo would need a second mechanism beside the one annotations and pages use.
- **Encode new text with the document's own font.** Fails after the first save, because the font is then a subset.
- **Cover and replace as the feature.** Leaves the original text in the file. It fails the FR-EDIT-001 acceptance criterion and has the weakness the threat model records for fake redaction (T-06).
- **An open-source engine (PDFium, MuPDF).** A large C++ integration, and MuPDF is AGPL without a commercial licence (ADR-0007).

**Consequences.**
- No third-party code, no network use, and no change to the privacy label.
- A new parser for untrusted input, with size, depth and count limits and fuzz tests; it is added to the [threat model](../threat-model.md) under T-01 and T-03.
- Fewer documents can be edited than with an SDK: text is edited a line at a time, and a typeface that is neither on the device nor complete in the document is replaced by the closest standard font. These limits are stated in the architecture document and in the device test plan.
- The proof refuses edits on unusual pages by design. Refusals are measured in the [device test plan](../process/text-editing-device-test.md); their rate is the main evidence for or against licensing an SDK.
- The feature is behind the `textEditing` release flag, off in Release builds until the device test plan is signed off, and behind the Pro entitlement through an injected access value ([ADR-0011](0011-storekit-2-monetisation.md)).
- This record is proposed, not accepted: it reverses part of PAP-003, which only the owner can do.

**Pillars served.** PIL-2, PIL-5, PIL-7

**References.** [Text editing architecture](../pdf-text-editing-architecture.md) · [ADR-0007](0007-pdf-sdk-boundary-and-vendor-selection.md) · [PRD](../prd.md) · [PDFPage](https://developer.apple.com/documentation/pdfkit/pdfpage) · [PDF 32000-1:2008, 9.4 Text objects](https://opensource.adobe.com/dc-acrobat-sdk-docs/pdfstandards/PDF32000_2008.pdf)
