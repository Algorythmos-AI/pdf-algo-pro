import AVFoundation
import Observation

/// What speaks: the system voices in the app, a silent stand-in in tests.
///
/// Tests never touch the system voices: on the CI simulator their database can block the main thread
/// for minutes.
@MainActor
public protocol SpeechEngine: AnyObject {
  /// Called when the text being spoken ends: `true` when it was read to the end, `false` when it was
  /// stopped or cancelled. Text replaced by a later `speak` doesn't report its end.
  var onEnd: ((_ finished: Bool) -> Void)? { get set }
  /// Speaks text, replacing anything still being spoken.
  func speak(_ text: String)
  /// Stops speaking.
  func stop()
}

/// "Listen to this PDF" with the system voices (FR-READ-004), page after page (FR-READ-008).
@MainActor
@Observable
public final class SpeechReader {
  /// Whether speech is playing.
  public private(set) var isSpeaking = false
  @ObservationIgnored private let engine: any SpeechEngine
  /// The document being read, when reading goes on from page to page.
  @ObservationIgnored private var reading: Reading?

  private struct Reading {
    var page: Int
    let pageCount: Int
    let text: (Int) -> String
    let onPage: (Int) -> Void
  }

  /// Creates a reader over an engine; the app uses the system voices.
  public init(engine: any SpeechEngine = SystemSpeechEngine()) {
    self.engine = engine
    engine.onEnd = { [weak self] finished in self?.ended(finished: finished) }
  }

  /// Speaks text in the system's default voice for its language.
  public func speak(_ text: String) {
    reading = nil
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    engine.speak(trimmed)
    isSpeaking = true
  }

  /// Reads a document aloud from a page to the end, skipping pages without text (FR-READ-008).
  ///
  /// `onPage` turns the reader to the page being read.
  public func read(
    from page: Int, pageCount: Int, text: @escaping (Int) -> String, onPage: @escaping (Int) -> Void
  ) {
    reading = Reading(page: page, pageCount: pageCount, text: text, onPage: onPage)
    speakPage(from: page)
  }

  /// Stops speaking.
  public func stop() {
    reading = nil
    engine.stop()
    isSpeaking = false
  }

  private func ended(finished: Bool) {
    guard finished, let reading else {
      self.reading = nil
      isSpeaking = false
      return
    }
    speakPage(from: reading.page + 1)
  }

  /// Speaks the first page with text from `start` on; at the end of the document, reading stops.
  private func speakPage(from start: Int) {
    guard var current = reading else { return }
    for index in max(0, start)..<max(start, current.pageCount) {
      let text = current.text(index).trimmingCharacters(in: .whitespacesAndNewlines)
      guard !text.isEmpty else { continue }
      current.page = index
      reading = current
      current.onPage(index)
      engine.speak(text)
      isSpeaking = true
      return
    }
    reading = nil
    isSpeaking = false
  }
}

/// The system voices.
///
/// The synthesizer is made on first use, so opening a document never waits for the voice database.
@MainActor
public final class SystemSpeechEngine: NSObject, SpeechEngine, AVSpeechSynthesizerDelegate {
  /// Called when the text being spoken ends; see `SpeechEngine.onEnd`.
  public var onEnd: ((_ finished: Bool) -> Void)?
  private var synthesizer: AVSpeechSynthesizer?
  /// The utterance being spoken, so the end of one replaced by a later `speak` isn't reported.
  private var current: ObjectIdentifier?

  /// Creates the engine without touching the system voices.
  override public init() {
    super.init()
  }

  /// Speaks text, replacing anything still being spoken.
  public func speak(_ text: String) {
    let synthesizer = self.synthesizer ?? AVSpeechSynthesizer()
    synthesizer.delegate = self
    self.synthesizer = synthesizer
    synthesizer.stopSpeaking(at: .immediate)
    let utterance = AVSpeechUtterance(string: text)
    current = ObjectIdentifier(utterance)
    synthesizer.speak(utterance)
  }

  /// Stops speaking; nothing happens before the first `speak`.
  public func stop() {
    synthesizer?.stopSpeaking(at: .immediate)
  }

  /// Called by the system when an utterance ends.
  nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance)
  {
    let id = ObjectIdentifier(utterance)
    Task { @MainActor in self.end(id, finished: true) }
  }

  /// Called by the system when speech is cancelled.
  nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance)
  {
    let id = ObjectIdentifier(utterance)
    Task { @MainActor in self.end(id, finished: false) }
  }

  private func end(_ id: ObjectIdentifier, finished: Bool) {
    guard id == current else { return }
    current = nil
    onEnd?(finished)
  }
}
