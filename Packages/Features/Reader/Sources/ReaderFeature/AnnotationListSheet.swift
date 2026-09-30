import DesignSystem
import PDFEngine
import SwiftUI

/// Every annotation in the document, by page; choosing one opens its page, and the list can be shared
/// as text (FR-ANN-003).
struct AnnotationListSheet: View {
  let model: ReaderModel

  var body: some View {
    NavigationStack {
      Group {
        let summaries = model.annotationSummaries
        if summaries.isEmpty {
          EmptyState(Text("No annotations yet", bundle: .module), systemImage: "highlighter") {
            Text("Highlights, notes, drawings and signatures you add appear here.", bundle: .module)
          }
        } else {
          List {
            ForEach(Dictionary(grouping: summaries, by: \.pageIndex).sorted { $0.key < $1.key }, id: \.key) {
              page, items in
              Section {
                ForEach(items) { summary in
                  Button {
                    model.openAfterClosingSheets(pageIndex: summary.pageIndex)
                  } label: {
                    VStack(alignment: .leading, spacing: Spacing.s050) {
                      Text(ReaderModel.name(of: summary)).font(.subheadline.weight(.semibold))
                      if let text = summary.text {
                        Text(text).lineLimit(3).foregroundStyle(Color.ds.labelSecondary)
                      }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                  }
                  .buttonStyle(.plain)
                }
              } header: {
                Text("Page \(page + 1)", bundle: .module)
              }
            }
          }
          .accessibilityIdentifier("reader.annotations.list")
        }
      }
      .navigationTitle(Text("Annotations", bundle: .module))
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button {
            model.showsAnnotations = false
          } label: {
            Text("Done", bundle: .module)
          }
        }
        if !model.annotationSummaries.isEmpty {
          ToolbarItem(placement: .primaryAction) {
            ShareLink(item: model.annotationsText()) {
              Label {
                Text("Share as text", bundle: .module)
              } icon: {
                Image(systemName: "square.and.arrow.up")
              }
            }
            .accessibilityIdentifier("reader.annotations.share")
          }
        }
      }
    }
  }
}
