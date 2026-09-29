import Core
import DesignSystem
import SwiftUI

/// The tag editor's state: a document's tags, and the tags in use elsewhere to suggest (F7a, FR-LIB-002).
///
/// Tags are trimmed, and a tag that differs from one already there only by case is not added twice.
struct TagEditing: Equatable {
  /// The document's tags, sorted.
  private(set) var tags: [String]
  /// Tags on other documents.
  let available: [String]
  /// The tag being typed.
  var draft = ""

  init(tags: [String], available: [String]) {
    self.tags = Document.normalizedTags(tags)
    self.available = Document.normalizedTags(available)
  }

  /// Tags in use elsewhere that the document does not have, narrowed by what is being typed.
  var suggestions: [String] {
    let typed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    return available.filter { tag in
      !tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame }
        && (typed.isEmpty || tag.localizedStandardContains(typed))
    }
  }

  /// Adds the typed tag and clears the field; nothing happens when it is blank.
  mutating func addDraft() {
    add(draft)
    draft = ""
  }

  /// Adds a tag.
  mutating func add(_ tag: String) {
    tags = Document.normalizedTags(tags + [tag])
  }

  /// Removes a tag.
  mutating func remove(_ tag: String) {
    tags.removeAll { $0 == tag }
  }
}

/// Edits one document's tags; Done saves them, Cancel leaves them as they were.
struct TagEditor: View {
  let title: String
  let onSave: ([String]) -> Void
  @State private var editing: TagEditing
  @Environment(\.dismiss) private var dismiss

  init(document: Document, available: [String], onSave: @escaping ([String]) -> Void) {
    title = document.title
    self.onSave = onSave
    _editing = State(initialValue: TagEditing(tags: document.tags, available: available))
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          HStack {
            TextField(text: $editing.draft) { Text("Add a tag", bundle: .module) }
              .submitLabel(.done)
              .onSubmit { editing.addDraft() }
              .accessibilityIdentifier("tags.new")
            Button {
              editing.addDraft()
            } label: {
              Image(systemName: "plus.circle.fill").minimumTarget()
            }
            .accessibilityLabel(Text("Add", bundle: .module))
            .disabled(editing.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          }
          ForEach(editing.tags, id: \.self) { tag in
            Label(tag, systemImage: "tag")
          }
          .onDelete { offsets in
            for tag in offsets.map({ editing.tags[$0] }) { editing.remove(tag) }
          }
        } header: {
          Text("Tags", bundle: .module).foregroundStyle(Color.ds.labelSecondary)
        } footer: {
          if editing.tags.isEmpty {
            Text("No tags yet. Tags group documents in the sidebar.", bundle: .module)
              .foregroundStyle(Color.ds.labelSecondary)
          }
        }
        if !editing.suggestions.isEmpty {
          Section {
            ForEach(editing.suggestions, id: \.self) { tag in
              Button {
                editing.add(tag)
              } label: {
                Label(tag, systemImage: "plus")
              }
            }
          } header: {
            Text("In use", bundle: .module).foregroundStyle(Color.ds.labelSecondary)
          }
        }
      }
      .navigationTitle(title)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button {
            dismiss()
          } label: {
            Text("Cancel", bundle: .module)
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button {
            // Text typed but not yet added counts, so nothing typed is lost.
            editing.addDraft()
            onSave(editing.tags)
            dismiss()
          } label: {
            Text("Done", bundle: .module)
          }
          .accessibilityIdentifier("tags.done")
        }
      }
    }
  }
}
