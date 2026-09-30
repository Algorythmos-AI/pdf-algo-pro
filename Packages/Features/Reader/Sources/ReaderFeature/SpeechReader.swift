import AVFoundation
import Observation

/// What speaks: the system voices in the app, a silent stand-in in tests.
///
/// Tests never touch the system voices: on the CI simulator their database can block the main thread
/// for minutes.
@MainActor
public protocol SpeechEngine: AnyObject {
  /// Called when speech ends on its own or is cancelled by the system.
  var onEnd: (() -> Void)? { get set }
  /// Speaks text, replacing anything still being spoken.
  func speak(_ text: String)
  /// Stops speaking.
  func stop()
}

/// "Listen to this PDF" with the system voices (FR-READ-004).
@MainActor
@Observable
public final class SpeechReader {
  /// Whether speech is playing.
  public private(set) var isSpeaking = false
  @ObservationIgnored private let engine: any SpeechEngine

  /// Creates a reader over an engine; the app uses the system voices.
  public init(engine: any SpeechEngine = SystemSpeechEngine()) {
    self.engine = engine
    engine.onEnd = { [weak self] in self?.isSpeaking = false }
  }

  /// Speaks text in the system's default voice for its language.
  public func speak(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    engine.speak(trimmed)
    isSpeaking = true
  }

  /// Stops speaking.
  public func stop() {
    engine.stop()
    isSpeaking = false
  }
}

/// The system voices.
///
/// The synthesizer is made on first use, so opening a document never waits for the voice database.
@MainActor
public final class SystemSpeechEngine: NSObject, SpeechEngine, AVSpeechSynthesizerDelegate {
  /// Called when speech ends on its own or is cancelled by the system.
  public var onEnd: (() -> Void)?
  private var synthesizer: AVSpeechSynthesizer?

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
    synthesizer.speak(AVSpeechUtterance(string: text))
  }

  /// Stops speaking; nothing happens before the first `speak`.
  public func stop() {
    synthesizer?.stopSpeaking(at: .immediate)
  }

  /// Called by the system when an utterance ends.
  nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance)
  {
    Task { @MainActor in self.onEnd?() }
  }

  /// Called by the system when speech is cancelled.
  nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance)
  {
    Task { @MainActor in self.onEnd?() }
  }
}
