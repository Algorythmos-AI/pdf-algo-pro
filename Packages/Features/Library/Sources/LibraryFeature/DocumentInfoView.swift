import Core
import DesignSystem
import PDFEngine
import SwiftUI

/// Everything known about a document: the library's record and what the file says about itself
/// (FR-LIB-008).
struct DocumentInfoView: View {
  let document: Document
  let details: DocumentDetails?
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section {
          row(Text("Title", bundle: .module), document.title)
          row(Text("File name", bundle: .module), document.fileName)
          if let size = details?.fileSize {
            row(Text("Size", bundle: .module), size.formatted(.byteCount(style: .file)))
          }
          if let details, details.pageCount > 0 {
            row(Text("Pages", bundle: .module), details.pageCount.formatted())
          }
        }
        Section {
          row(Text("Added", bundle: .module), document.addedAt.formatted(date: .abbreviated, time: .shortened))
          if document.modifiedAt > document.addedAt {
            row(Text("Changed", bundle: .module), document.modifiedAt.formatted(date: .abbreviated, time: .shortened))
          }
          if let opened = document.lastOpenedAt {
            row(Text("Last opened", bundle: .module), opened.formatted(date: .abbreviated, time: .shortened))
          }
        } header: {
          Text("In your library", bundle: .module).foregroundStyle(Color.ds.labelSecondary)
        }
        if let details {
          Section {
            if let author = details.author { row(Text("Author", bundle: .module), author) }
            if let created = details.created {
              row(Text("Created", bundle: .module), created.formatted(date: .abbreviated, time: .shortened))
            }
            if let modified = details.modified {
              row(Text("Modified", bundle: .module), modified.formatted(date: .abbreviated, time: .shortened))
            }
            if let creator = details.creator { row(Text("Made with", bundle: .module), creator) }
            if let producer = details.producer { row(Text("PDF made by", bundle: .module), producer) }
            row(Text("PDF version", bundle: .module), details.version)
          } header: {
            Text("From the file", bundle: .module).foregroundStyle(Color.ds.labelSecondary)
          }
          Section {
            row(
              Text("Password", bundle: .module),
              details.isEncrypted
                ? String(localized: "Protected", bundle: .module) : String(localized: "None", bundle: .module))
            row(Text("Printing", bundle: .module), Self.permission(details.allowsPrinting))
            row(Text("Copying text", bundle: .module), Self.permission(details.allowsCopying))
          } header: {
            Text("Protection", bundle: .module).foregroundStyle(Color.ds.labelSecondary)
          }
        }
      }
      .navigationTitle(Text("Info", bundle: .module))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button {
            dismiss()
          } label: {
            Text("Done", bundle: .module)
          }
        }
      }
    }
    .accessibilityIdentifier("library.info")
  }

  private func row(_ label: Text, _ value: String) -> some View {
    LabeledContent {
      Text(value).textSelection(.enabled).multilineTextAlignment(.trailing)
    } label: {
      label
    }
  }

  static func permission(_ allowed: Bool) -> String {
    allowed ? String(localized: "Allowed", bundle: .module) : String(localized: "Not allowed", bundle: .module)
  }
}
