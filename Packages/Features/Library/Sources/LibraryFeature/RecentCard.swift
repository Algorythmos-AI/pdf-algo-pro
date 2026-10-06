import Core
import CoreGraphics
import DesignSystem
import SwiftUI

/// One recently opened document on Home: its first page over its title.
struct RecentCard: View {
  let document: Document
  let thumbnail: () async -> CGImage?
  @State private var image: CGImage?
  @ScaledMetric(relativeTo: .footnote) private var width: CGFloat = 104

  var body: some View {
    // The page grows with the text size, but two cards still fit on a small iPhone.
    let width = min(width, 150)
    let page = RoundedRectangle(cornerRadius: 8, style: .continuous)
    VStack(alignment: .leading, spacing: Spacing.s100) {
      Group {
        if let image {
          Image(decorative: image, scale: 1).resizable().scaledToFill()
        } else {
          Image(systemName: document.isEncrypted ? "lock.doc" : "doc.text")
            .font(.title)
            .foregroundStyle(Color.ds.labelTertiary)
        }
      }
      .frame(width: width, height: width * 1.3)
      .background(Color.ds.backgroundGroupedElevated, in: page)
      .clipShape(page)
      // An edge and a soft shadow, as in the document list, so a white page reads as a page.
      .overlay(page.strokeBorder(Color.ds.separator, lineWidth: 1))
      .shadow(color: .black.opacity(0.10), radius: 3, y: 1)
      Text(document.title)
        .font(.footnote.weight(.medium))
        .foregroundStyle(Color.ds.labelPrimary)
        .multilineTextAlignment(.leading)
        .lineLimit(2, reservesSpace: true)
    }
    .frame(width: width, alignment: .leading)
    .contentShape(Rectangle())
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(document.title))
    .accessibilityAddTraits(.isButton)
    .task(id: document.modifiedAt) { image = await thumbnail() }
  }
}

/// A button that only dims while pressed.
///
/// Home puts several buttons in one list row; a plain or default style there makes a tap on the row
/// press all of them, and a style of its own keeps each button to itself.
struct DimmingButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
  }
}
