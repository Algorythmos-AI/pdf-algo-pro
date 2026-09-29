import Core
import CoreGraphics
import Foundation
import Observation
import PDFEngine

/// Scanning to a searchable PDF, entirely on device (FR-SCAN-001, FR-SCAN-002).
@MainActor
@Observable
public final class ScanModel {
  /// What the scanner is showing.
  public enum Phase: Equatable {
    /// Ready to capture or choose images.
    case ready
    /// Recognising text, from 0 to 1.
    case recognizing(Double)
    /// Saved as a document.
    case finished(Document)
    /// Recognition failed; nothing was saved.
    case failed
  }

  /// What is shown.
  public private(set) var phase: Phase = .ready

  private let intake: DocumentIntake
  private let builder: SearchablePDFBuilder
  private let telemetry: any TelemetryRecording
  private let now: () -> Date
  private let onFinish: (Document) -> Void
  private var work: Task<Void, Never>?

  /// Creates the scanner; `onFinish` opens the new document.
  public init(
    intake: DocumentIntake, builder: SearchablePDFBuilder, telemetry: any TelemetryRecording,
    now: @escaping () -> Date = { Date() }, onFinish: @escaping (Document) -> Void
  ) {
    self.intake = intake
    self.builder = builder
    self.telemetry = telemetry
    self.now = now
    self.onFinish = onFinish
  }

  /// The title a new scan gets, for example "Scan 28 Sept 2026 at 23:41".
  public var defaultTitle: String {
    String(localized: "Scan \(now().formatted(date: .abbreviated, time: .shortened))", bundle: .module)
  }

  /// Recognises the pages and saves them as a searchable PDF.
  public func process(_ images: [CGImage]) async {
    guard !images.isEmpty else { return }
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
        let document = try await intake.add(data: result.data, title: defaultTitle)
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

  /// Cancels recognition; nothing is saved.
  public func cancel() {
    work?.cancel()
  }

  /// Returns to the ready state after a failure.
  public func reset() {
    phase = .ready
  }
}
