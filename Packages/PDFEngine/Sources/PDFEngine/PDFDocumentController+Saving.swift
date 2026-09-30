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
    let options = try protectionOptions()
    let staging = FileManager.default.temporaryDirectory.appendingPathComponent("save-\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: staging) }
    document.repairAttributesIfNeeded()
    guard document.write(to: staging, withOptions: options), let data = try? Data(contentsOf: staging),
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
    hasUnsavedChanges = false
    recordFormValues()
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
