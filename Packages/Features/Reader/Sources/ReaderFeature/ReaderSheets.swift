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

/// The page grid in its own navigation stack, with a Done button and, where the author allows it,
/// Select for organising pages (FR-ORG-001).
struct PageGridSheet: View {
  let model: ReaderModel
  @State private var isSelecting = false
  @State private var selection: IndexSet = []

  var body: some View {
    NavigationStack {
      PageGrid(model: model, isSelecting: isSelecting, selection: $selection)
        .navigationTitle(
          isSelecting && !selection.isEmpty
            ? Text("\(selection.count) selected", bundle: .module) : Text("Pages", bundle: .module)
        )
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button {
              model.showsPages = false
            } label: {
              Text("Done", bundle: .module)
            }
          }
          if model.allowsOrganizing {
            ToolbarItem(placement: .topBarLeading) {
              Button {
                isSelecting.toggle()
                selection = []
              } label: {
                isSelecting ? Text("Cancel", bundle: .module) : Text("Select", bundle: .module)
              }
              .accessibilityIdentifier("pages.select")
            }
          }
          if isSelecting {
            ToolbarItemGroup(placement: .bottomBar) { actions }
          }
        }
    }
  }

  @ViewBuilder private var actions: some View {
    let none = selection.isEmpty
    Button {
      Task { await model.rotatePages(selection, clockwise: false) }
    } label: {
      Label {
        Text("Rotate left", bundle: .module)
      } icon: {
        Image(systemName: "rotate.left")
      }
    }
    .disabled(none)
    Button {
      Task { await model.rotatePages(selection, clockwise: true) }
    } label: {
      Label {
        Text("Rotate right", bundle: .module)
      } icon: {
        Image(systemName: "rotate.right")
      }
    }
    .disabled(none)
    Button {
      move(earlier: true)
    } label: {
      Label {
        Text("Move earlier", bundle: .module)
      } icon: {
        Image(systemName: "arrow.left")
      }
    }
    .disabled(selection.count != 1 || selection.first == 0)
    Button {
      move(earlier: false)
    } label: {
      Label {
        Text("Move later", bundle: .module)
      } icon: {
        Image(systemName: "arrow.right")
      }
    }
    .disabled(selection.count != 1 || selection.first == (model.controller?.pageCount ?? 1) - 1)
    Menu {
      Button {
        Task { await model.extractPages(selection) }
      } label: {
        Label {
          Text("Copy to a new document", bundle: .module)
        } icon: {
          Image(systemName: "doc.on.doc")
        }
      }
      Button(role: .destructive) {
        let pages = selection
        selection = []
        Task { await model.deletePages(pages) }
      } label: {
        Label {
          Text("Delete pages", bundle: .module)
        } icon: {
          Image(systemName: "trash")
        }
      }
    } label: {
      Label {
        Text("More", bundle: .module)
      } icon: {
        Image(systemName: "ellipsis.circle")
      }
    }
    .disabled(none)
    .accessibilityIdentifier("pages.more")
  }

  private func move(earlier: Bool) {
    guard let page = selection.first else { return }
    Task {
      if let moved = await model.movePage(page, earlier: earlier) { selection = [moved] }
    }
  }
}

/// A grid of page thumbnails: tapping one jumps to it (FR-READ-002), or, while selecting, selects it.
struct PageGrid: View {
  let model: ReaderModel
  var isSelecting = false
  @Binding var selection: IndexSet
  private let thumbnails = ThumbnailCache()

  init(model: ReaderModel, isSelecting: Bool = false, selection: Binding<IndexSet> = .constant([])) {
    self.model = model
    self.isSelecting = isSelecting
    _selection = selection
  }

  var body: some View {
    ScrollView {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: Spacing.s200)], spacing: Spacing.s200) {
        ForEach(0..<(model.controller?.pageCount ?? 0), id: \.self) { pageIndex in
          let isSelected = selection.contains(pageIndex)
          Button {
            if isSelecting {
              if isSelected { selection.remove(pageIndex) } else { selection.insert(pageIndex) }
            } else {
              model.openAfterClosingSheets(pageIndex: pageIndex)
            }
          } label: {
            PageThumbnail(
              pageIndex: pageIndex, url: model.fileURL, version: model.document?.modifiedAt ?? .distantPast,
              cache: thumbnails,
              isCurrent: isSelecting ? isSelected : model.controller?.currentPageIndex == pageIndex
            )
            .overlay(alignment: .topTrailing) {
              if isSelecting {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                  .font(.title3).foregroundStyle(isSelected ? Color.ds.brandTint : Color.ds.labelSecondary)
                  .background(Circle().fill(Color.ds.backgroundPrimary))
                  .padding(Spacing.s050)
                  .accessibilityHidden(true)
              }
            }
          }
          .buttonStyle(.plain)
          .accessibilityLabel(Text("Page \(pageIndex + 1)", bundle: .module))
          .accessibilityAddTraits(isSelecting && isSelected ? .isSelected : [])
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
      .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
      // Every page has an edge and a soft shadow, so a white page reads as a page on a white sheet.
      .overlay(
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .strokeBorder(isCurrent ? Color.ds.brandTint : Color.ds.separator, lineWidth: isCurrent ? 2 : 1)
      )
      .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
      .frame(height: 128)
      Text("\(pageIndex + 1)").font(.caption.monospacedDigit())
        .foregroundStyle(isCurrent ? Color.ds.brandTint : Color.ds.labelSecondary)
    }
    // Keyed by the file's version too, so pages redraw after they are rotated, moved or deleted.
    .task(id: "\(url?.path ?? "")|\(version.timeIntervalSince1970)") {
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
