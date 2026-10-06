import Core
import CoreGraphics
import DesignSystem
import SwiftUI

/// One document in the library list: thumbnail, title, details and an optional search snippet.
struct DocumentRow: View {
  let document: Document
  let snippet: String?
  let thumbnail: () async -> CGImage?
  /// The most lines the title takes; `nil` on Home, where a title is never cut short.
  var titleLineLimit: Int? = 2
  @State private var image: CGImage?
  @ScaledMetric(relativeTo: .body) private var thumbnailHeight: CGFloat = 64

  var body: some View {
    HStack(spacing: Spacing.s150) {
      Group {
        if let image {
          Image(decorative: image, scale: 1).resizable().scaledToFit()
        } else {
          Image(systemName: document.isEncrypted ? "lock.doc" : "doc.text")
            .font(.title2)
            .foregroundStyle(Color.ds.labelTertiary)
        }
      }
      .frame(width: thumbnailHeight * 0.78, height: thumbnailHeight)
      .background(Color.ds.backgroundSecondary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
      .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
      // An edge and a soft shadow, so a white first page reads as a page on a white list.
      .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.ds.separator, lineWidth: 1))
      .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
      .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: Spacing.s050) {
        HStack(spacing: Spacing.s050) {
          Text(document.title).font(.headline).lineLimit(titleLineLimit)
          if document.isFavorite {
            Image(systemName: "star.fill").font(.caption).foregroundStyle(Color.ds.brandTint)
              .accessibilityLabel(Text("Favourite", bundle: .module))
          }
        }
        details.font(.subheadline).foregroundStyle(Color.ds.labelSecondary)
        if let snippet {
          Text(snippet).font(.footnote).foregroundStyle(Color.ds.labelSecondary).lineLimit(2)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, Spacing.s050)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .task(id: document.modifiedAt) { image = await thumbnail() }
  }

  private var details: Text {
    let date = Text(document.lastOpenedAt ?? document.addedAt, format: .dateTime.day().month().year())
    if document.isEncrypted {
      return Text("Password protected · \(date)", bundle: .module)
    }
    if document.pageCount > 0 {
      return Text("\(document.pageCount) pages · \(date)", bundle: .module)
    }
    return date
  }
}
