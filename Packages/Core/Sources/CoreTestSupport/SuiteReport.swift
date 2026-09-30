import Foundation

/// Suite reports (OCR accuracy, AI evaluation, performance), written as files CI keeps.
///
/// A report is written to the folder named by the `REPORTS_DIR` environment variable, which the `ios`
/// job sets (`TEST_RUNNER_REPORTS_DIR`) and uploads as the `reports` artifact. Without it, nothing is
/// written, so local runs leave no files behind.
public enum SuiteReport {
  /// Writes a report, replacing an earlier one with the same name; failures are ignored because a
  /// report never decides whether a test passes.
  public static func write(_ text: String, named name: String) {
    guard let folder = ProcessInfo.processInfo.environment["REPORTS_DIR"], !folder.isEmpty else { return }
    let url = URL(fileURLWithPath: folder, isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try? Data(text.utf8).write(to: url.appendingPathComponent(name), options: .atomic)
  }
}
