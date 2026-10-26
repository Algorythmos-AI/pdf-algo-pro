import CoreGraphics
import Foundation
import PDFKit
import Testing

@testable import PDFEngine

@MainActor
@Suite("Annotations: copy, cut and paste", .serialized)
struct AnnotationClipboardTests {
  private func document() throws -> PDFDocumentController {
    AnnotationClipboard.shared.annotation = nil
    return try PDFDocumentController(data: SyntheticPDF.makeSample())
  }

  @Test("A copied tick is pasted where each tap lands, as many times as wanted")
  func copyAndPasteATick() throws {
    let controller = try document()
    #expect(!controller.canPasteAnnotation)
    #expect(controller.addStamp(.tick, onPage: 0), "A stamp is selected as it is placed")
    let page = try #require(controller.document.page(at: 0))
    let tick = try #require(page.annotations.last)
    #expect(controller.copySelection())
    #expect(controller.canPasteAnnotation)
    controller.isPastingAnnotations = true
    #expect(controller.selection == nil, "Pasting starts with nothing selected, so a tap pastes")
    for point in [CGPoint(x: 120, y: 200), CGPoint(x: 120, y: 300), CGPoint(x: 120, y: 400)] {
      #expect(controller.pasteAnnotation(at: point, onPage: 0))
      let pasted = try #require(page.annotations.last)
      #expect(abs(pasted.bounds.midX - point.x) < 0.5 && abs(pasted.bounds.midY - point.y) < 0.5)
      #expect(pasted.bounds.size == tick.bounds.size)
      #expect(pasted.contents == tick.contents && PDFDocumentController.kind(of: pasted) == .stamp)
      #expect(pasted !== tick)
    }
    #expect(controller.annotationCount(onPage: 0) == 4)
    #expect(controller.hasUnsavedChanges)
  }

  @Test("A paste near the edge stays on the page")
  func pasteStaysOnThePage() throws {
    let controller = try document()
    #expect(controller.addStamp(.tick, onPage: 0))
    #expect(controller.copySelection())
    let page = try #require(controller.document.page(at: 0))
    let box = page.bounds(for: .cropBox)
    #expect(controller.pasteAnnotation(at: CGPoint(x: box.maxX + 50, y: box.minY - 50), onPage: 0))
    let pasted = try #require(page.annotations.last)
    #expect(box.contains(pasted.bounds))
    #expect(!controller.pasteAnnotation(at: .zero, onPage: 99), "No such page")
  }

  @Test("Cut removes the original and keeps it to paste")
  func cut() throws {
    let controller = try document()
    #expect(controller.addShape(.rectangle, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 160), onPage: 0))
    #expect(controller.selectAnnotation(at: CGPoint(x: 150, y: 100), onPage: 0))
    let size = try #require(controller.document.page(at: 0)?.annotations.last).bounds.size
    #expect(controller.cutSelection())
    #expect(controller.annotationCount(onPage: 0) == 0 && controller.selection == nil)
    #expect(controller.canPasteAnnotation)
    #expect(controller.pasteAnnotation(at: CGPoint(x: 300, y: 300), onPage: 0))
    let page = try #require(controller.document.page(at: 0))
    let pasted = try #require(page.annotations.last)
    #expect(PDFDocumentController.kind(of: pasted) == .rectangle)
    #expect(pasted.bounds.size == size)
  }

  @Test("A pen drawing keeps its strokes when pasted, and changing the copy leaves the original as it was")
  func inkIsCopiedWhole() throws {
    let controller = try document()
    let stroke = [CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 150), CGPoint(x: 260, y: 120)]
    #expect(controller.addInk([stroke], onPage: 0))
    let page = try #require(controller.document.page(at: 0))
    let original = try #require(page.annotations.last)
    let strokes = original.paths?.count ?? 0
    #expect(strokes > 0)
    #expect(controller.selectAnnotation(at: CGPoint(x: original.bounds.midX, y: original.bounds.midY), onPage: 0))
    #expect(controller.copySelection())
    #expect(controller.pasteAnnotation(at: CGPoint(x: 400, y: 500), onPage: 0))
    let pasted = try #require(page.annotations.last)
    #expect(pasted.paths?.count == strokes)
    #expect(controller.selectAnnotation(at: CGPoint(x: pasted.bounds.midX, y: pasted.bounds.midY), onPage: 0))
    #expect(controller.moveSelection(by: CGSize(width: 10, height: 10)))
    #expect(original.paths?.count == strokes)
    #expect(original.bounds.minX < 150, "The original did not move")
  }

  @Test("Duplicate puts a copy beside the original and selects it; Undo removes it")
  func duplicate() throws {
    let controller = try document()
    #expect(controller.addStamp(.cross, onPage: 0))
    let page = try #require(controller.document.page(at: 0))
    let original = try #require(page.annotations.last)
    #expect(controller.duplicateSelection())
    let copy = try #require(page.annotations.last)
    #expect(copy !== original)
    #expect(abs(copy.bounds.minX - original.bounds.minX) <= 16.5)
    #expect(controller.selection?.kind == .stamp)
    #expect(!controller.canPasteAnnotation, "Duplicate leaves the clipboard alone")
  }

  @Test("Marks on text are not copied, and nothing is pasted before anything was copied")
  func whatCannotBeCopied() throws {
    let controller = try document()
    #expect(!controller.pasteAnnotation(at: CGPoint(x: 100, y: 100), onPage: 0))
    controller.isPastingAnnotations = true
    #expect(!controller.isPastingAnnotations, "Pasting does not start with nothing to paste")
    let highlight = PDFAnnotation(
      bounds: CGRect(x: 100, y: 500, width: 200, height: 14), forType: .highlight, withProperties: nil)
    let page = try #require(controller.document.page(at: 0))
    page.addAnnotation(highlight)
    #expect(controller.selectAnnotation(at: CGPoint(x: 200, y: 507), onPage: 0))
    #expect(!controller.copySelection() && !controller.cutSelection() && !controller.duplicateSelection())
  }

  @Test("What was copied in one document is pasted in another")
  func acrossDocuments() throws {
    let first = try document()
    #expect(first.addStamp(.tick, onPage: 0))
    #expect(first.copySelection())
    let second = try PDFDocumentController(data: SyntheticPDF.makeSample())
    #expect(second.canPasteAnnotation)
    #expect(second.pasteAnnotationOnCurrentPage())
    #expect(second.annotationCount(onPage: 0) == 1 && second.selection?.kind == .stamp)
  }

  @Test("A stamp from the menu is picked up, not placed, and each tap puts one where it lands")
  func stampIsPickedUp() throws {
    let controller = try document()
    #expect(controller.pickUpStamp(.tick))
    #expect(controller.isPastingAnnotations && controller.annotationCount(onPage: 0) == 0)
    #expect(controller.pasteAnnotation(at: CGPoint(x: 300, y: 300), onPage: 0))
    let page = try #require(controller.document.page(at: 0))
    let tick = try #require(page.annotations.last)
    #expect(PDFDocumentController.kind(of: tick) == .stamp && tick.contents == "✓")
    #expect(abs(tick.bounds.midX - 300) < 0.5 && abs(tick.bounds.midY - 300) < 0.5)
    #expect(!controller.pickUpStamp(.text("  ")))
  }

  /// A document with one of each annotation the app can copy on its first page.
  private func everyCopyableKind(at url: URL? = nil) throws -> PDFDocumentController {
    AnnotationClipboard.shared.annotation = nil
    let controller: PDFDocumentController
    if let url {
      try SyntheticPDF.makeSample().write(to: url)
      controller = try PDFDocumentController(url: url)
    } else {
      controller = try document()
    }
    controller.addNote("Check this", onPage: 0)
    let stroke = [CGPoint(x: 100, y: 100), CGPoint(x: 150, y: 160), CGPoint(x: 180, y: 120)]
    #expect(controller.addInk([stroke], onPage: 0))
    #expect(controller.addInk([stroke.map { CGPoint(x: $0.x, y: $0.y + 120) }], onPage: 0, contents: "Signature"))
    for (tool, y) in [(DrawingTool.rectangle, 400.0), (.oval, 460), (.arrow, 520)] {
      #expect(controller.addShape(tool, from: CGPoint(x: 300, y: y), to: CGPoint(x: 400, y: y + 40), onPage: 0))
    }
    #expect(controller.addTextBox("A text box", onPage: 0))
    #expect(controller.addStamp(.text("PAID"), onPage: 0))
    #expect(controller.addStamp(.tick, onPage: 0))
    #expect(controller.placeTypedSignature("Ada Lovelace", onPage: 0))
    return controller
  }

  private func annotations(on page: PDFPage?) -> [PDFAnnotation] {
    (page?.annotations ?? []).filter { $0.type != "Popup" }
  }

  /// The annotation drawn on its own, as pixels.
  private func pixels(_ annotation: PDFAnnotation) -> [UInt8] {
    let box = annotation.bounds.insetBy(dx: -4, dy: -4)
    let width = Int(box.width * 2)
    let height = Int(box.height * 2)
    var data = [UInt8](repeating: 0, count: width * height * 4)
    data.withUnsafeMutableBytes { raw in
      guard
        let context = CGContext(
          data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return }
      context.scaleBy(x: 2, y: 2)
      context.translateBy(x: -box.minX, y: -box.minY)
      annotation.draw(with: .mediaBox, in: context)
    }
    return data
  }

  @Test("A copy of each kind of annotation the app copies is a new one that reads and looks as the original")
  func copiesAreFaithful() throws {
    let controller = try everyCopyableKind()
    let originals = annotations(on: controller.document.page(at: 0))
    #expect(originals.count == 10)
    let target = try #require(controller.document.page(at: 1))
    for original in originals {
      let copy = try #require(PDFDocumentController.copy(of: original))
      target.addAnnotation(copy)
      let what = "\(original.type ?? "?") \"\(original.contents ?? "")\""
      #expect(copy !== original)
      #expect(copy.type == original.type && copy.bounds == original.bounds, "\(what)")
      #expect(PDFDocumentController.kind(of: copy) == PDFDocumentController.kind(of: original), "\(what)")
      // Both colours and the entries that make up the look, so a difference on a device says what it is.
      let looks = "\(what): original \(Self.look(of: original)); copy \(Self.look(of: copy))"
      #expect(copy.contents == original.contents, "\(what)")
      #expect(copy.color == original.color, "\(looks)")
      #expect(copy.interiorColor == original.interiorColor, "\(looks)")
      #expect(copy.border?.lineWidth == original.border?.lineWidth, "\(what)")
      #expect(copy.font == original.font && copy.fontColor == original.fontColor, "\(what)")
      #expect(copy.alignment == original.alignment, "\(what)")
      #expect(copy.startPoint == original.startPoint && copy.endPoint == original.endPoint, "\(what)")
      #expect(copy.endLineStyle == original.endLineStyle, "\(what)")
      #expect(copy.paths?.map(\.bounds) == original.paths?.map(\.bounds), "\(what)")
      #expect(
        zip(copy.paths ?? [], original.paths ?? []).allSatisfy { $0 !== $1 }, "\(what): its own drawing to change")
      let subject = PDFDocumentController.subjectKey
      #expect(copy.value(forAnnotationKey: subject) as? String == original.value(forAnnotationKey: subject) as? String)
      let drawn = pixels(original)
      #expect(drawn.contains { $0 != 0 }, "\(what) draws something")
      let same = pixels(copy) == drawn
      #expect(same, "looks the same: \(looks)")
    }
  }

  /// An annotation's colours (components and colour space) and the entries that make up its look.
  private static func look(of annotation: PDFAnnotation) -> String {
    func describe(_ color: PlatformColor?) -> String {
      guard let cgColor = color?.cgColor else { return "none" }
      let components = (cgColor.components ?? []).map { String(format: "%.3f", Double($0)) }.joined(separator: " ")
      return "[\(components)] \(cgColor.colorSpace?.name.map { $0 as String } ?? "no colour space")"
    }
    let entries = ["/C", "/IC", "/DA", "/MK", "/BS", "/Border"].map { key in
      "\(key)=\(annotation.annotationKeyValues[key].map { "\($0)" } ?? "absent")"
    }
    return "color \(describe(annotation.color)), interior \(describe(annotation.interiorColor)), "
      + "font colour \(describe(annotation.fontColor)), " + entries.joined(separator: ", ")
  }

  @Test("Pasted and duplicated annotations of every kind the app copies survive a save (#307)")
  func copiesAreSaved() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("copies-\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: url) }
    let controller = try everyCopyableKind(at: url)
    let first = try #require(controller.document.page(at: 0))
    let originals = annotations(on: first)
    for original in originals {
      controller.select(original, on: first)
      #expect(controller.duplicateSelection())
      controller.select(original, on: first)
      #expect(controller.copySelection())
      #expect(controller.pasteAnnotation(at: CGPoint(x: 300, y: 400), onPage: 1))
    }
    try controller.save(to: url)
    let reopened = try #require(PDFDocument(url: url))
    func summary(_ page: PDFPage?) -> [String] {
      annotations(on: page).map { "\($0.type ?? "?") \($0.contents ?? "")" }.sorted()
    }
    let expected = originals.map { "\($0.type ?? "?") \($0.contents ?? "")" }.sorted()
    #expect(summary(reopened.page(at: 0)) == (expected + expected).sorted(), "the originals and their duplicates")
    #expect(summary(reopened.page(at: 1)) == expected, "the pasted copies")
  }

  @Test("Stamps picked up from the menu survive each save, as stamps put straight on the page do (FR-ANN-006)")
  func pickedUpStampsAreSaved() throws {
    // As the reader does it: pick up, paste in the middle of the page, save; then the next stamp.
    let picked = try savedStamps { controller, stamp in
      controller.clearSelection()
      #expect(controller.pickUpStamp(stamp))
      #expect(controller.pasteAnnotationOnCurrentPage())
      controller.isPastingAnnotations = false
    }
    let placed = try savedStamps { controller, stamp in
      #expect(controller.addStamp(stamp, onPage: 0))
    }
    // What each file held after each save, so a failure on a device says which way of placing a stamp,
    // and which save, lost it (#307).
    #expect(picked.count == 2, "picked up and pasted: \(picked.files); placed: \(placed.files)")
    #expect(placed.count == 2, "placed: \(placed.files); picked up and pasted: \(picked.files)")
  }

  /// Puts a tick and then initials on a document's first page, saving after each, and reads the file.
  private func savedStamps(
    _ put: (PDFDocumentController, PDFDocumentController.Stamp) -> Void
  ) throws -> (count: Int, files: [String]) {
    AnnotationClipboard.shared.annotation = nil
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("stamps-\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: url) }
    try SyntheticPDF.makeSample().write(to: url)
    let controller = try PDFDocumentController(url: url)
    var files: [String] = []
    for stamp in [PDFDocumentController.Stamp.tick, .text("SK")] {
      put(controller, stamp)
      try controller.save(to: url)
      files.append(Self.stamps(in: url))
    }
    files.append("in memory: " + Self.stamps(on: controller.document))
    return (try PDFDocumentController(url: url).annotationCount(onPage: 0), files)
  }

  /// The annotations on a file's first page, and how many free-text objects its bytes hold.
  private static func stamps(in url: URL) -> String {
    let bytes = (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    let freeText = bytes.components(separatedBy: "/FreeText").count - 1
    return "file: " + (PDFDocument(url: url).map(stamps(on:)) ?? "unreadable") + " (/FreeText ×\(freeText))"
  }

  private static func stamps(on document: PDFDocument) -> String {
    let annotations = document.page(at: 0)?.annotations ?? []
    return "["
      + annotations.map {
        "\($0.type ?? "?") \"\($0.contents ?? "")\" at \(Int($0.bounds.midX)),\(Int($0.bounds.midY))"
      }
      .joined(separator: ", ") + "]"
  }

  @Test("Placing, drawing, marking and editing text are one mode at a time")
  func oneModeAtATime() throws {
    let controller = try document()
    #expect(controller.pickUpStamp(.tick))
    controller.setDrawing(true)
    #expect(!controller.isPastingAnnotations, "Drawing ends placing")
    controller.isPastingAnnotations = true
    #expect(controller.isPastingAnnotations && !controller.isDrawing, "Placing ends drawing")
    controller.setMarkupTool(.highlight)
    #expect(!controller.isPastingAnnotations, "A marker ends placing")
    controller.isPastingAnnotations = true
    #expect(controller.markupTool == nil)
  }
}
