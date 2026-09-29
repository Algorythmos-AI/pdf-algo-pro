import Foundation
import PDFKit

extension PDFDocumentController {
  /// Writes the document atomically with coordinated access; a failed save leaves the file unchanged (NFR-REL-002).
  ///
  /// An encrypted document stays encrypted, with the same restrictions (see `protectionOptions()`).
  ///
  /// - Throws: `PDFEngineError.restricted` when the document's author does not allow the change;
  ///   `PDFEngineError.saveFailed` when writing fails.
  public func save(to url: URL) throws {
    let options = try protectionOptions()
    let staging = FileManager.default.temporaryDirectory.appendingPathComponent("save-\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: staging) }
    guard document.write(to: staging, withOptions: options), let data = try? Data(contentsOf: staging),
      PDFDocument(data: data) != nil
    else { throw PDFEngineError.saveFailed }
    var coordinationError: NSError?
    var writeError: (any Error)?
    NSFileCoordinator(filePresenter: nil).coordinate(
      writingItemAt: url, options: .forReplacing, error: &coordinationError
    ) {
      target in
      do {
        try data.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      } catch {
        writeError = error
      }
    }
    guard coordinationError == nil, writeError == nil else { throw PDFEngineError.saveFailed }
    hasUnsavedChanges = false
    recordFormValues()
  }

  /// Whether the document's author allows notes and markup; always true for unencrypted documents.
  public var allowsAnnotating: Bool { document.allowsCommenting }

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
