# ADR-0008: On-device scanning and structured OCR

**Status:** accepted (2026-09-28)

**Context.** Scanning and searchable text are core tasks. Cloud OCR costs money per page, fails offline and sends documents away.

**Decision.** Scan with the VisionKit document camera. Recognise text on device with Vision's `RecognizeDocumentsRequest` (paragraphs, tables, lists). Write an invisible text layer into scanned PDFs and index the text. English and French first. OCR runs in a bounded actor queue that respects thermal state and Low Power Mode.

**Alternatives considered.** Cloud OCR services. Tesseract or other bundled engines.

**Consequences.** Private, free per page and offline. Accuracy and language coverage follow Apple's releases and are tracked by the OCR accuracy suite.

**Pillars served.** PIL-3, PIL-5, PIL-6

**References.** [RecognizeDocumentsRequest](https://developer.apple.com/documentation/vision/recognizedocumentsrequest) · [VNDocumentCameraViewController](https://developer.apple.com/documentation/visionkit/vndocumentcameraviewcontroller)

**Addendum, 2026-10-08 (PAP-053).** As built, recognition uses Vision's `RecognizeTextRequest`, not yet `RecognizeDocumentsRequest`. Behind `ReleaseFlag.widerRecognition` it recognises the Latin- and Cyrillic-script languages Vision supports with automatic language detection, and the text layer is placed word by word. Moving to `RecognizeDocumentsRequest` for paragraphs, tables and lists remains the decision; the current recogniser stays as its fallback.

**Addendum, 2026-10-08 (PAP-055).** Behind `ReleaseFlag.documentRecognition`, recognition now uses `RecognizeDocumentsRequest` and takes its lines in paragraph order, with `RecognizeTextRequest` as the fallback. Tables reach the text layer row by row; passing them to extraction as tables is still to do.
