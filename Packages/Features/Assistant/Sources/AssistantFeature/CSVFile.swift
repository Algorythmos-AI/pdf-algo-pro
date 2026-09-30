import Core
import CoreTransferable
import UniformTypeIdentifiers

/// Extracted fields as a `.csv` file to share or save to Files (plan item H2).
nonisolated struct CSVFile: Transferable {
  let data: Data
  let name: String

  /// Creates the file; `name` is its name without the extension.
  init(_ extraction: Extraction, name: String, locale: Locale = .current) {
    data = extraction.csvFile(locale: locale)
    self.name = name + ".csv"
  }

  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation(exportedContentType: .commaSeparatedText) { $0.data }
      .suggestedFileName { $0.name }
  }
}
