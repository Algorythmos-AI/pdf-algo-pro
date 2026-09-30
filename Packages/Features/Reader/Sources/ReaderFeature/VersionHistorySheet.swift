import Core
import DesignSystem
import SwiftUI

/// A document's earlier versions, kept for 30 days by each save; any can be put back (FR-EDIT-008).
struct VersionHistorySheet: View {
  let model: ReaderModel
  @State private var confirming: DocumentVersion?

  var body: some View {
    NavigationStack {
      List {
        Section {
          ForEach(model.versions) { version in
            Button {
              confirming = version
            } label: {
              LabeledContent {
                Text(version.size.formatted(.byteCount(style: .file))).foregroundStyle(Color.ds.labelSecondary)
              } label: {
                Text(version.savedAt.formatted(date: .abbreviated, time: .shortened))
              }
            }
          }
        } footer: {
          Text(
            "Each save keeps the version before it for 30 days. Restoring one keeps the current version too, so you can switch back.",
            bundle: .module
          )
          .foregroundStyle(Color.ds.labelSecondary)
        }
      }
      .navigationTitle(Text("Version history", bundle: .module))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button {
            model.showsVersions = false
          } label: {
            Text("Done", bundle: .module)
          }
        }
      }
      .confirmationDialog(
        Text("Restore this version?", bundle: .module),
        isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }),
        titleVisibility: .visible, presenting: confirming
      ) { version in
        Button {
          Task { await model.restore(version) }
        } label: {
          Text("Restore", bundle: .module)
        }
      } message: { _ in
        Text("Changes since then are replaced. The current version is kept in the history.", bundle: .module)
      }
      .task { await model.loadVersions() }
    }
  }
}
