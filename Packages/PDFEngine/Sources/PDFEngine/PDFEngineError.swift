import Foundation

/// Errors from the PDF engine, in the engine's terms.
public enum PDFEngineError: Error, Equatable, Sendable {
  /// The file is not a PDF the engine can read.
  case unreadable
  /// The document is locked and the password was missing or wrong.
  case passwordRequired
  /// Writing the document failed; the file on disk is unchanged.
  case saveFailed
  /// A page could not be rendered.
  case renderFailed
  /// The document's protection does not allow the change: its author restricted it, or writing it
  /// would remove the document's encryption.
  case restricted
}
