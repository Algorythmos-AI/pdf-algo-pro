import Core
import CoreTransferable
import UniformTypeIdentifiers

/// Extracted fields as a `.csv` file to share or save to Files (plan item H2).
nonisolated struct CSVFile: Transferable {
  let data: Data
  let name: String

  /// Creates the file; `name` is its name without the extension, and `notice`, the generated-text
  /// footer, is its last row (EU AI Act Art 50(2), plan item L3).
  init(_ extraction: Extraction, name: String, notice: String, locale: Locale = .current) {
    data = extraction.csvFile(locale: locale, notice: notice)
    self.name = name + ".csv"
  }

  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation(exportedContentType: .commaSeparatedText) { $0.data }
      .suggestedFileName { $0.name }
  }
}
