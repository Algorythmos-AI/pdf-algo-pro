import Core
import CoreGraphics
import Foundation
import Observation
import PDFEngine
import Scanning

/// Scanning to a searchable PDF, entirely on device (FR-SCAN-001, FR-SCAN-002).
@MainActor
@Observable
public final class ScanModel {
  /// What the scanner is showing.
  public enum Phase: Equatable {
    /// Ready to capture or choose images.
    case ready
    /// Checking the pages and the name before saving (FR-SCAN-006).
    case reviewing
    /// Recognising text, from 0 to 1.
    case recognizing(Double)
    /// Saved as a document.
    case finished(Document)
    /// Recognition failed; nothing was saved.
    case failed
  }

  /// What is shown.
  public private(set) var phase: Phase = .ready

  /// A note about chosen files that could not be used, shown until the next choice.
  public private(set) var notice: String?
  /// The captured pages, in order, while reviewing (FR-SCAN-006).
  public private(set) var pages: [CGImage] = []
  /// The name the scan will be saved under; suggested from the first page until the person types one.
  public var title = "" {
    didSet { if !isSuggesting { isTitleEdited = true } }
  }
  @ObservationIgnored private var isTitleEdited = false
  @ObservationIgnored private var isSuggesting = false

  private let intake: DocumentIntake
  private let builder: SearchablePDFBuilder
  private let telemetry: any TelemetryRecording
  private let recognizer: (any TextRecognizing)?
  private let now: () -> Date
  private let onFinish: (Document) -> Void
  private var work: Task<Void, Never>?

  /// Creates the scanner; `onFinish` opens the new document.
  public init(
    intake: DocumentIntake, builder: SearchablePDFBuilder, telemetry: any TelemetryRecording,
    recognizer: (any TextRecognizing)? = nil, now: @escaping () -> Date = { Date() },
    onFinish: @escaping (Document) -> Void
  ) {
    self.intake = intake
    self.builder = builder
    self.telemetry = telemetry
    self.recognizer = recognizer
    self.now = now
    self.onFinish = onFinish
  }

  /// The title a new scan gets, for example "Scan 28 Sept 2026 at 23:41".
  public var defaultTitle: String {
    String(localized: "Scan \(now().formatted(date: .abbreviated, time: .shortened))", bundle: .module)
  }

  // MARK: - Review (FR-SCAN-006)

  /// Shows captured pages for review before saving, and suggests a name from the first page.
  public func review(_ images: [CGImage]) async {
    guard !images.isEmpty else { return }
    pages = images
    setTitle(defaultTitle)
    isTitleEdited = false
    phase = .reviewing
    guard let recognizer, let first = images.first,
      let lines = try? await recognizer.recognizeText(in: first),
      let suggestion = Self.suggestedTitle(from: lines),
      phase == .reviewing, !isTitleEdited
    else { return }
    setTitle(suggestion)
  }

  private func setTitle(_ suggestion: String) {
    isSuggesting = true
    title = suggestion
    isSuggesting = false
  }

  /// Turns a page a quarter turn clockwise.
  public func rotatePage(at index: Int) {
    guard pages.indices.contains(index), let rotated = Self.rotatedClockwise(pages[index]) else { return }
    pages[index] = rotated
  }

  /// Removes a page; the last page stays.
  public func deletePage(at index: Int) {
    guard pages.count > 1, pages.indices.contains(index) else { return }
    pages.remove(at: index)
  }

  /// Moves a page one place earlier or later.
  public func movePage(at index: Int, earlier: Bool) {
    let target = earlier ? index - 1 : index + 1
    guard pages.indices.contains(index), pages.indices.contains(target) else { return }
    pages.swapAt(index, target)
  }

  /// Saves the reviewed pages as a searchable PDF under the chosen name.
  public func save() async {
    let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
    let reviewed = pages
    pages = []
    await process(reviewed, title: name.isEmpty ? defaultTitle : name)
  }

  /// Leaves the review without saving anything.
  public func discardReview() {
    pages = []
    phase = .ready
  }

  /// A name from the first page: its largest line of words, near the top, such as "Invoice" or a
  /// company's name; `nil` when no line looks like a title.
  nonisolated static func suggestedTitle(from lines: [RecognizedLine]) -> String? {
    let candidates = lines.filter { line in
      let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
      let letters = text.filter(\.isLetter).count
      return line.bounds.minY >= 0.5 && line.confidence >= 0.5 && letters >= 4 && letters * 2 >= text.count
    }
    guard
      let best = candidates.max(by: { ($0.bounds.height, $0.bounds.minY) < ($1.bounds.height, $1.bounds.minY) })
    else { return nil }
    return String(best.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
  }

  /// An image turned a quarter turn clockwise.
  nonisolated static func rotatedClockwise(_ image: CGImage) -> CGImage? {
    let width = image.width
    let height = image.height
    guard
      let context = CGContext(
        data: nil, width: height, height: width, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { return nil }
    context.translateBy(x: 0, y: CGFloat(width))
    context.rotate(by: -.pi / 2)
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
  }

  // MARK: - Saving

  /// Recognises the pages and saves them as a searchable PDF.
  public func process(_ images: [CGImage], title: String? = nil) async {
    guard !images.isEmpty else { return }
    let title = title ?? defaultTitle
    phase = .recognizing(0)
    let work = Task {
      do {
        let result = try await builder.makeSearchablePDF(from: images) { progress in
          Task { @MainActor in
            if case .recognizing = self.phase { self.phase = .recognizing(progress) }
          }
        }
        // Cancelled during the last page: the builder has finished, but nothing is saved.
        try Task.checkCancellation()
        let document = try await intake.add(data: result.data, title: title)
        phase = .finished(document)
        await telemetry.record("task.core.completed")
        onFinish(document)
      } catch is CancellationError {
        phase = .ready
      } catch {
        phase = .failed
        await telemetry.record("quality.operation.failed")
      }
    }
    self.work = work
    await work.value
  }

  /// Reviews images chosen in Files; files that are not images are skipped, and the notice says so.
  public func process(files urls: [URL]) async {
    let images = ImageLoader.images(at: urls)
    let skipped = urls.count - images.count
    notice =
      skipped > 0
      ? String(localized: "\(skipped) of the chosen files weren't images, so they were skipped.", bundle: .module) : nil
    await review(images)
  }

  /// Cancels recognition; nothing is saved.
  public func cancel() {
    work?.cancel()
  }

  /// Returns to the ready state after a failure.
  public func reset() {
    phase = .ready
  }
}
