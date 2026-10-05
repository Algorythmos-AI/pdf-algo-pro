import Testing

@testable import Core

@Suite("Text editing diagnostics")
struct TextEditingDiagnosticsTests {
  @Test("The record reads as counts")
  func lines() {
    var record = TextEditingDiagnostics(pageKind: .text)
    record.direct = 12
    record.limited = 3
    record.coverOnly = ["unsupportedFont": 2, "unsupportedScript": 1]
    record.findMilliseconds = 41
    record.viewIsBound = true
    record.outlinedPages = 2
    record.taps = 4
    record.picks = 3
    record.lastEdit = .refused("notVerified")
    record.editMilliseconds = 310
    #expect(
      record.lines == [
        "Text editing page: text",
        "Text editing regions: direct 12, matched font 3, cover only 3",
        "Text editing cover only (unsupportedFont): 2",
        "Text editing cover only (unsupportedScript): 1",
        "Text editing find: 41 ms",
        "Text editing view: bound, outlined pages 2",
        "Text editing taps: 4, picked 3",
        "Text editing last edit: refused (notVerified), 310 ms",
      ])
    record.lastEdit = .edited
    #expect(record.lines.last == "Text editing last edit: made, 310 ms")
    record.lastEdit = .tooLong
    #expect(record.lines.last == "Text editing last edit: too long, 310 ms")
    #expect(TextEditingDiagnostics(pageKind: .timedOut).lines.first == "Text editing page: timed-out")
    #expect(TextEditingDiagnostics(pageKind: .image).lines.contains("Text editing view: not bound, outlined pages 0"))
  }

  @Test("A reason is cut down to letters, so a wrongly filled field cannot carry a document's words")
  func reasonsAreReduced() {
    var record = TextEditingDiagnostics(pageKind: .text)
    record.coverOnly = ["Salary: 4 200,00 EUR for Jane Example, 12 Sample Street": 1]
    record.lastEdit = .refused("IBAN FR76 3000 6000 0112 3456 7890 189")
    let text = record.lines.joined(separator: "\n")
    #expect(!text.contains("4 200") && !text.contains("FR76") && !text.contains("Sample Street"))
    #expect(TextEditingDiagnostics.safe("unsupportedFont") == "unsupportedFont")
    #expect(TextEditingDiagnostics.safe("a b-c 1 2 3 é").count == 3)
  }

  @MainActor
  @Test("The log keeps the latest record and says nothing before there is one")
  func log() {
    let log = TextEditingDiagnosticsLog()
    #expect(log.summary().isEmpty)
    log.record(TextEditingDiagnostics(pageKind: .image))
    log.record(TextEditingDiagnostics(pageKind: .unreadable))
    #expect(log.summary().first == "Text editing page: unreadable")
  }
}
