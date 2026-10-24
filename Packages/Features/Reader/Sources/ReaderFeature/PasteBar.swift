import AccessibilityIDs
import DesignSystem
import SwiftUI

/// The bar shown after Copy or Cut, while each tap on a page pastes what was copied.
struct PasteBar: View {
  let onPasteHere: () -> Void
  let onDone: () -> Void
  var canUndo = false
  var canRedo = false
  var onUndo: () -> Void = {}
  var onRedo: () -> Void = {}

  var body: some View {
    HStack(spacing: Spacing.s150) {
      Label {
        Text("Tap where to paste", bundle: .module)
      } icon: {
        Image(systemName: "doc.on.clipboard")
      }
      .font(.subheadline.weight(.semibold))
      // With Undo and Redo beside it, the words wrap onto more lines rather than being cut off.
      .fixedSize(horizontal: false, vertical: true)
      .layoutPriority(1)
      // It carries an action, so it gets a full-size target like any control (the audit's rule).
      .minimumTarget()
      // A tap on the page is not open to VoiceOver or Switch Control; this pastes on the page on screen.
      .accessibilityAction(named: Text("Paste on this page", bundle: .module), onPasteHere)
      Spacer(minLength: Spacing.s100)
      // A paste in the wrong place is taken back here, without leaving pasting.
      Button(action: onUndo) {
        Image(systemName: "arrow.uturn.backward").minimumTarget()
      }
      .disabled(!canUndo)
      .accessibilityLabel(Text("Undo", bundle: .module))
      .accessibilityIdentifier(AccessibilityID.Reader.Paste.undo)
      Button(action: onRedo) {
        Image(systemName: "arrow.uturn.forward").minimumTarget()
      }
      .disabled(!canRedo)
      .accessibilityLabel(Text("Redo", bundle: .module))
      .accessibilityIdentifier(AccessibilityID.Reader.Paste.redo)
      Button(action: onDone) { Text("Done", bundle: .module).minimumTarget() }
        .accessibilityIdentifier(AccessibilityID.Reader.Paste.done)
    }
    .tint(Color.ds.labelPrimary)
    .padding(Spacing.s150)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier(AccessibilityID.Reader.Paste.bar)
  }
}
