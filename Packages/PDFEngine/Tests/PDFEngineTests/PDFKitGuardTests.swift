import Foundation
import PDFEngine
import PDFKit
import PDFKitGuard
import Testing

/// A selection whose attributed string fails the way PDFKit's does when it can't make a font (#311).
private final class RaisingSelection: PDFSelection {
  override var attributedString: NSAttributedString? {
    NSException(
      name: .invalidArgumentException,
      reason: "*** -[__NSDictionaryM setObject:forKey:]: object cannot be nil (key: NSFont)"
    ).raise()
    return nil
  }
}

@Suite("Guarding the PDFKit call that raises an Objective-C exception (#311)")
struct PDFKitGuardTests {
  @Test("A selection whose attributed string raises gives none, instead of ending the process")
  func raisingSelection() {
    #expect(guardedAttributedString(of: RaisingSelection(document: PDFDocument())) == nil)
  }

  @Test("A selection whose attributed string reads is returned as PDFKit builds it")
  func readableSelection() throws {
    let document = try #require(PDFDocument(data: SyntheticPDF.make(pages: ["Hello world"])))
    let page = try #require(document.page(at: 0))
    let selection = try #require(page.selection(for: page.bounds(for: .mediaBox)))
    let guarded = try #require(guardedAttributedString(of: selection))
    #expect(guarded.string == selection.attributedString?.string)
    #expect(guarded.string.contains("Hello world"))
  }
}
