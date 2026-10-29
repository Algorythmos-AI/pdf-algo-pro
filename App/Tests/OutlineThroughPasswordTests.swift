import Foundation
import PDFEngine
import PDFKit
import XCTest

/// A file's outline keeps its web address and zoom through a password being set, saved, opened again
/// and removed (#356).
///
/// It runs in the app's bundle, so the Device plan runs it on a real iPhone as well as the simulator;
/// PDFEngine's own tests run tool-hosted, which a device can't do. It covers the path a person takes, an
/// outline read from a file. It is not the proof of #356's fix: that fault showed only when PDFKit had
/// dropped an outline made in memory and the engine rewrote it, which PDFEngine's
/// `passwordRemovalKeepsOutlineActions` covers on iOS 27. On a device this test passed before the fix
/// as well.
nonisolated final class OutlineThroughPasswordTests: XCTestCase {
  private let address = URL(string: "https://example.com/terms")!

  /// A three-page document whose outline opens a web address and goes to page 2 at zoom 2.
  ///
  /// Written by hand: on iOS 27, PDFKit's own `dataRepresentation()` drops an outline (#307), so a
  /// fixture made with it would have none to lose.
  private func fixture() throws -> Data {
    let objects = [
      "<< /Type /Catalog /Pages 2 0 R /Outlines 6 0 R /PageMode /UseOutlines >>",
      "<< /Type /Pages /Kids [3 0 R 4 0 R 5 0 R] /Count 3 >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>",
      "<< /Type /Outlines /First 7 0 R /Last 8 0 R /Count 2 >>",
      "<< /Title (Terms) /Parent 6 0 R /Next 8 0 R /A << /S /URI /URI (\(address.absoluteString)) >> >>",
      "<< /Title (Two) /Parent 6 0 R /Prev 7 0 R /Dest [4 0 R /XYZ 72 700 2] >>",
    ]
    var text = "%PDF-1.7\n"
    var offsets: [Int] = []
    for (index, object) in objects.enumerated() {
      offsets.append(text.utf8.count)
      text += "\(index + 1) 0 obj\n\(object)\nendobj\n"
    }
    let start = text.utf8.count
    text += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
    for offset in offsets { text += String(format: "%010d 00000 n \n", offset) }
    text += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(start)\n%%EOF\n"
    let data = Data(text.utf8)
    let check = try XCTUnwrap(PDFDocument(data: data), "the fixture opens")
    XCTAssertEqual(check.outlineRoot?.numberOfChildren, 2, "the fixture has its outline before anything is saved")
    return data
  }

  /// The first entry's web address, and the second's page and zoom, as the file at `url` has them.
  private func entries(at url: URL) throws -> (url: URL?, page: Int?, zoom: CGFloat?) {
    let document = try XCTUnwrap(PDFDocument(url: url), "the saved file opens")
    XCTAssertFalse(document.isEncrypted, "the saved file has no password")
    let root = try XCTUnwrap(document.outlineRoot, "the saved file has an outline")
    XCTAssertEqual(root.numberOfChildren, 2, "the saved outline keeps both entries")
    let web = (root.child(at: 0)?.action as? PDFActionURL)?.url
    let item = root.child(at: 1)
    let destination = item?.destination ?? (item?.action as? PDFActionGoTo)?.destination
    return (web, destination?.page.map { document.index(for: $0) }, destination?.zoom)
  }

  @MainActor func testAnOutlinesWebAddressAndZoomSurviveAPasswordAndItsRemoval() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("outline-\(UUID()).pdf")
    defer { try? FileManager.default.removeItem(at: url) }

    // A protected file's outline isn't readable through a fresh PDFDocument, even unlocked, so the file
    // is checked once its password is gone: an address the protected save lost can't come back there.
    let protected = try PDFDocumentController(data: try fixture())
    XCTAssertTrue(protected.setPassword("secret"))
    try protected.save(to: url)

    let opened = try PDFDocumentController(url: url)
    XCTAssertTrue(opened.unlock(password: "secret") && opened.removePassword())
    try opened.save(to: url)
    let open = try entries(at: url)
    XCTAssertEqual(open.url, address, "with the password removed, the web entry: \(String(describing: open.url))")
    XCTAssertEqual(open.page, 1, "with the password removed, the zoomed entry's page")
    XCTAssertEqual(open.zoom ?? 0, 2, accuracy: 0.01, "with the password removed, the zoomed entry's zoom")
  }
}
