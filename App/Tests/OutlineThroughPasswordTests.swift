import Foundation
import PDFEngine
import PDFKit
import XCTest

/// An outline's web address and zoom through a password being set, saved, opened again and removed (#356).
///
/// PDFEngine's own test of this runs tool-hosted, which a device can't do, so this one runs in the app's
/// bundle: on every simulator run and in the Device plan on a real iPhone, whose PDFKit is the one that
/// dropped the address on iOS 27.
@MainActor final class OutlineThroughPasswordTests: XCTestCase {
  private let address = URL(string: "https://example.com/terms")!

  /// A three-page document whose outline opens a web address and goes to page 2 at zoom 2.
  private func fixture() throws -> Data {
    let source = try XCTUnwrap(PDFDocument(data: SyntheticPDF.make(pages: ["One", "Two", "Three"])))
    let root = PDFOutline()
    let web = PDFOutline()
    web.label = "Terms"
    web.action = PDFActionURL(url: address)
    root.insertChild(web, at: 0)
    let zoomed = PDFOutline()
    zoomed.label = "Two"
    let destination = PDFDestination(page: try XCTUnwrap(source.page(at: 1)), at: CGPoint(x: 72, y: 700))
    destination.zoom = 2
    zoomed.destination = destination
    root.insertChild(zoomed, at: 1)
    source.outlineRoot = root
    return try XCTUnwrap(source.dataRepresentation())
  }

  /// The first entry's web address, and the second's page and zoom, as the file at `url` has them.
  private func entries(at url: URL, password: String? = nil) throws -> (url: URL?, page: Int?, zoom: CGFloat?) {
    let document = try XCTUnwrap(PDFDocument(url: url), "the saved file opens")
    if let password { XCTAssertTrue(document.unlock(withPassword: password), "the password opens it") }
    let root = try XCTUnwrap(document.outlineRoot, "the saved file has an outline")
    XCTAssertEqual(root.numberOfChildren, 2, "the saved outline keeps both entries")
    let web = (root.child(at: 0)?.action as? PDFActionURL)?.url
    let item = root.child(at: 1)
    let destination = item?.destination ?? (item?.action as? PDFActionGoTo)?.destination
    return (web, destination?.page.map { document.index(for: $0) }, destination?.zoom)
  }

  func testAnOutlinesWebAddressAndZoomSurviveAPasswordAndItsRemoval() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("outline-\(UUID()).pdf")
    defer { try? FileManager.default.removeItem(at: url) }

    let protected = try PDFDocumentController(data: try fixture())
    XCTAssertTrue(protected.setPassword("secret"))
    try protected.save(to: url)
    let locked = try entries(at: url, password: "secret")
    XCTAssertEqual(locked.url, address, "with the password set, the web entry: \(String(describing: locked.url))")
    XCTAssertEqual(locked.page, 1, "with the password set, the zoomed entry's page")
    XCTAssertEqual(locked.zoom ?? 0, 2, accuracy: 0.01, "with the password set, the zoomed entry's zoom")

    let opened = try PDFDocumentController(url: url)
    XCTAssertTrue(opened.unlock(password: "secret") && opened.removePassword())
    try opened.save(to: url)
    let open = try entries(at: url)
    XCTAssertEqual(open.url, address, "with the password removed, the web entry: \(String(describing: open.url))")
    XCTAssertEqual(open.page, 1, "with the password removed, the zoomed entry's page")
    XCTAssertEqual(open.zoom ?? 0, 2, accuracy: 0.01, "with the password removed, the zoomed entry's zoom")
  }
}
