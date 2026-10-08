import DesignSystem
import PDFEngine
import SwiftUI

/// A strip of small pages along the bottom of the reader, to move through a document with.
///
/// A tap on a small page shows that page, and the strip keeps the page in view in its middle.
/// PDFKit has a strip of its own (`PDFThumbnailView`); this one is the app's, so that each small
/// page is a labelled button and the pictures come from the same cache as the page grid.
struct PageStrip: View {
  let model: ReaderModel
  @State private var thumbnails = ThumbnailCache()

  /// The height the strip is laid out in.
  static let height: CGFloat = 64

  var body: some View {
    let count = model.controller?.pageCount ?? 0
    let current = model.controller?.currentPageIndex ?? 0
    ScrollViewReader { proxy in
      ScrollView(.horizontal) {
        LazyHStack(spacing: Spacing.s050) {
          ForEach(0..<count, id: \.self) { pageIndex in
            Button {
              model.controller?.goTo(pageIndex: pageIndex)
            } label: {
              StripPage(
                pageIndex: pageIndex, url: model.fileURL, version: model.document?.modifiedAt ?? .distantPast,
                cache: thumbnails, isCurrent: pageIndex == current)
            }
            .buttonStyle(.plain)
            // Not "Page 3": that is a page in the page grid, which can be open over the strip.
            .accessibilityLabel(Text("Go to page \(pageIndex + 1)", bundle: .module))
            .accessibilityAddTraits(pageIndex == current ? .isSelected : [])
            .accessibilityIdentifier("reader.pageStrip.\(pageIndex + 1)")
            .id(pageIndex)
          }
        }
        .padding(.horizontal, Spacing.s100)
      }
      .scrollIndicators(.hidden)
      // A few pages sit in the middle of the strip, not against its start.
      .defaultScrollAnchor(.center)
      .onChange(of: current) { _, page in
        withAnimation(.snappy) { proxy.scrollTo(page, anchor: .center) }
      }
      .onAppear { proxy.scrollTo(current, anchor: .center) }
    }
    .frame(height: Self.height)
    .frame(maxWidth: 560)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .accessibilityElement(children: .contain)
    .accessibilityLabel(Text("Page strip", bundle: .module))
    .accessibilityIdentifier("reader.pageStrip")
  }
}

/// One small page of the strip, in a cell large enough to tap.
private struct StripPage: View {
  let pageIndex: Int
  let url: URL?
  let version: Date
  let cache: ThumbnailCache
  let isCurrent: Bool
  @State private var image: CGImage?

  var body: some View {
    Group {
      if let image {
        Image(decorative: image, scale: 1).resizable().scaledToFit()
      } else {
        Color.ds.backgroundSecondary.aspectRatio(0.72, contentMode: .fit)
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 3, style: .continuous)
        .strokeBorder(isCurrent ? Color.ds.selection : Color.ds.separator, lineWidth: isCurrent ? 2 : 1)
    )
    .frame(height: isCurrent ? 52 : 44)
    .frame(minWidth: 44, minHeight: 56)
    .contentShape(Rectangle())
    // Keyed by the file's version too, so pages redraw after they are rotated, moved or deleted.
    .task(id: "\(url?.path ?? "")|\(version.timeIntervalSince1970)") {
      guard let url else { return }
      image = await cache.thumbnail(for: url, pageIndex: pageIndex, version: version, maximumPixelSize: 160)
    }
  }
}
