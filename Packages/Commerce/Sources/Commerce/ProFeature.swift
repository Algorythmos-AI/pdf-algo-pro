/// A capability that creates a Pro result, as the packaging table in `docs/pricing-strategy.md` lists them.
///
/// Reading, markup, forms, signing, scanning with OCR, passwords, organising pages and the on-device
/// intelligence allowance are free (FR-STORE-001) and have no case here.
public enum ProFeature: String, Sendable, CaseIterable {
  /// Editing a document's text, images and links.
  case textEditing
  /// Redacting content so that it is removed from the file.
  case redaction
  /// Converting a document to Word, Excel or PowerPoint.
  case conversion
  /// Intelligence on Private Cloud Compute for long documents (opt-in).
  case privateCloudComputeAI
  /// Invoice and receipt templates that extract fields to CSV.
  case extractionTemplates
  /// The Claude intelligence tier (opt-in).
  case claudeAI
}

/// Something the user does with a document they already have, which no entitlement ever gates.
///
/// Losing Pro never locks the user out of their documents or annotations (FR-STORE-004). The list is
/// explicit so that a call site names the operation and the gate's answer for it is tested for every
/// entitlement.
public enum DocumentOperation: String, Sendable, CaseIterable {
  /// Opening a document from the library or from another app.
  case open
  /// Reading and navigating a document.
  case read
  /// Adding, changing and removing annotations.
  case annotate
  /// Filling form fields.
  case fill
  /// Signing a document.
  case sign
  /// Saving changes, including to a document that holds results made while Pro was active.
  case save
  /// Sharing a document with another app or person.
  case share
  /// Exporting a document or a copy of it.
  case export
  /// Printing a document.
  case print
  /// Removing a document's password.
  case removePassword
  /// Deleting a document.
  case delete
  /// Restoring an earlier version of a document.
  case restoreVersion
}
