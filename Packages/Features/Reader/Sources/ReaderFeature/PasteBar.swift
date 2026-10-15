import DesignSystem
import SwiftUI

/// The bar shown after Copy or Cut, while each tap on a page pastes what was copied.
struct PasteBar: View {
  let onPasteHere: () -> Void
  let onDone: () -> Void

  var body: some View {
    HStack(spacing: Spacing.s150) {
      Label {
        Text("Tap where to paste", bundle: .module)
      } icon: {
        Image(systemName: "doc.on.clipboard")
      }
      .font(.subheadline.weight(.semibold))
      // A tap on the page is not open to VoiceOver or Switch Control; this pastes on the page on screen.
      .accessibilityAction(named: Text("Paste on this page", bundle: .module), onPasteHere)
      Spacer(minLength: Spacing.s100)
      Button(action: onDone) { Text("Done", bundle: .module).minimumTarget() }
        .accessibilityIdentifier("reader.paste.done")
    }
    .tint(Color.ds.labelPrimary)
    .padding(Spacing.s150)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("reader.paste.bar")
  }
}
