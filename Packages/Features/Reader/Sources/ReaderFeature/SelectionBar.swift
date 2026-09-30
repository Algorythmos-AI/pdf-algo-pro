import DesignSystem
import PDFEngine
import SwiftUI

/// The bar shown while an annotation is selected (F3): what it is, and what can be done with it.
struct SelectionBar: View {
  let selection: AnnotationSelection
  let onEdit: () -> Void
  let onDelete: () -> Void
  let onDone: () -> Void

  var body: some View {
    HStack(spacing: Spacing.s150) {
      Self.title(for: selection.kind).font(.subheadline.weight(.semibold))
      Spacer(minLength: Spacing.s100)
      if selection.isTextEditable {
        Button(action: onEdit) { Text("Edit text", bundle: .module).minimumTarget() }
          .accessibilityIdentifier("reader.selection.edit")
      }
      Button(role: .destructive, action: onDelete) { Text("Delete", bundle: .module).minimumTarget() }
        .accessibilityIdentifier("reader.selection.delete")
      Button(action: onDone) { Text("Done", bundle: .module).minimumTarget() }
        .accessibilityIdentifier("reader.selection.done")
    }
    .padding(Spacing.s150)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("reader.selection.actionBar")
  }

  static func title(for kind: AnnotationSelection.Kind) -> Text {
    switch kind {
    case .highlight: Text("Highlight", bundle: .module)
    case .underline: Text("Underline", bundle: .module)
    case .strikeThrough: Text("Strike-through", bundle: .module)
    case .note: Text("Note", bundle: .module)
    case .ink: Text("Drawing", bundle: .module)
    case .rectangle: Text("Rectangle", bundle: .module)
    case .oval: Text("Oval", bundle: .module)
    case .line: Text("Line", bundle: .module)
    case .textBox: Text("Text box", bundle: .module)
    case .stamp: Text("Stamp", bundle: .module)
    case .other: Text("Annotation", bundle: .module)
    }
  }
}
