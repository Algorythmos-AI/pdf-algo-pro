#if canImport(MetricKit)
  import Foundation
  import MetricKit

  /// Receives MetricKit's diagnostic reports and keeps a summary of each in the diagnostics log (P6).
  ///
  /// MetricKit delivers reports on a device only, at most once a day and on the next launch after a
  /// crash; the simulator never calls it, so this adapter is checked on a device before each release
  /// (scripts/ci/coverage_gate.py, DEVICE_ONLY). Everything it records is tested in `DiagnosticsLog`.
  public final class MetricKitCollector: NSObject, MXMetricManagerSubscriber, Sendable {
    private let log: DiagnosticsLog

    /// Creates a collector that writes to a log.
    public init(log: DiagnosticsLog) {
      self.log = log
    }

    /// Subscribes, and records the reports delivered before this launch.
    public func start() {
      MXMetricManager.shared.add(self)
      receive(MXMetricManager.shared.pastDiagnosticPayloads)
    }

    /// Records newly delivered reports.
    public func didReceive(_ payloads: [MXDiagnosticPayload]) {
      receive(payloads)
    }

    private func receive(_ payloads: [MXDiagnosticPayload]) {
      let records = payloads.flatMap(Self.records(in:))
      guard !records.isEmpty else { return }
      Task { await log.add(records) }
    }

    private static func records(in payload: MXDiagnosticPayload) -> [DiagnosticRecord] {
      let date = payload.timeStampEnd
      func record(_ kind: DiagnosticRecord.Kind, _ diagnostic: MXDiagnostic, _ detail: String?) -> DiagnosticRecord {
        DiagnosticRecord(kind: kind, date: date, build: diagnostic.metaData.applicationBuildVersion, detail: detail)
      }
      var records: [DiagnosticRecord] = []
      for crash in payload.crashDiagnostics ?? [] {
        let reason = [crash.exceptionType.map { "exception \($0)" }, crash.signal.map { "signal \($0)" }]
          .compactMap(\.self).joined(separator: ", ")
        records.append(record(.crash, crash, reason.isEmpty ? nil : reason))
      }
      for hang in payload.hangDiagnostics ?? [] {
        records.append(record(.hang, hang, hang.hangDuration.formatted()))
      }
      for exception in payload.cpuExceptionDiagnostics ?? [] {
        records.append(record(.cpuException, exception, exception.totalCPUTime.formatted()))
      }
      for exception in payload.diskWriteExceptionDiagnostics ?? [] {
        records.append(record(.diskWriteException, exception, exception.totalWritesCaused.formatted()))
      }
      #if os(iOS)
        for launch in payload.appLaunchDiagnostics ?? [] {
          records.append(record(.launch, launch, launch.launchDuration.formatted()))
        }
      #endif
      return records
    }
  }
#endif
