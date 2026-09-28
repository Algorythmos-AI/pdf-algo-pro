import Core
import CoreTestSupport
import Foundation
import PDFEngine
import SwiftUI
import Testing

@testable import ScanFeature

@MainActor
@Suite("Scan model")
struct ScanModelTests {
  private func makeModel(
    inspector: FakeInspector = FakeInspector()
  ) -> (ScanModel, FakeDocumentLibrary, RecordingTelemetry, Opened) {
    let library = FakeDocumentLibrary()
    let telemetry = RecordingTelemetry()
    let opened = Opened()
    let model = ScanModel(
      intake: DocumentIntake(library: library, inspector: inspector, index: FakeIndex()),
      builder: SearchablePDFBuilder(recognizer: FakeRecognizer()), telemetry: telemetry,
      now: { Date(timeIntervalSince1970: 1_800_000_000) }, onFinish: { opened.document = $0 })
    return (model, library, telemetry, opened)
  }

  @Test("Scans become searchable documents in the library and open (FR-SCAN-002)")
  func scanning() async throws {
    let (model, library, telemetry, opened) = makeModel()
    let image = try #require(SyntheticPDF.makeTextImage("Receipt"))
    await model.process([image, image])
    guard case .finished(let document) = model.phase else { throw Failure.unexpected }
    #expect(opened.document?.id == document.id)
    #expect(document.title.hasPrefix("Scan "))
    #expect(try await library.documents(in: .all, sortedBy: .title).count == 1)
    #expect(await telemetry.events == ["task.core.completed"])
  }

  @Test("Nothing to scan does nothing; failures save nothing")
  func emptyAndFailure() async throws {
    let (model, _, _, _) = makeModel()
    await model.process([])
    #expect(model.phase == .ready)
    let (failing, library, telemetry, opened) = makeModel(inspector: FakeInspector(fails: true))
    await failing.process([try #require(SyntheticPDF.makeTextImage("x"))])
    #expect(failing.phase == .failed)
    #expect(opened.document == nil)
    #expect(try await library.documents(in: .all, sortedBy: .title).isEmpty)
    #expect(await telemetry.events == ["quality.operation.failed"])
    failing.reset()
    #expect(failing.phase == .ready)
  }

  @Test func titlesCarryTheDate() {
    let (model, _, _, _) = makeModel()
    #expect(model.defaultTitle.hasPrefix("Scan "))
    #expect(model.defaultTitle.count > 8)
  }

  @Test func sheetRenders() {
    let (model, _, _, _) = makeModel()
    #expect(ImageRenderer(content: ScanView(model: model).frame(width: 390, height: 700)).uiImage != nil)
  }
}

@MainActor
private final class Opened {
  var document: Document?
}

private enum Failure: Error { case unexpected }
