import Foundation
import PDFKit
import Testing

@testable import PDFEngine

/// Runs the text editor over documents on this machine and prints what happened to each line, as
/// codes and counts only.
///
/// For finding out why a real document cannot be edited without the document ever entering the
/// repository (AGENTS.md, rule 6) or its words being shown: nothing it prints comes from the
/// document's text. It is skipped unless `PAP_PROBE_PDF` names a PDF or a folder of them:
///
///     PAP_PROBE_PDF=~/Desktop/pdf-probe swift test --filter TextEditingProbe
/// The PDF or folder to probe, if one was named.
private let probeTarget = ProcessInfo.processInfo.environment["PAP_PROBE_PDF"]

@MainActor
@Suite("Text editing probe (local documents)")
struct TextEditingProbe {
  /// What happened to the lines of one document.
  private struct Tally {
    var lines = 0
    var edited = 0
    var coverOnly = 0
    var tooLong = 0
    var refused: [String: Int] = [:]
  }

  @Test("Every line of each document is replaced, and the outcome counted", .enabled(if: probeTarget != nil))
  func probe() async throws {
    let path = (try #require(probeTarget) as NSString).expandingTildeInPath
    var isFolder: ObjCBool = false
    try #require(FileManager.default.fileExists(atPath: path, isDirectory: &isFolder), "nothing at the path")
    let files =
      isFolder.boolValue
      ? try FileManager.default.contentsOfDirectory(atPath: path).filter { $0.lowercased().hasSuffix(".pdf") }.sorted()
        .map { URL(fileURLWithPath: path).appendingPathComponent($0) }
      : [URL(fileURLWithPath: path)]
    print("PROBE documents: \(files.count)")
    for (number, file) in files.enumerated() {
      guard let document = PDFDocument(url: file), !document.isLocked else {
        print("PROBE doc \(number): cannot be opened")
        continue
      }
      var tally = Tally()
      let producer = (document.documentAttributes?[PDFDocumentAttribute.producerAttribute] as? String) ?? "?"
      for pageIndex in 0..<min(document.pageCount, 5) {
        guard let page = document.page(at: pageIndex), let snapshot = PDFDocumentController.snapshot(of: page) else {
          continue
        }
        await probe(snapshot, page: pageIndex, document: number, into: &tally)
      }
      // The producer is the name of the software that wrote the file, not something from its text.
      print(
        "PROBE doc \(number): producer \(producer.prefix(40)), pages \(document.pageCount), lines \(tally.lines), "
          + "edited \(tally.edited), cover only \(tally.coverOnly), too long \(tally.tooLong), "
          + "refused \(tally.refused.sorted { $0.key < $1.key })")
    }
  }

  private func probe(_ snapshot: Data, page: Int, document: Int, into tally: inout Tally) async {
    let editor = ContentStreamTextEditor()
    let text = await editor.text(ofPage: snapshot)
    if let analysis = try? PageAnalysis(snapshot) {
      var fonts: [String: Int] = [:]
      for region in analysis.regions {
        let font = region.font
        let kind =
          "\(font.program == nil ? "not embedded" : "embedded"), "
          + "\(FontMatcher.hasDeviceFont(for: font) ? "on device" : "not on device")"
        fonts[kind, default: 0] += 1
      }
      print("PROBE doc \(document) page \(page): kind \(text.kind), regions \(text.regions.count), fonts \(fonts)")
      // The shape of the text's placement, as numbers: how the page maps text to paper.
      let shapes = Set(
        analysis.regions.map { region -> String in
          let m = region.drawing
          return String(
            format: "a%.2f b%.2f c%.2f d%.2f scale%.2f size%.1f", m.a, m.b, m.c, m.d, region.horizontalScale,
            region.pointSize)
        })
      print("PROBE doc \(document) page \(page): placements \(shapes.sorted().prefix(6))")
    }
    for (index, region) in text.regions.enumerated() {
      tally.lines += 1
      guard region.capability.editsContent else {
        tally.coverOnly += 1
        continue
      }
      // The line's own words (does anything at all get through?) and a made-up replacement of
      // about the same length (can new words be drawn?).
      let made = String(repeating: "Nemo ", count: max(1, region.text.count / 5)).trimmingCharacters(in: .whitespaces)
      var codes: [String] = []
      var worst: TextEditOutcome = .edited(.contentStream)
      for replacement in [region.text, made] {
        let result = await editor.applying([TextEdit(region: region, replacement: replacement)], toPage: snapshot)
        let outcome = result.outcomes.first ?? .refused(.stale)
        switch outcome {
        case .edited(let mode): codes.append("ok:\(mode.rawValue)")
        case .tooLong: codes.append("tooLong")
        case .refused(let refusal):
          let proof = result.proofFailure.map { " \($0.check.rawValue) \($0.measured)/\($0.expected)" } ?? ""
          codes.append("refused:\(refusal.rawValue)\(proof)")
        }
        if !outcome.isEdited { worst = outcome }
      }
      switch worst {
      case .edited: tally.edited += 1
      case .tooLong: tally.tooLong += 1
      case .refused(let refusal): tally.refused[refusal.rawValue, default: 0] += 1
      }
      print("PROBE doc \(document) page \(page) line \(index): same words \(codes[0]) | new words \(codes[1])")
    }
  }
}
