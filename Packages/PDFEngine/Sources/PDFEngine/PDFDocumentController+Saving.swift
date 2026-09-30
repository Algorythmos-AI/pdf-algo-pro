import Core
import Foundation
import PDFKit

extension PDFDocumentController {
  /// Writes the document atomically with coordinated access; a failed save leaves the file unchanged (NFR-REL-002).
  ///
  /// An encrypted document stays encrypted, with the same restrictions (see `protectionOptions()`).
  ///
  /// - Parameters:
  ///   - url: The document's file.
  ///   - previous: Where to keep the file as it was before this save (FR-EDIT-008, first step), replacing
  ///     any version kept there before; `nil` keeps none. On APFS the copy is a clone, so it takes no
  ///     space until the files differ.
  /// - Throws: `PDFEngineError.restricted` when the document's author does not allow the change;
  ///   `PDFEngineError.insufficientSpace` when the device is too full to save safely;
  ///   `PDFEngineError.saveFailed` when writing fails, or when the earlier version can't be kept.
  public func save(to url: URL, keepingPreviousAt previous: URL? = nil) throws {
    let interval = Signposts.begin("Document.Save")
    defer { interval.end() }
    let options = try protectionOptions()
    let staging = FileManager.default.temporaryDirectory.appendingPathComponent("save-\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: staging) }
    document.repairAttributesIfNeeded()
    // PDFKit keeps an encrypted document encrypted whatever the options, so a document whose password
    // is being (or was) removed is written as a fresh copy of its pages.
    let source = pendingProtection == .remove || (document.isEncrypted && !wasEncrypted) ? unencryptedCopy() : document
    guard source.write(to: staging, withOptions: options), let data = try? Data(contentsOf: staging),
      PDFDocument(data: data) != nil
    else { throw PDFEngineError.saveFailed }
    let available = try? url.deletingLastPathComponent()
      .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
      .volumeAvailableCapacityForImportantUsage
    guard Self.hasRoom(toWrite: data.count, available: available) else { throw PDFEngineError.insufficientSpace }
    var coordinationError: NSError?
    var writeError: (any Error)?
    NSFileCoordinator(filePresenter: nil).coordinate(
      writingItemAt: url, options: .forReplacing, error: &coordinationError
    ) {
      target in
      let fileManager = FileManager.default
      do {
        if let previous, fileManager.fileExists(atPath: target.path) {
          if fileManager.fileExists(atPath: previous.path) { try fileManager.removeItem(at: previous) }
          try fileManager.copyItem(at: target, to: previous)
        }
        try data.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      } catch {
        writeError = error
      }
    }
    guard coordinationError == nil, writeError == nil else { throw PDFEngineError.saveFailed }
    switch pendingProtection {
    case .set(let newPassword):
      wasEncrypted = true
      password = newPassword
    case .remove:
      wasEncrypted = false
      password = nil
    case nil:
      break
    }
    pendingProtection = nil
    hasUnsavedChanges = false
    recordFormValues()
  }

  // MARK: - Passwords (FR-EDIT-006)

  /// A document with copies of this one's pages (and their annotations), its metadata and its outline,
  /// but no encryption.
  func unencryptedCopy() -> PDFDocument {
    let copy = PDFDocument()
    var pages: [PDFPage: PDFPage] = [:]
    for index in 0..<document.pageCount {
      guard let page = document.page(at: index), let duplicate = page.copy() as? PDFPage else { continue }
      copy.insert(duplicate, at: copy.pageCount)
      pages[page] = duplicate
    }
    copy.documentAttributes = document.documentAttributes
    if let outline = document.outlineRoot {
      copy.outlineRoot = Self.copyOutline(outline, pages: pages)
    }
    return copy
  }

  private static func copyOutline(_ item: PDFOutline, pages: [PDFPage: PDFPage]) -> PDFOutline {
    let copy = PDFOutline()
    copy.label = item.label
    copy.isOpen = item.isOpen
    if let destination = item.destination, let page = destination.page, let target = pages[page] {
      copy.destination = PDFDestination(page: target, at: destination.point)
    }
    for index in 0..<item.numberOfChildren {
      guard let child = item.child(at: index) else { continue }
      copy.insertChild(copyOutline(child, pages: pages), at: copy.numberOfChildren)
    }
    return copy
  }

  /// A password change, applied by the next save.
  enum ProtectionChange: Equatable {
    /// Protect the document with this password, which opens it and grants every permission.
    case set(String)
    /// Remove the password and every restriction.
    case remove
  }

  /// Whether a password protects the document, counting a change waiting for the next save.
  public var isPasswordProtected: Bool {
    switch pendingProtection {
    case .set: true
    case .remove: false
    case nil: wasEncrypted
    }
  }

  /// Whether the password can be removed: the document is protected, and was opened with its owner
  /// password (a password that only opens it can't lift the author's protection).
  public var canRemovePassword: Bool {
    wasEncrypted && !isLocked && document.permissionsStatus == .owner
  }

  /// Protects the document with a password when it is next saved.
  ///
  /// An empty password does nothing.
  ///
  /// - Returns: `false` when the password is empty, or the document's author restricted it and it
  ///   wasn't opened with the owner password.
  @discardableResult
  public func setPassword(_ newPassword: String) -> Bool {
    guard !newPassword.isEmpty, !isLocked, !wasEncrypted || document.permissionsStatus == .owner else { return false }
    pendingProtection = .set(newPassword)
    hasUnsavedChanges = true
    return true
  }

  /// Removes the password and every restriction when the document is next saved.
  ///
  /// - Returns: `false` when the document has no password, or wasn't opened with its owner password.
  @discardableResult
  public func removePassword() -> Bool {
    guard wasEncrypted, !isLocked, document.permissionsStatus == .owner else { return false }
    pendingProtection = .remove
    hasUnsavedChanges = true
    return true
  }

  /// Room kept free beyond the new file, so a save never fills the device (`Assumption:` 50 MB).
  static let spareSpace: Int64 = 50_000_000

  /// Whether a file of `byteCount` bytes can be written safely with `available` bytes free.
  ///
  /// The atomic write holds the new file next to the old one until it replaces it, and the kept earlier
  /// version holds the old one's space after that, so the new file must fit whole, with room to spare.
  /// When the free space can't be read, the save goes ahead and the write itself reports a full disk.
  static func hasRoom(toWrite byteCount: Int, available: Int64?) -> Bool {
    guard let available else { return true }
    return available >= Int64(byteCount) + spareSpace
  }

  /// Whether the document's author allows notes and markup; always true for unencrypted documents.
  public var allowsAnnotating: Bool { document.allowsCommenting }

  /// Whether the document's author allows printing; always true for unencrypted documents.
  public var allowsPrinting: Bool { document.allowsPrinting }

  /// The write options that keep an encrypted document's protection (defect D9).
  ///
  /// - Opened with the owner password: that password keeps protecting it and opens it.
  /// - Opened with the user password, or with none: the user password and the author's restrictions
  ///   stay as they were, under a new owner password nobody knows. The user password never grants
  ///   more than it did, and the original owner password, which this app never had, no longer applies.
  ///
  /// - Throws: `PDFEngineError.restricted` when the author does not allow the unsaved changes.
  func protectionOptions() throws -> [PDFDocumentWriteOption: Any] {
    switch pendingProtection {
    case .set(let newPassword):
      return [.userPasswordOption: newPassword, .ownerPasswordOption: newPassword]
    case .remove:
      guard document.permissionsStatus == .owner else { throw PDFEngineError.restricted }
      return [:]
    case nil:
      break
    }
    guard wasEncrypted else { return [:] }
    if hasUnsavedChanges && !document.allowsCommenting || hasChangedFormValues && !document.allowsFormFieldEntry {
      throw PDFEngineError.restricted
    }
    if document.permissionsStatus == .owner, let password {
      return [.userPasswordOption: password, .ownerPasswordOption: password]
    }
    var options: [PDFDocumentWriteOption: Any] = [
      .ownerPasswordOption: UUID().uuidString + UUID().uuidString,
      .accessPermissionsOption: document.accessPermissions.rawValue,
    ]
    if let password { options[.userPasswordOption] = password }
    return options
  }
}
