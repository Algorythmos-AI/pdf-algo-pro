import PDFEngine
import SwiftUI
import UIKit

/// Asks before a link in a document opens, showing its full address (threat T-02).
///
/// Links the app never opens (files, other apps, scripts) say so instead, and can still be copied.
struct LinkConfirmation: ViewModifier {
  let controller: PDFDocumentController?
  @Environment(\.openURL) private var openURL

  func body(content: Content) -> some View {
    let link = controller?.tappedLink
    let isPresented = Binding(get: { link != nil }, set: { if !$0 { controller?.dismissLink() } })
    content
      .confirmationDialog(
        Text("Open this link?", bundle: .module), isPresented: isPresented, titleVisibility: .visible,
        presenting: link
      ) { link in
        if link.isOpenable {
          Button {
            controller?.dismissLink()
            openURL(link.url)
          } label: {
            Text("Open link", bundle: .module)
          }
        }
        Button {
          UIPasteboard.general.string = link.address
          controller?.dismissLink()
        } label: {
          Text("Copy link", bundle: .module)
        }
        Button(role: .cancel) {
          controller?.dismissLink()
        } label: {
          Text("Cancel", bundle: .module)
        }
      } message: { link in
        if link.isOpenable {
          Text(link.address)
        } else {
          Text(
            "This link goes to a file or another app, so it can't be opened from a document: \(link.address)",
            bundle: .module)
        }
      }
  }
}
