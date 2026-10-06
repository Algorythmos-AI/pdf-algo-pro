import Foundation
import PDFKit
import Testing

@testable import PDFEngine

/// Runs the text editor over documents on this machine and prints how the lines of each ended, as
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
  @Test("Every line of each document is changed a little, and how it ends is counted", .enabled(if: probeTarget != nil))
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
    var totals: [LineEnding: Int] = [:]
    var unopened = 0
    for (number, file) in files.enumerated() {
      guard let document = PDFDocument(url: file), !document.isLocked else {
        unopened += 1
        print("PROBE doc \(number): locked or not readable")
        continue
      }
      var counts: [LineEnding: Int] = [:]
      var details: [String: Int] = [:]
      var kinds: [String: Int] = [:]
      // The first pages say what kind of document it is; a long one is not walked to its end.
      for pageIndex in 0..<min(document.pageCount, Self.pagesPerDocument) {
        guard let page = document.page(at: pageIndex), let snapshot = PDFDocumentController.snapshot(of: page) else {
          continue
        }
        let result = await LineSweep.endings(onPage: snapshot)
        kinds["\(result.kind)", default: 0] += 1
        counts.merge(result.counts, uniquingKeysWith: +)
        details.merge(result.details, uniquingKeysWith: +)
      }
      totals.merge(counts, uniquingKeysWith: +)
      // The producer is the name of the software that wrote the file, not something from its text.
      let producer = (document.documentAttributes?[PDFDocumentAttribute.producerAttribute] as? String) ?? "?"
      let row = LineEnding.allCases.map { "\($0.rawValue) \(counts[$0] ?? 0)" }.joined(separator: ", ")
      print(
        "PROBE doc \(number): producer \(producer.prefix(32)), pages \(document.pageCount) \(kinds.sorted { $0.key < $1.key }), "
          + "\(row)\(details.isEmpty ? "" : " \(details.sorted { $0.key < $1.key })")")
    }
    let row = LineEnding.allCases.map { "\($0.rawValue) \(totals[$0] ?? 0)" }.joined(separator: ", ")
    print("PROBE total: documents \(files.count), not opened \(unopened), \(row)")
  }

  /// How many pages of each document are looked at.
  private static let pagesPerDocument = 3
}
