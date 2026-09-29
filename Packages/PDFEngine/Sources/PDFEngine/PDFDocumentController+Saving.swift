import Foundation
import PDFKit

extension PDFDocumentController {
  /// Writes the document atomically with coordinated access; a failed save leaves the file unchanged (NFR-REL-002).
  ///
  /// Encrypted documents keep their password.
  ///
  /// - Throws: `PDFEngineError.saveFailed`.
  public func save(to url: URL) throws {
    var options: [PDFDocumentWriteOption: Any] = [:]
    if wasEncrypted, let password {
      options[.userPasswordOption] = password
      options[.ownerPasswordOption] = password
    }
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
}
