import Core
import DesignSystem
import PDFEngine
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The library: a split view with sections, the document list and the open document (ADR-0004).
///
/// On iPhone it collapses to a stack that opens on Home, the first column: the app's mark, the actions
/// people start with, the documents they opened last, and the sections. Layouts follow size, never
/// device type.
public struct LibraryView<Detail: View>: View {
  @State private var model: LibraryModel
  @State private var columns = NavigationSplitViewVisibility.automatic
  @State private var compactColumn = NavigationSplitViewColumn.content
  @Environment(\.horizontalSizeClass) private var sizeClass
  @Environment(\.dynamicTypeSize) private var typeSize
  @State private var isPickingFiles = false
  @State private var isPickingPhotos = false
  @State private var photos: [PhotosPickerItem] = []
  /// The assistant task to start on a single imported file: set by the home screen's primary action.
  @State private var importTask: AssistantTask?
  @State private var renaming: Document?
  @State private var tagging: Document?
  @State private var showingInfo: InfoSheet?
  /// Whether the list is selecting documents to act on together (FR-LIB-009).
  @State private var isSelecting = false
  @State private var chosen: Set<DocumentID> = []
  @State private var shareURLs: [URL] = []
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
    _compactColumn = State(initialValue: Self.firstColumn(for: model))
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
    .sheet(item: $showingInfo) { info in
      DocumentInfoView(document: info.document, details: info.details)
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
    // A link, Spotlight or an intent asked for a section: leave Home for its documents.
    .onChange(of: model.listRequests) { if model.selection == nil { compactColumn = .content } }
    // On iPhone the back button leaves the document without telling the model. Closing it there lets
    // the same document open again, and lets the list pick up what changed in the reader. It waits
    // for the document to slide away so the empty detail never shows in its place.
    .onChange(of: compactColumn) {
      guard compactColumn != .detail, model.selection != nil else { return }
      Task {
        try? await Task.sleep(for: .milliseconds(400))
        if compactColumn != .detail { model.selection = nil }
      }
    }
    .task { await model.load() }
  }

  // MARK: - Sidebar

  /// The first column: Home on iPhone, a sidebar beside the documents on a wide window.
  private var sidebar: some View {
    Group {
      if sizeClass == .compact { home } else { sectionList }
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

  /// The sidebar of a wide window: the sections with their counts, and the tags.
  private var sectionList: some View {
    List(
      // Choosing a section shows its documents in the next column.
      selection: Binding(
        get: { compactColumn == .sidebar ? nil : model.section },
        set: { section in
          if let section {
            model.section = section
            compactColumn = .content
          } else {
            compactColumn = .sidebar
          }
        })
    ) {
      Section {
        ForEach(LibrarySection.fixed, id: \.self) { section in
          sectionLabel(section)
            .tag(section)
            .accessibilityElement(children: .combine)
            .accessibilityValue(sectionCount(section))
            .accessibilityIdentifier("library.section.\(Self.identifier(for: section))")
        }
      }
      if !model.tags.isEmpty {
        Section {
          ForEach(model.tags, id: \.self) { tag in
            Label(tag, systemImage: "tag").tag(LibrarySection.tag(tag))
          }
        } header: {
          Text("Tags", bundle: .module).foregroundStyle(Color.ds.labelSecondary)
        }
      }
    }
  }

  // MARK: - Home

  /// Home, the screen an iPhone opens on.
  ///
  /// A scroll view of cards, not a list: every part lays itself out at once when the text size
  /// changes, and nothing is cut to a list row's shape.
  var home: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Spacing.s300) {
        VStack(alignment: .leading, spacing: Spacing.s200) {
          homeHeader
          homeActions
          if model.phase == .loaded, model.counts[.all] == 0 { homeStart }
        }
        if !model.recentDocuments.isEmpty {
          VStack(alignment: .leading, spacing: Spacing.s100) {
            homeHeading(Text("Continue reading", bundle: .module))
            homeCard(model.recentDocuments, id: \.id) { document in recentRow(document) }
          }
        }
        homeCard(LibrarySection.fixed, id: \.self) { section in sectionRow(section) }
        if !model.tags.isEmpty {
          VStack(alignment: .leading, spacing: Spacing.s100) {
            homeHeading(Text("Tags", bundle: .module))
            homeCard(model.tags, id: \.self) { tag in tagRow(tag) }
          }
        }
        homeFooter
      }
      .padding(.horizontal, Spacing.s200)
      .padding(.bottom, Spacing.s300)
    }
    .background {
      ZStack(alignment: .top) {
        Color.ds.backgroundGrouped
        // Behind the title only: text further down is read against a plain background.
        BrandGlow(over: Color.ds.backgroundGrouped).frame(height: 220)
      }
      .ignoresSafeArea()
    }
  }

  /// A heading over one of Home's cards.
  private func homeHeading(_ title: Text) -> some View {
    title
      .font(.title3.weight(.semibold))
      .foregroundStyle(Color.ds.labelPrimary)
      .accessibilityAddTraits(.isHeader)
  }

  /// A card of rows with a hairline between them, as a grouped list draws its sections.
  private func homeCard<Items: RandomAccessCollection, ID: Hashable, Row: View>(
    _ items: Items, id: KeyPath<Items.Element, ID>, @ViewBuilder row: @escaping (Items.Element) -> Row
  ) -> some View {
    let last = items.last?[keyPath: id]
    return VStack(spacing: Spacing.s0) {
      ForEach(items, id: id) { item in
        row(item)
        if item[keyPath: id] != last { Divider().padding(.leading, Spacing.s200) }
      }
    }
    .background(Color.ds.backgroundGroupedElevated, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
  }

  /// A section's tile and title, and how many documents it holds once the library has loaded.
  private func sectionLabel(_ section: LibrarySection) -> some View {
    HStack(spacing: Spacing.s150) {
      IconTile(systemName: Self.symbol(for: section), tone: section == .recentlyDeleted ? .quiet : .brand)
      Self.title(for: section).foregroundStyle(Color.ds.labelPrimary)
      Spacer(minLength: Spacing.s100)
      if model.phase == .loaded, let count = model.counts[section] {
        Text(count, format: .number)
          .monospacedDigit()
          .foregroundStyle(Color.ds.labelSecondary)
          // The row says the count in words (`sectionCount`); a spoken label here would be longer
          // than the digit it sits on.
          .accessibilityHidden(true)
      }
    }
  }

  /// How many documents a section holds, in words, for VoiceOver; empty until the library has loaded.
  private func sectionCount(_ section: LibrarySection) -> Text {
    guard model.phase == .loaded, let count = model.counts[section] else { return Text(verbatim: "") }
    return Text("\(count) documents", bundle: .module)
  }

  /// A section's row on Home: tapping it shows the section's documents.
  private func sectionRow(_ section: LibrarySection) -> some View {
    Button {
      model.section = section
      compactColumn = .content
    } label: {
      HStack(spacing: Spacing.s100) {
        sectionLabel(section)
        Image(systemName: "chevron.forward")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(Color.ds.labelTertiary)
          .accessibilityHidden(true)
      }
      .homeRow()
    }
    .buttonStyle(DimmingButtonStyle())
    .accessibilityElement(children: .combine)
    .accessibilityValue(sectionCount(section))
    .accessibilityIdentifier("library.section.\(Self.identifier(for: section))")
  }

  /// A tag's row on Home.
  private func tagRow(_ tag: String) -> some View {
    Button {
      model.section = .tag(tag)
      compactColumn = .content
    } label: {
      HStack(spacing: Spacing.s150) {
        IconTile(systemName: "tag")
        Text(tag).foregroundStyle(Color.ds.labelPrimary)
        Spacer(minLength: Spacing.s100)
        Image(systemName: "chevron.forward")
          .font(.footnote.weight(.semibold))
          .foregroundStyle(Color.ds.labelTertiary)
          .accessibilityHidden(true)
      }
      .homeRow()
    }
    .buttonStyle(DimmingButtonStyle())
    .accessibilityIdentifier("library.section.\(Self.identifier(for: .tag(tag)))")
  }

  /// The app's mark beside what the library holds.
  private var homeHeader: some View {
    HStack(spacing: Spacing.s200) {
      AppMark()
      VStack(alignment: .leading, spacing: Spacing.s050) {
        Text("Your library", bundle: .module)
          .font(.title3.weight(.semibold))
          .foregroundStyle(Color.ds.labelPrimary)
          .accessibilityAddTraits(.isHeader)
        // The line keeps its place while the library loads, so nothing below it moves.
        Group {
          if model.phase != .loaded {
            Text(verbatim: " ").accessibilityHidden(true)
          } else if let count = model.counts[.all], count > 0 {
            Text("\(count) documents", bundle: .module)
          } else {
            Text("No documents yet", bundle: .module)
          }
        }
        .font(.subheadline)
        .foregroundStyle(Color.ds.labelSecondary)
      }
      Spacer(minLength: 0)
    }
    .accessibilityElement(children: .combine)
  }

  /// The actions people start with; the onboarding choice decides which one is filled (FR-ONB-003).
  private var homeActions: some View {
    let layout =
      typeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(spacing: Spacing.s100)) : AnyLayout(HStackLayout(spacing: Spacing.s100))
    let primary = model.primaryAction
    return layout {
      if case .openAssistant(let task) = primary {
        QuickAction(Self.assistantTitle(for: task), systemImage: "sparkles", prominence: .filled) {
          startAtAllDocuments()
          pick(task: task)
        }
        .accessibilityIdentifier("library.home.primary.assistant")
      }
      if primary == .scanDocument {
        homeScan(.filled).accessibilityIdentifier("library.home.primary.scan")
        homeImport(.tonal).accessibilityIdentifier("library.home.import")
      } else {
        homeImport(primary == .importDocument ? .filled : .tonal)
          .accessibilityIdentifier(primary == .importDocument ? "library.home.primary.import" : "library.home.import")
        homeScan(.tonal).accessibilityIdentifier("library.home.scan")
      }
    }
    .fixedSize(horizontal: false, vertical: true)
  }

  private func homeScan(_ prominence: QuickAction.Prominence) -> some View {
    QuickAction(Text("Scan", bundle: .module), systemImage: "doc.viewfinder", prominence: prominence) {
      startAtAllDocuments()
      onScan()
    }
  }

  private func homeImport(_ prominence: QuickAction.Prominence) -> some View {
    QuickAction(Text("Import", bundle: .module), systemImage: "square.and.arrow.down", prominence: prominence) {
      startAtAllDocuments()
      pick(task: nil)
    }
  }

  /// With nothing in the library yet: what can be done, and the sample.
  private var homeStart: some View {
    VStack(alignment: .leading, spacing: Spacing.s050) {
      Text(
        "Import a PDF from Files, scan a paper document, or try a sample. Everything stays on this device.",
        bundle: .module
      )
      .font(.callout)
      .foregroundStyle(Color.ds.labelSecondary)
      Button {
        startAtAllDocuments()
        Task { await model.addSample(task: model.primaryTask) }
      } label: {
        Text("Try a sample", bundle: .module)
          .font(.callout.weight(.semibold))
          .foregroundStyle(Color.ds.brandTint)
          .minimumTarget()
      }
      .buttonStyle(DimmingButtonStyle())
      .accessibilityIdentifier("library.home.sample")
    }
  }

  /// One of the documents opened last, as the document list shows it.
  private func recentRow(_ document: Document) -> some View {
    Button {
      // Back from the document then shows Recents, where it is first.
      model.section = .recents
      model.open(document.id)
      compactColumn = .detail
    } label: {
      DocumentRow(
        document: document, snippet: nil, thumbnail: { await model.thumbnail(for: document) }, titleLineLimit: nil
      )
      .homeRow()
    }
    .buttonStyle(DimmingButtonStyle())
    .accessibilityIdentifier("library.home.recent.\(document.title)")
  }

  /// What the app promises about documents, and who makes it.
  private var homeFooter: some View {
    VStack(spacing: Spacing.s100) {
      HStack(spacing: Spacing.s100) {
        Image(systemName: "lock.shield").accessibilityHidden(true)
        Text("Your documents stay on this device.", bundle: .module)
      }
      HStack(spacing: Spacing.s100) {
        // The words beside it name the company; read aloud, the mark would only say it twice.
        CompanyMark(side: 22).accessibilityHidden(true)
        Text("Built by Algorythmos", bundle: .module)
      }
      .accessibilityElement(children: .combine)
    }
    .font(.footnote)
    .foregroundStyle(Color.ds.labelSecondary)
    .multilineTextAlignment(.center)
    .frame(maxWidth: .infinity)
  }

  /// A document brought in from Home is filed in All documents, so that is where Back should lead.
  private func startAtAllDocuments() {
    model.section = .all
  }

  /// The column an iPhone shows first: an open document, a section that was asked for, or Home.
  static func firstColumn(for model: LibraryModel) -> NavigationSplitViewColumn {
    if model.selection != nil { return .detail }
    return model.listRequests > 0 ? .content : .sidebar
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
      if isSelecting {
        ToolbarItemGroup(placement: .bottomBar) { selectionActions }
      }
      if !model.documents.isEmpty, model.results == nil, model.section != .recentlyDeleted {
        ToolbarItem(placement: .topBarTrailing) {
          Button {
            isSelecting.toggle()
            chosen = []
          } label: {
            isSelecting ? Text("Done", bundle: .module) : Text("Select", bundle: .module)
          }
          .accessibilityIdentifier("library.select")
        }
      }
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
      } else if !model.lastDeleted.isEmpty {
        undoBanner
      }
    }
    .task(id: model.lastDeleted) {
      guard !model.lastDeleted.isEmpty else { return }
      try? await Task.sleep(for: .seconds(8))
      model.forgetLastDeleted()
    }
    .task(id: chosen) {
      shareURLs = await model.fileURLs(for: Array(chosen))
    }
  }

  /// What can be done with the chosen documents together (FR-LIB-009).
  @ViewBuilder private var selectionActions: some View {
    let ids = model.documents.map(\.id).filter { chosen.contains($0) }
    ShareLink(items: shareURLs) {
      Label {
        Text("Share", bundle: .module)
      } icon: {
        Image(systemName: "square.and.arrow.up")
      }
    }
    .disabled(shareURLs.isEmpty)
    Button {
      let allFavourite = model.documents.filter { chosen.contains($0.id) }.allSatisfy(\.isFavorite)
      Task { await model.setFavorite(!allFavourite, for: ids) }
    } label: {
      Label {
        Text("Favourite", bundle: .module)
      } icon: {
        Image(systemName: "star")
      }
    }
    .disabled(ids.isEmpty)
    Button {
      Task {
        await model.merge(ids)
        isSelecting = false
        chosen = []
      }
    } label: {
      Label {
        Text("Merge", bundle: .module)
      } icon: {
        Image(systemName: "rectangle.stack.badge.plus")
      }
    }
    .disabled(ids.count < 2)
    .accessibilityIdentifier("library.merge")
    Button(role: .destructive) {
      Task {
        await model.delete(ids)
        isSelecting = false
        chosen = []
      }
    } label: {
      Label {
        Text("Delete", bundle: .module)
      } icon: {
        Image(systemName: "trash")
      }
    }
    .disabled(ids.isEmpty)
  }

  /// Says what was just deleted, with Undo, for a few seconds.
  private var undoBanner: some View {
    HStack(spacing: Spacing.s150) {
      Text("\(model.lastDeleted.count) moved to Recently deleted", bundle: .module).font(.callout)
      Button {
        Task { await model.undoDelete() }
      } label: {
        Text("Undo", bundle: .module).bold()
      }
      .accessibilityIdentifier("library.undoDelete")
    }
    .padding(.horizontal, Spacing.s200)
    .padding(.vertical, Spacing.s150)
    .background(.regularMaterial, in: Capsule())
    .padding(Spacing.s200)
  }

  private var documentList: some View {
    List(selection: $chosen) {
      if !isSelecting, model.showsPrimaryAction {
        primaryActionCard.listRowSeparator(.hidden)
      }
      ForEach(model.documents) { document in
        if isSelecting {
          DocumentRow(document: document, snippet: nil, thumbnail: { await model.thumbnail(for: document) })
            .tag(document.id)
        } else {
          row(document, snippet: nil, pageIndex: nil)
        }
      }
      // No line above the first row: the title already separates the list from the bar.
      .listSectionSeparator(.hidden, edges: .top)
    }
    .environment(\.editMode, .constant(isSelecting ? .active : .inactive))
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
      compactColumn = .detail
    } label: {
      DocumentRow(document: document, snippet: snippet, thumbnail: { await model.thumbnail(for: document) })
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("library.document.\(document.title)")
    .modifier(DragsOut(document: model.offersDragging && !document.isDeleted ? model.dragged(document) : nil))
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
      // In Recently deleted, the menu offers what the swipe does, so restoring is easy to find.
      if document.isDeleted {
        Button {
          Task { await model.restore(document.id) }
        } label: {
          Label {
            Text("Restore", bundle: .module)
          } icon: {
            Image(systemName: "arrow.uturn.backward")
          }
        }
        Button(role: .destructive) {
          confirmingPermanentDelete = document
        } label: {
          Label {
            Text("Delete now", bundle: .module)
          } icon: {
            Image(systemName: "trash")
          }
        }
      }
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
        Button {
          Task { showingInfo = InfoSheet(document: document, details: await model.details(for: document)) }
        } label: {
          Label {
            Text("Info", bundle: .module)
          } icon: {
            Image(systemName: "info.circle")
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

  /// The assistant action's title on Home, short enough for a tile.
  static func assistantTitle(for task: AssistantTask) -> Text {
    switch task {
    case .ask: Text("Ask a PDF", bundle: .module)
    case .summarize: Text("Summarise", bundle: .module)
    case .extract: Text("Extract data", bundle: .module)
    case .explainContract: Text("Explain a contract", bundle: .module)
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

extension View {
  /// The inset and height of a row in one of Home's cards: at least the 44-point target.
  fileprivate func homeRow() -> some View {
    padding(.horizontal, Spacing.s200)
      .padding(.vertical, Spacing.s100)
      .frame(maxWidth: .infinity, minHeight: Sizes.targetMinimum + Spacing.s100, alignment: .leading)
      .contentShape(Rectangle())
  }
}

/// A button that only dims while pressed: for Home's rows and its text button.
struct DimmingButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
  }
}

/// A document and its file's details, for the info sheet.
struct InfoSheet: Identifiable {
  let document: Document
  let details: DocumentDetails?
  var id: DocumentID { document.id }
}

/// Lets a row be dragged into another app as its PDF, when there is something to drag.
private struct DragsOut: ViewModifier {
  let document: DraggedDocument?

  func body(content: Content) -> some View {
    if let document {
      content.draggable(document)
    } else {
      content
    }
  }
}
