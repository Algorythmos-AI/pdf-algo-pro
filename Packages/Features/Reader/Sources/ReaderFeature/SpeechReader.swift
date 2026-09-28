import AVFoundation
import Observation

/// "Listen to this PDF" with the system voices (FR-READ-004).
@MainActor
@Observable
public final class SpeechReader: NSObject, AVSpeechSynthesizerDelegate {
  /// Whether speech is playing.
  public private(set) var isSpeaking = false
  @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()

  override init() {
    super.init()
    synthesizer.delegate = self
  }

  /// Speaks text in the system's default voice for its language.
  public func speak(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    synthesizer.stopSpeaking(at: .immediate)
    synthesizer.speak(AVSpeechUtterance(string: trimmed))
    isSpeaking = true
  }

  /// Stops speaking.
  public func stop() {
    synthesizer.stopSpeaking(at: .immediate)
    isSpeaking = false
  }

  /// Called by the system when an utterance ends.
  nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance)
  {
    Task { @MainActor in self.isSpeaking = false }
  }

  /// Called by the system when speech is cancelled.
  nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance)
  {
    Task { @MainActor in self.isSpeaking = false }
  }
}
