import Core
import DesignSystem
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The library: a split view with sections, the document list and the open document (ADR-0004).
///
/// On iPhone it collapses to a stack; layouts follow size, never device type.
public struct LibraryView<Detail: View>: View {
  @State private var model: LibraryModel
  @State private var columns = NavigationSplitViewVisibility.automatic
  @State private var compactColumn = NavigationSplitViewColumn.content
  @Environment(\.horizontalSizeClass) private var sizeClass
  @State private var isPickingFiles = false
  @State private var isPickingPhotos = false
  @State private var photos: [PhotosPickerItem] = []
  /// The assistant task to start on a single imported file: set by the home screen's primary action.
  @State private var importTask: AssistantTask?
  @State private var renaming: Document?
  @State private var tagging: Document?
  @State private var confirmingPermanentDelete: Document?
  @State private var newTitle = ""
  private let onScan: () -> Void
  private let onSettings: () -> Void
  private let detail: (DocumentSelection) -> Detail

  /// Creates the library.
  ///
  /// - Parameters:
  ///   - model: The library model.
  ///   - onScan: Starts the scanner.
  ///   - onSettings: Opens Settings.
  ///   - detail: The view for the selected document, supplied by the app so features stay independent.
  public init(
    model: LibraryModel, onScan: @escaping () -> Void, onSettings: @escaping () -> Void,
    @ViewBuilder detail: @escaping (DocumentSelection) -> Detail
  ) {
    _model = State(initialValue: model)
    _compactColumn = State(initialValue: model.selection == nil ? .content : .detail)
    self.onScan = onScan
    self.onSettings = onSettings
    self.detail = detail
  }

  /// The library.
  public var body: some View {
    NavigationSplitView(columnVisibility: $columns, preferredCompactColumn: $compactColumn) {
      sidebar
    } content: {
      content
    } detail: {
      if let selection = model.selection {
        detail(selection).id(selection)
      } else {
        EmptyState(Text("No document selected", bundle: .module), systemImage: "doc.text") {
          Text("Choose a document from the library.", bundle: .module)
        }
      }
    }
    .sheet(item: $tagging) { document in
      TagEditor(document: document, available: model.tags) { tags in
        Task { await model.setTags(tags, for: document.id) }
      }
    }
    .photosPicker(isPresented: $isPickingPhotos, selection: $photos, matching: .images)
    .onChange(of: photos) { _, items in
      guard !items.isEmpty else { return }
      photos = []
      Task {
        var data: [Data] = []
        for item in items {
          if let photo = try? await item.loadTransferable(type: Data.self) { data.append(photo) }
        }
        await model.addPhotos(data)
      }
    }
    .fileImporter(isPresented: $isPickingFiles, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
      if case .success(let urls) = result { Task { await model.importFiles(urls, task: importTask) } }
    }
    .alert(
      Text("Something went wrong", bundle: .module),
      isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })
    ) {
      Button {
        model.errorMessage = nil
      } label: {
        Text("OK", bundle: .module)
      }
    } message: {
      Text(model.errorMessage ?? "")
    }
    .alert(
      Text("Rename document", bundle: .module),
      isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    ) {
      TextField(text: $newTitle) { Text("Name", bundle: .module) }
      Button {
        if let document = renaming { Task { await model.rename(document.id, to: newTitle) } }
        renaming = nil
      } label: {
        Text("Rename", bundle: .module)
      }
      Button(role: .cancel) {
        renaming = nil
      } label: {
        Text("Cancel", bundle: .module)
      }
    }
    .confirmationDialog(
      Text("Delete permanently?", bundle: .module),
      isPresented: Binding(
        get: { confirmingPermanentDelete != nil }, set: { if !$0 { confirmingPermanentDelete = nil } }),
      titleVisibility: .visible,
      presenting: confirmingPermanentDelete
    ) { document in
      Button(role: .destructive) {
        Task { await model.deletePermanently(document.id) }
      } label: {
        Text("Delete permanently", bundle: .module)
      }
    } message: { document in
      Text("\(document.title) will be removed from this device. This can't be undone.", bundle: .module)
    }
    .onChange(of: model.selection) { compactColumn = model.selection == nil ? .content : .detail }
    .task { await model.load() }
  }

  // MARK: - Sidebar

  private var sidebar: some View {
    List(
      selection: Binding(
        get: { model.section },
        set: { section in
          if let section { model.section = section }
          compactColumn = .content
        })
    ) {
      Section {
        ForEach(LibrarySection.fixed, id: \.self) { section in
          Label {
            Self.title(for: section)
          } icon: {
            Image(systemName: Self.symbol(for: section))
          }
          .tag(section)
          .accessibilityIdentifier("library.section.\(Self.identifier(for: section))")
        }
      }
      if !model.tags.isEmpty {
        Section {
          ForEach(model.tags, id: \.self) { tag in
            Label(tag, systemImage: "tag").tag(LibrarySection.tag(tag))
          }
        } header: {
          Text("Tags", bundle: .module)
        }
      }
    }
    .navigationTitle(Text("PDF Algo Pro", bundle: .module))
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button(action: onSettings) {
          Label {
            Text("Settings", bundle: .module)
          } icon: {
            Image(systemName: "gearshape")
          }
        }
        .accessibilityIdentifier("library.sidebar.settings")
      }
    }
  }

  // MARK: - Content

  private var content: some View {
    Group {
      if model.phase == .loading {
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if let results = model.results {
        searchResults(results)
      } else if model.documents.isEmpty {
        emptyState
      } else {
        documentList
      }
    }
    .navigationTitle(Self.title(for: model.section))
    .searchable(text: $model.query, prompt: Text("Titles, tags and text", bundle: .module))
    .task(id: model.query) {
      try? await Task.sleep(for: .milliseconds(200))
      await model.search()
    }
    .dropDestination(for: URL.self) { urls, _ in
      Task { await model.importFiles(urls.filter { $0.pathExtension.lowercased() == "pdf" }) }
      return !urls.isEmpty
    }
    .toolbar {
      if sizeClass == .compact {
        // On iPhone the sidebar is one step back, so Settings is also on the list's toolbar.
        ToolbarItem(placement: .topBarLeading) {
          Button(action: onSettings) {
            Label {
              Text("Settings", bundle: .module)
            } icon: {
              Image(systemName: "gearshape")
            }
          }
          .accessibilityIdentifier("library.settings")
        }
      }
      ToolbarItemGroup(placement: .primaryAction) {
        Menu {
          Picker(selection: $model.sort) {
            Text("Recently opened", bundle: .module).tag(LibrarySort.recentlyOpened)
            Text("Name", bundle: .module).tag(LibrarySort.title)
            Text("Date added", bundle: .module).tag(LibrarySort.dateAdded)
          } label: {
            Text("Sort by", bundle: .module)
          }
        } label: {
          Label {
            Text("Sort", bundle: .module)
          } icon: {
            Image(systemName: "arrow.up.arrow.down")
          }
        }
        Button(action: onScan) {
          Label {
            Text("Scan", bundle: .module)
          } icon: {
            Image(systemName: "doc.viewfinder")
          }
        }
        .accessibilityIdentifier("library.scan")
        // A tap chooses files, as before; holding it also offers a PDF from photos (FR-ORG-008).
        Menu {
          Button {
            pick(task: nil)
          } label: {
            Label {
              Text("Choose files", bundle: .module)
            } icon: {
              Image(systemName: "folder")
            }
          }
          Button {
            isPickingPhotos = true
          } label: {
            Label {
              Text("PDF from photos", bundle: .module)
            } icon: {
              Image(systemName: "photo.on.rectangle")
            }
          }
        } label: {
          Label {
            Text("Import", bundle: .module)
          } icon: {
            Image(systemName: "plus")
          }
        } primaryAction: {
          pick(task: nil)
        }
        .accessibilityIdentifier("library.import")
      }
    }
    .overlay(alignment: .bottom) {
      if model.isImporting {
        ProgressView { Text("Importing…", bundle: .module) }
          .padding(Spacing.s150)
          .background(.regularMaterial, in: Capsule())
          .padding(Spacing.s200)
      }
    }
  }

  private var documentList: some View {
    List {
      if model.showsPrimaryAction {
        primaryActionCard.listRowSeparator(.hidden)
      }
      ForEach(model.documents) { document in
        row(document, snippet: nil, pageIndex: nil)
      }
    }
    .listStyle(.plain)
    .accessibilityIdentifier("library.list")
  }

  private func searchResults(_ results: [SearchHit]) -> some View {
    Group {
      if model.isSearchUnavailable {
        EmptyState(Text("Search isn't available right now", bundle: .module), systemImage: "magnifyingglass") {
          Text("Your documents are safe. Try again in a moment.", bundle: .module)
        }
        .accessibilityIdentifier("library.search.unavailable")
      } else if results.isEmpty {
        ContentUnavailableView.search(text: model.query)
      } else {
        List(results) { hit in
          if let document = model.document(for: hit) {
            row(document, snippet: hit.snippet, pageIndex: hit.pageIndex)
          }
        }
        .listStyle(.plain)
      }
    }
  }

  private func row(_ document: Document, snippet: String?, pageIndex: Int?) -> some View {
    Button {
      model.open(document.id, pageIndex: pageIndex)
    } label: {
      DocumentRow(document: document, snippet: snippet, thumbnail: { await model.thumbnail(for: document) })
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("library.document.\(document.title)")
    // A full swipe moves a document to Recently Deleted; deleting for good always asks first.
    .swipeActions(edge: .trailing, allowsFullSwipe: !document.isDeleted) {
      if document.isDeleted {
        Button(role: .destructive) {
          confirmingPermanentDelete = document
        } label: {
          Label {
            Text("Delete now", bundle: .module)
          } icon: {
            Image(systemName: "trash")
          }
        }
        Button {
          Task { await model.restore(document.id) }
        } label: {
          Label {
            Text("Restore", bundle: .module)
          } icon: {
            Image(systemName: "arrow.uturn.backward")
          }
        }
      } else {
        Button(role: .destructive) {
          Task { await model.delete(document.id) }
        } label: {
          Label {
            Text("Delete", bundle: .module)
          } icon: {
            Image(systemName: "trash")
          }
        }
      }
    }
    .swipeActions(edge: .leading) {
      if !document.isDeleted {
        Button {
          Task { await model.toggleFavorite(document) }
        } label: {
          Label {
            document.isFavorite
              ? Text("Remove from favourites", bundle: .module) : Text("Add to favourites", bundle: .module)
          } icon: {
            Image(systemName: document.isFavorite ? "star.slash" : "star")
          }
        }
        .tint(Color.ds.brandTint)
      }
    }
    .contextMenu {
      if !document.isDeleted {
        Button {
          newTitle = document.title
          renaming = document
        } label: {
          Label {
            Text("Rename", bundle: .module)
          } icon: {
            Image(systemName: "pencil")
          }
        }
        Button {
          Task { await model.toggleFavorite(document) }
        } label: {
          Label {
            document.isFavorite
              ? Text("Remove from favourites", bundle: .module) : Text("Add to favourites", bundle: .module)
          } icon: {
            Image(systemName: "star")
          }
        }
        Button {
          tagging = document
        } label: {
          Label {
            Text("Tags", bundle: .module)
          } icon: {
            Image(systemName: "tag")
          }
        }
        Button(role: .destructive) {
          Task { await model.delete(document.id) }
        } label: {
          Label {
            Text("Delete", bundle: .module)
          } icon: {
            Image(systemName: "trash")
          }
        }
      }
    }
  }

  // MARK: - Empty and personalised states

  private var emptyState: some View {
    EmptyState(Self.emptyTitle(for: model.section), systemImage: Self.symbol(for: model.section)) {
      if model.section == .all {
        Text(
          "Import a PDF from Files, scan a paper document, or try a sample. Everything stays on this device.",
          bundle: .module)
      }
    } actions: {
      if model.section == .all {
        // The onboarding choice decides which action is prominent (FR-ONB-003).
        if model.primaryAction == .scanDocument {
          Button(action: onScan) { Text("Scan a document", bundle: .module).minimumTarget() }
            .buttonStyle(.primary)
            .accessibilityIdentifier("library.empty.primary.scan")
          Button {
            pick(task: model.primaryTask)
          } label: {
            Text("Import a PDF", bundle: .module).minimumTarget()
          }
          .accessibilityIdentifier("library.empty.import")
        } else {
          Button {
            pick(task: model.primaryTask)
          } label: {
            Text("Import a PDF", bundle: .module)
          }
          .buttonStyle(.primary)
          .accessibilityIdentifier("library.empty.primary.import")
          Button(action: onScan) { Text("Scan a document", bundle: .module).minimumTarget() }
        }
        Button {
          Task { await model.addSample(task: model.primaryTask) }
        } label: {
          Text("Try a sample", bundle: .module).minimumTarget()
        }
        .accessibilityIdentifier("library.empty.sample")
      }
    }
  }

  /// Opens the file picker; a single file picked opens with `task` started in the assistant (F9).
  private func pick(task: AssistantTask?) {
    importTask = task
    isPickingFiles = true
  }

  private var primaryActionCard: some View {
    let action = model.primaryAction
    return VStack(alignment: .leading, spacing: Spacing.s100) {
      Self.primaryTitle(for: action).font(.headline)
      Self.primaryDetail(for: action).font(.callout).foregroundStyle(Color.ds.labelSecondary)
      HStack {
        switch action {
        case .scanDocument:
          Button(action: onScan) { Text("Scan", bundle: .module) }.buttonStyle(.primary)
        case .importDocument:
          Button {
            pick(task: nil)
          } label: {
            Text("Import a PDF", bundle: .module)
          }.buttonStyle(.primary)
        case .openAssistant:
          Button {
            pick(task: model.primaryTask)
          } label: {
            Text("Choose a PDF", bundle: .module)
          }.buttonStyle(.primary)
        }
      }
    }
    .cardStyle()
    .accessibilityIdentifier("library.primaryAction")
  }

  // MARK: - Copy

  static func title(for section: LibrarySection) -> Text {
    switch section {
    case .all: Text("All documents", bundle: .module)
    case .recents: Text("Recents", bundle: .module)
    case .favorites: Text("Favourites", bundle: .module)
    case .recentlyDeleted: Text("Recently deleted", bundle: .module)
    case .tag(let tag): Text(tag)
    }
  }

  static func emptyTitle(for section: LibrarySection) -> Text {
    switch section {
    case .all: Text("No documents yet", bundle: .module)
    case .recents: Text("Nothing opened yet", bundle: .module)
    case .favorites: Text("No favourites", bundle: .module)
    case .recentlyDeleted: Text("Nothing deleted in the last 30 days", bundle: .module)
    case .tag: Text("No documents with this tag", bundle: .module)
    }
  }

  static func symbol(for section: LibrarySection) -> String {
    switch section {
    case .all: "doc.on.doc"
    case .recents: "clock"
    case .favorites: "star"
    case .recentlyDeleted: "trash"
    case .tag: "tag"
    }
  }

  static func identifier(for section: LibrarySection) -> String {
    switch section {
    case .all: "all"
    case .recents: "recents"
    case .favorites: "favorites"
    case .recentlyDeleted: "deleted"
    case .tag(let tag): "tag.\(tag)"
    }
  }

  static func primaryTitle(for action: HomeAction) -> Text {
    switch action {
    case .importDocument: Text("Open your first PDF", bundle: .module)
    case .scanDocument: Text("Scan a document", bundle: .module)
    case .openAssistant(.ask): Text("Chat with a PDF", bundle: .module)
    case .openAssistant(.summarize): Text("Summarise a document", bundle: .module)
    case .openAssistant(.extract): Text("Extract data from a PDF", bundle: .module)
    case .openAssistant(.explainContract): Text("Understand a contract", bundle: .module)
    }
  }

  static func primaryDetail(for action: HomeAction) -> Text {
    switch action {
    case .importDocument: Text("Import from Files, or drag PDFs here.", bundle: .module)
    case .scanDocument: Text("Your scan becomes a searchable PDF, recognised on this device.", bundle: .module)
    case .openAssistant:
      Text("Choose a PDF and the assistant opens with it. Answers cite their pages.", bundle: .module)
    }
  }
}
