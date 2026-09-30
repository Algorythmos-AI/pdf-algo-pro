import DesignSystem
import PDFEngine
import SwiftUI
import UIKit

/// The table of contents; choosing an entry jumps to its page (FR-READ-002).
struct OutlineSheet: View {
  let model: ReaderModel

  var body: some View {
    NavigationStack {
      Group {
        let items = model.controller?.outline ?? []
        if items.isEmpty {
          EmptyState(Text("No table of contents", bundle: .module), systemImage: "list.bullet.indent") {
            Text("This document doesn't include one. Use Pages to jump to a page.", bundle: .module)
          }
        } else {
          List(items) { item in
            Button {
              model.openAfterClosingSheets(pageIndex: item.pageIndex)
            } label: {
              HStack {
                Text(item.title).padding(.leading, CGFloat(item.depth) * Spacing.s200)
                Spacer()
                Text("\(item.pageIndex + 1)").foregroundStyle(Color.ds.labelSecondary).monospacedDigit()
              }
            }
          }
        }
      }
      .navigationTitle(Text("Contents", bundle: .module))
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button {
            model.showsOutline = false
          } label: {
            Text("Done", bundle: .module)
          }
        }
      }
    }
  }
}

/// The page grid in its own navigation stack, with a Done button.
struct PageGridSheet: View {
  let model: ReaderModel

  var body: some View {
    NavigationStack {
      PageGrid(model: model)
        .navigationTitle(Text("Pages", bundle: .module))
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button {
              model.showsPages = false
            } label: {
              Text("Done", bundle: .module)
            }
          }
        }
    }
  }
}

/// A grid of page thumbnails; tapping one jumps to it (FR-READ-002).
struct PageGrid: View {
  let model: ReaderModel
  private let thumbnails = ThumbnailCache()

  var body: some View {
    ScrollView {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: Spacing.s200)], spacing: Spacing.s200) {
        ForEach(0..<(model.controller?.pageCount ?? 0), id: \.self) { pageIndex in
          Button {
            model.openAfterClosingSheets(pageIndex: pageIndex)
          } label: {
            PageThumbnail(
              pageIndex: pageIndex, url: model.fileURL, version: model.document?.modifiedAt ?? .distantPast,
              cache: thumbnails,
              isCurrent: model.controller?.currentPageIndex == pageIndex)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(Text("Page \(pageIndex + 1)", bundle: .module))
        }
      }
      .padding(Spacing.s200)
    }
  }
}

private struct PageThumbnail: View {
  let pageIndex: Int
  let url: URL?
  let version: Date
  let cache: ThumbnailCache
  let isCurrent: Bool
  @State private var image: CGImage?

  var body: some View {
    VStack(spacing: Spacing.s050) {
      Group {
        if let image {
          Image(decorative: image, scale: 1).resizable().scaledToFit()
        } else {
          Color.ds.backgroundSecondary
        }
      }
      .frame(height: 128)
      .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(isCurrent ? Color.ds.brandTint : .clear, lineWidth: 2))
      Text("\(pageIndex + 1)").font(.caption.monospacedDigit())
    }
    .task(id: url) {
      guard let url else { return }
      image = await cache.thumbnail(for: url, pageIndex: pageIndex, version: version, maximumPixelSize: 256)
    }
  }
}

/// The system share sheet for a saved document; Print is left out when the author does not allow it.
struct ShareSheet: UIViewControllerRepresentable {
  let file: SharedFile

  func makeUIViewController(context: Context) -> UIActivityViewController {
    let controller = UIActivityViewController(activityItems: [file.url], applicationActivities: nil)
    if !file.allowsPrinting { controller.excludedActivityTypes = [.print] }
    return controller
  }

  func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
