import AccessibilityIDs
import Core
import DesignSystem
import PhotosUI
import Scanning
import SwiftUI
import UniformTypeIdentifiers

/// The scanner sheet: the system document camera where there is one, and images from Files
/// everywhere, so every device can make searchable PDFs.
public struct ScanView: View {
  @State private var model: ScanModel
  @State private var showsCamera = false
  @State private var isChoosingImages = false
  @State private var isChoosingPhotos = false
  @State private var photos: [PhotosPickerItem] = []
  @Environment(\.dismiss) private var dismiss

  /// Creates the sheet for a model.
  public init(model: ScanModel) {
    _model = State(initialValue: model)
  }

  /// The sheet.
  public var body: some View {
    NavigationStack {
      content
        .padding(Spacing.s200)
        .navigationTitle(Text("Scan", bundle: .module))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) {
            Button {
              model.cancel()
              dismiss()
            } label: {
              Text("Cancel", bundle: .module)
            }
            .accessibilityIdentifier(AccessibilityID.Scan.cancel)
          }
        }
        .fullScreenCover(isPresented: $showsCamera) {
          DocumentCameraView { images in
            showsCamera = false
            Task { await model.review(images) }
          } onCancel: {
            showsCamera = false
          }
          .ignoresSafeArea()
        }
        // Photos of pages are usually in the photo library; the picker needs no permission, because
        // only the chosen photos reach the app.
        .photosPicker(isPresented: $isChoosingPhotos, selection: $photos, matching: .images)
        .onChange(of: photos) { _, items in
          guard !items.isEmpty else { return }
          photos = []
          Task {
            var data: [Data] = []
            // A photo that doesn't load, such as an iCloud original offline, is counted, not dropped (#238).
            var unreadable = 0
            for item in items {
              if let photo = try? await item.loadTransferable(type: Data.self) {
                data.append(photo)
              } else {
                unreadable += 1
              }
            }
            await model.process(photos: data, unreadable: unreadable)
          }
        }
        .fileImporter(isPresented: $isChoosingImages, allowedContentTypes: [.image], allowsMultipleSelection: true) {
          result in
          if case .success(let urls) = result { Task { await model.process(files: urls) } }
        }
    }
  }

  /// What the current phase shows; outside the navigation stack so tests can draw every phase.
  @ViewBuilder var content: some View {
    switch model.phase {
    case .ready: ready
    case .reviewing: reviewing
    case .recognizing(let progress): recognizing(progress)
    case .saving, .finished: waiting
    case .failed:
      EmptyState(Text("The scan wasn't saved", bundle: .module), systemImage: "exclamationmark.triangle") {
        Text("Text recognition didn't finish. Your pages are kept, so you can try again.", bundle: .module)
      } actions: {
        Button {
          model.reset()
        } label: {
          Text("Try again", bundle: .module).minimumTarget()
        }
        .accessibilityIdentifier(AccessibilityID.Scan.tryAgain)
      }
    }
  }

  private var ready: some View {
    VStack(spacing: Spacing.s300) {
      Image(systemName: "doc.viewfinder").font(.system(.largeTitle)).foregroundStyle(Color.ds.brandTint)
        .accessibilityHidden(true)
      Text(
        "Scanned pages become a searchable PDF. Text is recognised on this device, in English and French.",
        bundle: .module
      )
      .multilineTextAlignment(.center)
      .foregroundStyle(Color.ds.labelSecondary)
      if DocumentCamera.isSupported {
        Button {
          showsCamera = true
        } label: {
          Text("Scan with camera", bundle: .module)
        }
        .buttonStyle(.primary)
        .accessibilityIdentifier(AccessibilityID.Scan.camera)
      } else {
        Text("This device has no document camera. You can make a PDF from photos of pages instead.", bundle: .module)
          .font(.footnote)
          .multilineTextAlignment(.center)
          .foregroundStyle(Color.ds.labelSecondary)
          .accessibilityIdentifier(AccessibilityID.Scan.noCamera)
      }
      Button {
        isChoosingPhotos = true
      } label: {
        Text("Choose from Photos", bundle: .module).minimumTarget()
      }
      .accessibilityIdentifier(AccessibilityID.Scan.photos)
      Button {
        isChoosingImages = true
      } label: {
        Text("Choose from Files", bundle: .module).minimumTarget()
      }
      .accessibilityIdentifier(AccessibilityID.Scan.images)
      if let notice = model.notice {
        Text(notice)
          .font(.footnote)
          .multilineTextAlignment(.center)
          .foregroundStyle(Color.ds.labelSecondary)
          .accessibilityIdentifier(AccessibilityID.Scan.notice)
      }
    }
    .readableWidth()
    .centeredScrolling()
  }

  /// The pages and name, checked before saving (FR-SCAN-006).
  private var reviewing: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Spacing.s200) {
        TextField(text: $model.title) { Text("Name", bundle: .module) }
          .textFieldStyle(.roundedBorder)
          .font(.headline)
          .accessibilityLabel(Text("Name", bundle: .module))
          .accessibilityIdentifier(AccessibilityID.Scan.title)
        Text("Tap a page to rotate, move or delete it.", bundle: .module)
          .font(.footnote).foregroundStyle(Color.ds.labelSecondary)
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: Spacing.s200)], spacing: Spacing.s200) {
          ForEach(Array(model.pages.enumerated()), id: \.offset) { index, page in
            Menu {
              Button {
                model.rotatePage(at: index)
              } label: {
                Label {
                  Text("Rotate", bundle: .module)
                } icon: {
                  Image(systemName: "rotate.right")
                }
              }
              .accessibilityIdentifier(AccessibilityID.Scan.Page.rotate)
              if index > 0 {
                Button {
                  model.movePage(at: index, earlier: true)
                } label: {
                  Label {
                    Text("Move earlier", bundle: .module)
                  } icon: {
                    Image(systemName: "arrow.left")
                  }
                }
                .accessibilityIdentifier(AccessibilityID.Scan.Page.moveEarlier)
              }
              if index < model.pages.count - 1 {
                Button {
                  model.movePage(at: index, earlier: false)
                } label: {
                  Label {
                    Text("Move later", bundle: .module)
                  } icon: {
                    Image(systemName: "arrow.right")
                  }
                }
                .accessibilityIdentifier(AccessibilityID.Scan.Page.moveLater)
              }
              if model.pages.count > 1 {
                Button(role: .destructive) {
                  model.deletePage(at: index)
                } label: {
                  Label {
                    Text("Delete page", bundle: .module)
                  } icon: {
                    Image(systemName: "trash")
                  }
                }
                .accessibilityIdentifier(AccessibilityID.Scan.Page.delete)
              }
            } label: {
              VStack(spacing: Spacing.s050) {
                Image(decorative: page, scale: 1).resizable().scaledToFit().frame(height: 140)
                Text(index + 1, format: .number).font(.caption.monospacedDigit())
              }
            }
            .accessibilityIdentifier(AccessibilityID.Scan.page(index + 1))
            .accessibilityLabel(Text("Page \(index + 1)", bundle: .module))
          }
        }
        Button {
          Task { await model.save() }
        } label: {
          Text("Save", bundle: .module).frame(maxWidth: .infinity)
        }
        .buttonStyle(.primary)
        .accessibilityIdentifier(AccessibilityID.Scan.save)
        Button {
          model.discardReview()
        } label: {
          Text("Discard", bundle: .module).minimumTarget().frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier(AccessibilityID.Scan.discard)
      }
      .readableWidth()
    }
  }

  /// A wait with nothing to choose, which says what is happening (#371).
  @ViewBuilder private var waiting: some View {
    if let words = model.phase.waitingWords {
      ProgressView { Text(words) }
        .readableWidth()
        .centeredScrolling()
    }
  }

  private func recognizing(_ progress: Double) -> some View {
    VStack(spacing: Spacing.s200) {
      ProgressView(value: progress) { Text("Recognising text on this device…", bundle: .module) }
      Button {
        model.cancel()
      } label: {
        Text("Stop", bundle: .module).minimumTarget()
      }
      .accessibilityIdentifier(AccessibilityID.Scan.stop)
    }
    .readableWidth()
    .centeredScrolling()
  }
}
