import CoreGraphics
import Foundation

/// The library: documents as files plus a rebuildable index (ADR-0005, ADR-0006).
public protocol DocumentLibrary: Sendable {
  /// Documents in a section, in the given order.
  func documents(in section: LibrarySection, sortedBy sort: LibrarySort) async throws -> [Document]
  /// One document, or `nil` when it does not exist.
  func document(withID id: DocumentID) async throws -> Document?
  /// Every tag in use, sorted.
  func allTags() async throws -> [String]
  /// The file URL of a document, for reading and coordinated writing.
  func fileURL(for id: DocumentID) async throws -> URL
  /// Copies a PDF into the library, reading it with coordinated, security-scoped access.
  func importDocument(from url: URL) async throws -> Document
  /// Adds PDF data (for example a new scan) as a document.
  func addDocument(data: Data, title: String) async throws -> Document
  /// Records what inspection learnt about a document's file.
  func updateInspection(_ inspection: PDFInspection, for id: DocumentID) async throws
  /// Renames a document; the title is trimmed and must not be empty.
  func rename(_ id: DocumentID, to title: String) async throws -> Document
  /// Marks or unmarks a favourite.
  func setFavorite(_ isFavorite: Bool, for id: DocumentID) async throws
  /// Replaces a document's tags.
  func setTags(_ tags: [String], for id: DocumentID) async throws
  /// Records that a document was opened and the page it showed.
  func recordOpened(_ id: DocumentID, pageIndex: Int) async throws
  /// Records that the file's contents changed (after a save).
  func recordModified(_ id: DocumentID) async throws
  /// Moves a document to Recently Deleted, where it stays for 30 days.
  func moveToRecentlyDeleted(_ id: DocumentID) async throws
  /// Restores a document from Recently Deleted.
  func restore(_ id: DocumentID) async throws
  /// Deletes a document's file and index entry permanently.
  func deletePermanently(_ id: DocumentID) async throws
  /// Permanently deletes documents that have been in Recently Deleted for 30 days or more.
  func purgeExpired(now: Date) async throws -> [DocumentID]
}

/// Errors from the library.
public enum LibraryError: Error, Equatable, Sendable {
  /// No document has this identifier.
  case notFound
  /// The file is not a PDF.
  case notAPDF
  /// A title was empty after trimming.
  case emptyTitle
  /// The file could not be read or written; the library is unchanged.
  case fileAccessFailed
}

/// What reading a PDF file revealed.
public struct PDFInspection: Hashable, Sendable {
  /// The number of pages (zero when locked).
  public let pageCount: Int
  /// Whether a password is needed.
  public let isEncrypted: Bool
  /// The text of each page; empty for locked documents.
  public let pages: [PageText]

  /// Creates an inspection result.
  public init(pageCount: Int, isEncrypted: Bool, pages: [PageText]) {
    self.pageCount = pageCount
    self.isEncrypted = isEncrypted
    self.pages = pages
  }

  /// Whether any page has selectable text.
  public var hasTextLayer: Bool {
    pages.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
  }
}

/// Reads PDF files without showing them.
public protocol PDFInspecting: Sendable {
  /// Inspects the PDF at a URL.
  ///
  /// - Throws: `LibraryError.notAPDF` when the file cannot be read as a PDF.
  func inspect(_ url: URL) async throws -> PDFInspection
}

/// A search result: a document and, when the match was in its text, the page and a snippet.
public struct SearchHit: Hashable, Sendable, Identifiable {
  /// The matching document.
  public let documentID: DocumentID
  /// The zero-based page of the first text match, or `nil` for a title or tag match.
  public let pageIndex: Int?
  /// Text around the match, for display.
  public let snippet: String?

  /// Creates a search hit.
  public init(documentID: DocumentID, pageIndex: Int?, snippet: String?) {
    self.documentID = documentID
    self.pageIndex = pageIndex
    self.snippet = snippet
  }

  /// The hit's identity in lists.
  public var id: DocumentID { documentID }
}

/// The on-device search index over titles, tags and text, including recognised text (FR-LIB-003).
public protocol DocumentIndexing: Sendable {
  /// Adds or replaces a document in the index (and in Spotlight, FR-LIB-005).
  func index(_ document: Document, pages: [PageText]) async throws
  /// Removes a document and its derived text (FR-LIB-006).
  func remove(_ id: DocumentID) async throws
  /// The stored page texts of a document, for intelligence and reading aloud.
  func pages(of id: DocumentID) async throws -> [PageText]
  /// Documents matching a query, best first.
  func search(_ query: String, in documents: [Document]) async throws -> [SearchHit]
}

/// A line of recognised text; `bounds` are normalised (0...1) with a lower-left origin.
public struct RecognizedLine: Hashable, Sendable {
  /// The recognised text.
  public let text: String
  /// The line's box, normalised to the image with the origin at the lower left.
  public let bounds: CGRect
  /// Recognition confidence from 0 to 1.
  public let confidence: Double

  /// Creates a recognised line.
  public init(text: String, bounds: CGRect, confidence: Double) {
    self.text = text
    self.bounds = bounds
    self.confidence = confidence
  }
}

/// On-device text recognition (ADR-0008).
public protocol TextRecognizing: Sendable {
  /// Recognises the lines of text in an image.
  func recognizeText(in image: CGImage) async throws -> [RecognizedLine]
}

/// Records privacy-safe product events on the device (ADR-0012, ADR-0017).
public protocol TelemetryRecording: Sendable {
  /// Records an event by its `domain.object.action` name; unknown names are dropped.
  func record(_ event: String) async
}
