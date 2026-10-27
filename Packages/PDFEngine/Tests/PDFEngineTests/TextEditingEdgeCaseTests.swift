import CoreGraphics
import Foundation
import PDFEngineTestSupport
import PDFKit
import Testing

@testable import PDFEngine

#if canImport(UIKit)
  import UIKit
#endif

/// Edge cases the R1 adversarial review found in text editing (issues #251, #252, #268, #269 and
/// #305), each read through the same public path the reader uses.
@MainActor
@Suite("Text editing: edge cases from the R1 review")
struct TextEditingEdgeCaseTests {
  private let editor = ContentStreamTextEditor()

  /// A one-page file read as it is, without PDFKit rewriting it first.
  private func analysis(content: String, fonts: String) throws -> PageAnalysis {
    try PageAnalysis(
      TextEditFixtures.assemble([
        "<< /Type /Catalog /Pages 2 0 R >>", "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << \(fonts) >> >> >>",
        "<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream",
      ]))
  }

  /// A page ready for the editor, and the regions it finds.
  private func prepared(_ data: Data) async throws -> (page: Data, regions: [EditableTextRegion]) {
    let page = try TextEditFixtures.singlePage(data)
    return (page, await editor.text(ofPage: page).regions)
  }

  /// A controller with time enough for any machine, as the reader has one.
  private func controller(_ data: Data) throws -> PDFDocumentController {
    let controller = try PDFDocumentController(data: data)
    controller.textFindLimit = .seconds(600)
    controller.textEditLimit = .seconds(600)
    controller.setEditingText(true)
    return controller
  }

  // MARK: - #251

  /// A page tinted pale blue in a band around one line, and white everywhere else.
  private static func tintedLine(mediaBox: String, pageEntries: String = "") -> Data {
    TextEditFixtures.raw(
      content: "0.8 0.9 1 rg 40 670 420 70 re f 0 g BT /F1 14 Tf 72 700 Td (Total due) Tj ET", mediaBox: mediaBox,
      pageEntries: pageEntries)
  }

  @Test(
    "The cover takes the colour from behind the text, on a turned page and on one whose box is offset (#251)",
    arguments: [("0 0 612 792", "/Rotate 90"), ("0 50 612 842", ""), ("0 0 612 792", "")])
  func coverMatchesTheBackground(mediaBox: String, pageEntries: String) async throws {
    let controller = try controller(Self.tintedLine(mediaBox: mediaBox, pageEntries: pageEntries))
    let regions = await controller.pageText(onPage: 0).regions
    let region = try #require(regions.first { $0.text.contains("Total") }, "\(regions.map(\.text))")
    controller.selectTextRegion(region, onPage: 0)
    #expect(controller.coverSelectedText(with: "Amount due", insteadOfEditing: true) == .edited(.visualReplacement))
    let page = try #require(controller.document.page(at: 0))
    let cover = try #require(page.annotations.first { $0.type?.lowercased() == "square" })
    let sRGB = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let color = try #require(
      cover.interiorColor?.cgColor.converted(to: sRGB, intent: .defaultIntent, options: nil)?.components)
    let expected: [CGFloat] = [0.8, 0.9, 1]
    #expect(zip(color, expected).allSatisfy { abs($0 - $1) < 0.03 }, "The cover is \(color), not the page's tint")
  }

  // MARK: - #252

  @Test("Columns set apart in one line are never offered as one string to redraw (#252)")
  func tableRowKeepsItsColumns() async throws {
    // A table row as one TJ: "Qty" and "Amount" four ems apart.
    let (_, regions) = try await prepared(
      TextEditFixtures.raw(content: "BT /F1 10 Tf 72 700 Td [(Qty) -4000 (Amount)] TJ ET"))
    let joined = regions.filter { $0.text.contains("Qty") && $0.text.contains("Amount") }
    #expect(
      joined.allSatisfy { !$0.capability.editsContent },
      "\(joined.map(\.text)) would be redrawn with natural spacing, closing the columns up")
    // A kerning nudge or a word space inside a line is still one line to edit.
    let (_, words) = try await prepared(
      TextEditFixtures.raw(content: "BT /F1 10 Tf 72 700 Td [(Unit) -300 (price) -40 (s)] TJ ET"))
    #expect(words.contains { $0.text == "Unit prices" && $0.capability.editsContent }, "\(words.map(\.text))")
  }

  // MARK: - #268

  @Test("A batch that is not made says none of its edits were made (#268)")
  func partialBatchReportsNothingMade() async throws {
    let (page, regions) = try await prepared(TextEditFixtures.invoice())
    let good = TextEdit(
      region: try #require(regions.first { $0.text.contains("John Smith") }), replacement: "Customer: David Smith")
    let empty = TextEdit(region: try #require(regions.first { $0.text.contains("Materials") }), replacement: "")
    let result = await editor.applying([good, empty], toPage: page)
    #expect(result.page == nil)
    #expect(!result.outcomes.contains { $0.isEdited }, "\(result.outcomes)")
    #expect(result.outcomes.last == .refused(.unsupportedCharacters), "The edit at fault still says why")
  }

  /// A good edit in a batch that failed is not given another edit's reason: a line that fits is
  /// never reported as too long.
  @Test(
    "A good edit in a failed batch is not blamed for the edit at fault (#268)",
    arguments: ["", String(repeating: "A much longer description of the materials used ", count: 8)])
  func goodEditIsNotBlamed(faulty replacement: String) async throws {
    let (page, regions) = try await prepared(TextEditFixtures.invoice())
    let good = TextEdit(
      region: try #require(regions.first { $0.text.contains("John Smith") }), replacement: "Customer: David Smith")
    let faulty = TextEdit(
      region: try #require(regions.first { $0.text.contains("Materials") }), replacement: replacement)
    let result = await editor.applying([good, faulty], toPage: page)
    #expect(result.page == nil && !result.outcomes.contains { $0.isEdited }, "\(result.outcomes)")
    #expect(result.outcomes.first != result.outcomes.last, "The good edit says \(result.outcomes)")
  }

  // MARK: - #269

  @Test("Invisible text set with a real-number rendering mode is not offered (#269)", arguments: ["3", "3.0"])
  func realNumberRenderingMode(mode: String) throws {
    let page = try analysis(
      content: "BT /F1 12 Tf \(mode) Tr 72 700 Td (Hidden words) Tj ET",
      fonts: "/F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>")
    #expect(page.content.runs.first?.renderingMode == 3)
    #expect(page.regions.isEmpty, "Invisible text is not a line to edit")
  }

  @Test("Undoing a text edit gives back the memory it was counted for (#269)")
  func undoGivesBackMemory() async throws {
    let controller = try controller(TextEditFixtures.invoice())
    for round in 0..<3 {
      let regions = await controller.pageText(onPage: 0).regions
      let region = try #require(regions.first { $0.text.contains("John Smith") })
      let outcomes = await controller.applyTextEdits(
        [TextEdit(region: region, replacement: "Customer: Jane Smith \(round)")], onPage: 0)
      #expect(outcomes.allSatisfy { $0.isEdited }, "\(outcomes)")
      #expect(controller.textUndoBytes > 0)
      controller.undoManager.undo()
      #expect(controller.textUndoBytes == 0, "Round \(round): the undone edit is still counted")
    }
    // Redo counts it again.
    controller.undoManager.redo()
    #expect(controller.textUndoBytes > 0)
  }

  // MARK: - #305

  @Test("A typed signature is a signature: not a text box, and not text to edit (#305)")
  func typedSignatureIsASignature() throws {
    let controller = try PDFDocumentController(data: TextEditFixtures.invoice())
    #expect(controller.placeTypedSignature("Jane Citizen", onPage: 0))
    let selection = try #require(controller.selection)
    #expect(selection.isSignature && !selection.isTextEditable)
    #expect(controller.annotationSummaries().map(\.isSignature) == [true])
    // It stays one across a save.
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("typed-signature-\(UUID()).pdf")
    defer { try? FileManager.default.removeItem(at: url) }
    try controller.save(to: url)
    let reopened = try PDFDocumentController(url: url)
    #expect(reopened.annotationSummaries().map(\.isSignature) == [true])
    // A text box is still a text box.
    #expect(controller.addTextBox("Check the total", onPage: 0))
    #expect(controller.selection?.isSignature == false && controller.selection?.isTextEditable == true)
  }
}
