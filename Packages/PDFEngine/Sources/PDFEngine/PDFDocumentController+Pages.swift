import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Page organising (FR-ORG-001), flattening (FR-ORG-006) and pages as images (FR-ORG-007).
///
/// Every change to the pages is one undo step and is saved like any other edit, through the save that
/// keeps the version before it (FR-EDIT-008).
extension PDFDocumentController {
  /// Whether the document's author allows pages to be added, removed, moved and rotated.
  public var allowsOrganizing: Bool { !isLocked && document.allowsDocumentAssembly }

  /// Rotates pages by a multiple of 90 degrees, clockwise when positive.
  ///
  /// - Returns: `false`, changing nothing, when the author doesn't allow it or an index is out of range.
  @discardableResult
  public func rotatePages(_ indexes: IndexSet, by degrees: Int) -> Bool {
    guard allowsOrganizing, degrees % 90 == 0, degrees % 360 != 0, isValid(indexes) else { return false }
    rotate(indexes.compactMap { document.page(at: $0) }, by: degrees)
    return true
  }

  /// Deletes pages; at least one page always stays.
  ///
  /// - Returns: `false`, changing nothing, when the author doesn't allow it, an index is out of range,
  ///   or every page would go.
  @discardableResult
  public func deletePages(_ indexes: IndexSet) -> Bool {
    guard allowsOrganizing, isValid(indexes), indexes.count < pageCount else { return false }
    remove(pages: indexes.compactMap { index in document.page(at: index).map { (index, $0) } })
    return true
  }

  /// Moves one page to a new position.
  ///
  /// - Returns: `false`, changing nothing, when the author doesn't allow it or a position is out of range.
  @discardableResult
  public func movePage(from source: Int, to destination: Int) -> Bool {
    guard allowsOrganizing, source != destination, (0..<pageCount).contains(source),
      (0..<pageCount).contains(destination)
    else { return false }
    move(from: source, to: destination)
    return true
  }

  /// A new PDF holding copies of the chosen pages, in order, with their annotations.
  ///
  /// - Throws: `PDFEngineError.restricted` when the author doesn't allow copying pages out;
  ///   `PDFEngineError.saveFailed` when no PDF could be made.
  public func extractPages(_ indexes: IndexSet) throws -> Data {
    guard allowsOrganizing else { throw PDFEngineError.restricted }
    guard isValid(indexes) else { throw PDFEngineError.saveFailed }
    let extracted = PDFDocument()
    for (position, index) in indexes.enumerated() {
      guard let page = document.page(at: index)?.copy() as? PDFPage else { throw PDFEngineError.saveFailed }
      extracted.insert(page, at: position)
    }
    guard let data = extracted.dataRepresentation() else { throw PDFEngineError.saveFailed }
    return data
  }

  /// A copy of the document with its annotations and form fields drawn into the pages (FR-ORG-006).
  ///
  /// Every reader then shows them the same way and nobody can edit them. Text stays text.
  ///
  /// - Throws: `PDFEngineError.restricted` for a locked document; `PDFEngineError.saveFailed` when no
  ///   PDF could be made.
  public func flattenedData() throws -> Data {
    guard !isLocked else { throw PDFEngineError.restricted }
    endEditing()
    let pages = (0..<pageCount).compactMap { document.page(at: $0) }
    let boxes = pages.map { page in
      let box = page.bounds(for: .cropBox)
      return page.rotation % 180 == 0 ? box.size : CGSize(width: box.height, height: box.width)
    }
    return try PDFWriter.makePDF(mediaBoxes: boxes.map { CGRect(origin: .zero, size: $0) }) { context, index, _ in
      context.saveGState()
      pages[index].draw(with: .cropBox, to: context)
      context.restoreGState()
    }
  }

  /// The formats pages can be exported in (FR-ORG-007).
  public enum ImageFormat: Sendable, CaseIterable {
    case png, jpeg

    var type: UTType { self == .png ? .png : .jpeg }
  }

  /// One page as an image, with its annotations, at `scale` pixels per point (2 is sharp on a phone).
  ///
  /// - Throws: `PDFEngineError.renderFailed` when the page can't be drawn.
  public func imageData(ofPage index: Int, format: ImageFormat, scale: CGFloat = 2) throws -> Data {
    guard !isLocked, let page = document.page(at: index), scale > 0 else { throw PDFEngineError.renderFailed }
    let box = page.bounds(for: .cropBox)
    let size = page.rotation % 180 == 0 ? box.size : CGSize(width: box.height, height: box.width)
    let width = max(1, Int((size.width * scale).rounded()))
    let height = max(1, Int((size.height * scale).rounded()))
    guard
      let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { throw PDFEngineError.renderFailed }
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.scaleBy(x: scale, y: scale)
    page.draw(with: .cropBox, to: context)
    guard let image = context.makeImage() else { throw PDFEngineError.renderFailed }
    return try Self.encode(image, as: format)
  }

  static func encode(_ image: CGImage, as format: ImageFormat) throws -> Data {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(data, format.type.identifier as CFString, 1, nil) else {
      throw PDFEngineError.renderFailed
    }
    let options = format == .jpeg ? [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary : nil
    CGImageDestinationAddImage(destination, image, options)
    guard CGImageDestinationFinalize(destination) else { throw PDFEngineError.renderFailed }
    return data as Data
  }

  // MARK: - Undoable steps

  private func isValid(_ indexes: IndexSet) -> Bool {
    !indexes.isEmpty && (indexes.last ?? .max) < pageCount
  }

  func rotate(_ pages: [PDFPage], by degrees: Int) {
    for page in pages { page.rotation = ((page.rotation + degrees) % 360 + 360) % 360 }
    pagesChanged()
    undoManager.registerUndo(withTarget: self) { controller in
      MainActor.assumeIsolated { controller.rotate(pages, by: -degrees) }
    }
  }

  func remove(pages: [(Int, PDFPage)]) {
    for (index, _) in pages.sorted(by: { $0.0 > $1.0 }) { document.removePage(at: index) }
    pagesChanged()
    undoManager.registerUndo(withTarget: self) { controller in
      MainActor.assumeIsolated { controller.insert(pages: pages) }
    }
  }

  func insert(pages: [(Int, PDFPage)]) {
    for (index, page) in pages.sorted(by: { $0.0 < $1.0 }) { document.insert(page, at: index) }
    pagesChanged()
    undoManager.registerUndo(withTarget: self) { controller in
      MainActor.assumeIsolated { controller.remove(pages: pages) }
    }
  }

  func move(from source: Int, to destination: Int) {
    guard let page = document.page(at: source) else { return }
    document.removePage(at: source)
    document.insert(page, at: destination)
    pagesChanged()
    undoManager.registerUndo(withTarget: self) { controller in
      MainActor.assumeIsolated { controller.move(from: destination, to: source) }
    }
  }

  private func pagesChanged() {
    hasUnsavedChanges = true
    structureGeneration += 1
    view?.reload()
  }
}

/// PDFs made from pictures (FR-ORG-008).
public enum ImagePDF {
  /// The longest side of a page made from a picture, in points (A4's long side).
  static let maximumSide: CGFloat = 842

  /// A PDF with one page per picture, each page the picture's shape, its longest side at most A4's.
  ///
  /// - Throws: `PDFEngineError.saveFailed` when there are no pictures or no PDF could be made.
  public static func make(from images: [CGImage]) throws -> Data {
    guard !images.isEmpty else { throw PDFEngineError.saveFailed }
    let boxes = images.map { image in
      let width = CGFloat(image.width)
      let height = CGFloat(image.height)
      let scale = min(1, maximumSide / max(width, height, 1))
      return CGRect(x: 0, y: 0, width: (width * scale).rounded(), height: (height * scale).rounded())
    }
    return try PDFWriter.makePDF(mediaBoxes: boxes) { context, index, box in
      context.interpolationQuality = .high
      context.draw(images[index], in: box)
    }
  }
}
