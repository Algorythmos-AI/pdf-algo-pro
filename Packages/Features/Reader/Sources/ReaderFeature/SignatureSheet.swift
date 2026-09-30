import Core
import DesignSystem
import SwiftUI

/// Signing (F1c, FR-EDIT-004): place a saved signature, draw and save a new one, or type a name.
///
/// Signatures are kept in the Keychain on this device only; the sheet never shows where they are
/// stored, only what they look like.
struct SignatureSheet: View {
  let model: ReaderModel
  @State private var strokes: [[CGPoint]] = []
  @State private var typedName = ""
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        if !model.savedSignatures.isEmpty {
          Section {
            ForEach(model.savedSignatures) { signature in
              Button {
                place { await model.place(signature) }
              } label: {
                SignaturePreview(signature: signature).frame(height: 64)
              }
              .accessibilityLabel(
                Text(
                  "Saved signature from \(signature.createdAt.formatted(date: .abbreviated, time: .omitted))",
                  bundle: .module)
              )
              .accessibilityHint(Text("Places it on this page", bundle: .module))
            }
            .onDelete { offsets in
              let ids = offsets.map { model.savedSignatures[$0].id }
              Task { for id in ids { await model.deleteSignature(id) } }
            }
          } header: {
            Text("Saved on this device", bundle: .module).foregroundStyle(Color.ds.labelSecondary)
          }
        }
        Section {
          SignaturePad(strokes: $strokes).frame(height: 180)
          HStack {
            Button {
              strokes = []
            } label: {
              Text("Clear", bundle: .module).readableWhenDisabled()
            }
            .disabled(strokes.isEmpty)
            Spacer()
            Button {
              place {
                if let signature = await model.saveSignature(drawn: strokes) { await model.place(signature) }
              }
            } label: {
              Text("Save and place", bundle: .module).readableWhenDisabled()
            }
            .disabled(strokes.isEmpty)
            .accessibilityIdentifier("signature.savePlace")
          }
          .buttonStyle(.borderless)
        } header: {
          Text("Draw a new signature", bundle: .module).foregroundStyle(Color.ds.labelSecondary)
        }
        Section {
          TextField(text: $typedName) { Text("Your name", bundle: .module) }
            .textContentType(.name)
            .submitLabel(.done)
            .accessibilityIdentifier("signature.typedName")
          Button {
            place { await model.placeTyped(typedName) }
          } label: {
            Text("Place typed signature", bundle: .module).readableWhenDisabled()
          }
          .disabled(typedName.trimmingCharacters(in: .whitespaces).isEmpty)
          .accessibilityIdentifier("signature.placeTyped")
        } header: {
          Text("Or type your name", bundle: .module).foregroundStyle(Color.ds.labelSecondary)
        }
      }
      .navigationTitle(Text("Signature", bundle: .module))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button {
            dismiss()
          } label: {
            Text("Cancel", bundle: .module)
          }
        }
      }
      .task { await model.loadSignatures() }
    }
  }

  /// Runs a placing action, then closes the sheet so the signature is visible on the page.
  private func place(_ action: @escaping () async -> Void) {
    Task {
      await action()
      dismiss()
    }
  }
}

/// A drawing pad for a new signature: each drag is a stroke, drawn as it goes.
struct SignaturePad: View {
  @Binding var strokes: [[CGPoint]]
  @State private var current: [CGPoint] = []

  var body: some View {
    Canvas { context, _ in
      for stroke in strokes + [current] where stroke.count > 1 {
        var path = Path()
        path.addLines(stroke)
        context.stroke(
          path, with: .color(Color.ds.brandTint), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
      }
    }
    .background(Color.ds.backgroundSecondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .gesture(
      DragGesture(minimumDistance: 0)
        .onChanged { current.append($0.location) }
        .onEnded { _ in
          if current.count > 1 { strokes.append(current) }
          current = []
        }
    )
    .accessibilityElement()
    .accessibilityLabel(Text("Signature pad", bundle: .module))
    .accessibilityHint(
      Text("Draw your signature with a finger or Apple Pencil, or type your name below", bundle: .module)
    )
    .accessibilityAddTraits(.allowsDirectInteraction)
    .accessibilityIdentifier("signature.pad")
  }
}

/// A saved signature drawn to fit its space, keeping its shape.
struct SignaturePreview: View {
  let signature: SavedSignature

  var body: some View {
    Canvas { context, size in
      let ratio = CGFloat(signature.aspectRatio)
      let width = min(size.width, size.height * ratio)
      let height = width / ratio
      let origin = CGPoint(x: (size.width - width) / 2, y: (size.height - height) / 2)
      for stroke in signature.strokes where stroke.count > 1 {
        var path = Path()
        path.addLines(
          stroke.map { CGPoint(x: origin.x + CGFloat($0.x) * width, y: origin.y + CGFloat($0.y) * height) })
        context.stroke(
          path, with: .color(.primary), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
      }
    }
  }
}
