# ADR-0007: Commercial PDF SDK behind our own boundary

**Status:** proposed (2026-09-28)

**Context.** Editing existing PDF text, true redaction and on-device Office conversion are core to the category, and PDFKit supports none of them. Building a content-stream editor is years of work.

**Decision.** Use a commercial PDF SDK from day one, unless the phased-licence alternative is chosen after the spike (PAP-026). The SDK lives only inside the `PDFEngine` package, behind our own protocols. Choose between Nutrient (formerly PSPDFKit) and Apryse with a time-boxed spike scored on: true text editing; on-device PDF to Word, Excel and PowerPoint; true redaction; signatures and forms; iPhone, iPad, Mac and visionOS support; SwiftUI integration; binary size; privacy manifest and **no telemetry**; offline licence validation; licence cost and terms; exit plan. PDFKit remains for thumbnails and as a contingency for read-only protocols. Redaction must remove content, verified by tests. **Status stays Proposed until the spike, licence and telemetry audit close readiness blocker C1.**

**Alternatives considered.** PDFKit only (no editing, no Office export). PDFium or MuPDF (large C++ integration; MuPDF is AGPL without a commercial licence). Building our own engine. A phased licence: the MVP features (reading, annotation, forms, signing, scanning) are within PDFKit's reach, so if the vendor quote makes early break-even impossible, the MVP can run on PDFKit behind the same `PDFEngine` protocols and the SDK can be licensed when V1 editing, redaction and conversion ship; the spike records whether this is viable.

**Consequences.** Licence cost, binary size and a critical dependency, accepted for launch-grade editing and conversion. The boundary keeps a vendor switch possible. A third-party SDK needs a NOTICE entry and a privacy-manifest review.

**Pillars served.** PIL-1, PIL-2, PIL-3

**References.** [Nutrient iOS SDK](https://www.nutrient.io/sdk/ios/) · [Apryse iOS SDK guides](https://docs.apryse.com/ios/guides)
