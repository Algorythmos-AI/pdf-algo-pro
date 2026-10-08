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
  /// The document whose file is at `url`, or `nil` when `url` is not in the library's folder.
  ///
  /// The Files app shows that folder, so a file opened from there is already in the library. A PDF put
  /// there since the library last looked is added in place, not copied.
  func document(at url: URL) async throws -> Document?
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
  /// Brings the index in line with the files: PDFs added outside the app (for example in the Files
  /// app) are added, entries whose file is gone are removed.
  func reconcileWithFiles() async throws -> Reconciliation
  /// Where a save keeps the version of a document from before it, or `nil` when this library keeps
  /// none (FR-EDIT-008, first step).
  func previousVersionURL(for id: DocumentID) async throws -> URL?
  /// Whether the version from before the last save is kept.
  func hasPreviousVersion(of id: DocumentID) async -> Bool
  /// Swaps a document's file with the version from before its last save, so restoring can itself be
  /// undone the same way.
  func restorePreviousVersion(of id: DocumentID) async throws
  /// The kept earlier versions of a document, newest first (FR-EDIT-008).
  func versions(of id: DocumentID) async -> [DocumentVersion]
  /// Puts an earlier version back; the current file becomes a kept version, so this can be undone.
  func restore(_ version: DocumentVersion, of id: DocumentID) async throws
  /// The space every kept version takes, in bytes.
  func versionsSize() async -> Int64
  /// Deletes every kept version of every document.
  func deleteAllVersions() async throws
}

/// An earlier version of a document, kept by a save (FR-EDIT-008).
public struct DocumentVersion: Hashable, Sendable, Identifiable {
  /// The version's identity within its document.
  public let id: String
  /// When the save that replaced it happened.
  public let savedAt: Date
  /// Its size in bytes.
  public let size: Int

  /// Creates a version.
  public init(id: String, savedAt: Date, size: Int) {
    self.id = id
    self.savedAt = savedAt
    self.size = size
  }
}

extension DocumentLibrary {
  /// A library that keeps no earlier versions.
  public func previousVersionURL(for id: DocumentID) async throws -> URL? { nil }
  /// A library that keeps no earlier versions.
  public func hasPreviousVersion(of id: DocumentID) async -> Bool { false }
  /// A library that keeps no earlier versions.
  public func restorePreviousVersion(of id: DocumentID) async throws { throw LibraryError.notFound }
  /// A library that keeps no earlier versions.
  public func versions(of id: DocumentID) async -> [DocumentVersion] { [] }
  /// A library that keeps no earlier versions.
  public func restore(_ version: DocumentVersion, of id: DocumentID) async throws { throw LibraryError.notFound }
  /// A library that keeps no earlier versions.
  public func versionsSize() async -> Int64 { 0 }
  /// A library that keeps no earlier versions.
  public func deleteAllVersions() async throws {}
}

/// What reconciling the library index with the files changed.
public struct Reconciliation: Equatable, Sendable {
  /// Documents found without an entry; they still need inspecting and indexing.
  public var added: [Document]
  /// Entries removed because their file is gone; their search text and Spotlight entry must go too
  /// (FR-LIB-006).
  public var removed: [DocumentID]

  /// Creates a result.
  public init(added: [Document] = [], removed: [DocumentID] = []) {
    self.added = added
    self.removed = removed
  }
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
  /// Removes the derived text and Spotlight entries of every document not in `ids`, for example
  /// after the library index was rebuilt with new identifiers. Returns the identifiers removed.
  func prune(keeping ids: Set<DocumentID>) async -> [DocumentID]
  /// The stored page texts of a document, for intelligence and reading aloud.
  func pages(of id: DocumentID) async throws -> [PageText]
  /// Documents matching a query, best first.
  func search(_ query: String, in documents: [Document]) async throws -> [SearchHit]
}

/// One word of a recognised line, with where it is.
public struct RecognizedWord: Hashable, Codable, Sendable {
  /// The word, with any punctuation attached to it.
  public let text: String
  /// The word's box, normalised to the image with the origin at the lower left.
  public let bounds: CGRect

  /// Creates a recognised word.
  public init(text: String, bounds: CGRect) {
    self.text = text
    self.bounds = bounds
  }
}

/// A line of recognised text; `bounds` are normalised (0...1) with a lower-left origin.
public struct RecognizedLine: Hashable, Codable, Sendable {
  /// The recognised text.
  public let text: String
  /// The line's box, normalised to the image with the origin at the lower left.
  public let bounds: CGRect
  /// Recognition confidence from 0 to 1.
  public let confidence: Double
  /// The line's words in order, each with its own box, when the recogniser found them.
  ///
  /// With them, the text layer of a scan places every word where it is, so one word can be
  /// selected. Without them (`nil`, as in lines kept by an earlier version) the line is one piece.
  public let words: [RecognizedWord]?

  /// Creates a recognised line.
  public init(text: String, bounds: CGRect, confidence: Double, words: [RecognizedWord]? = nil) {
    self.text = text
    self.bounds = bounds
    self.confidence = confidence
    self.words = words
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
