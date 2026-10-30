import Core
import Foundation

/// Holds inspections until a test lets them go, so the test can act while one runs.
public actor InspectionGate {
  private var held: [CheckedContinuation<Void, Never>] = []
  private var isOpen = false
  /// How many inspections have reached the gate.
  public private(set) var arrivals = 0

  /// Creates a closed gate.
  public init() {}

  /// Waits here until the gate opens.
  public func pass() async {
    arrivals += 1
    guard !isOpen else { return }
    await withCheckedContinuation { held.append($0) }
  }

  /// Lets every held inspection go, and all later ones through.
  public func open() {
    isOpen = true
    for continuation in held { continuation.resume() }
    held = []
  }

  /// Waits until an inspection is held at the gate.
  public func waitForArrival() async {
    while arrivals == 0 { await Task.yield() }
  }
}

/// An inspector that waits at a gate, then returns a fixed result.
public struct GatedInspector: PDFInspecting {
  /// The gate inspections wait at.
  public let gate: InspectionGate
  /// What every inspection returns.
  public let result: PDFInspection

  /// Creates an inspector held at `gate`.
  public init(
    gate: InspectionGate,
    result: PDFInspection = PDFInspection(
      pageCount: 1, isEncrypted: false, pages: [PageText(pageIndex: 0, text: "Hello")])
  ) {
    self.gate = gate
    self.result = result
  }

  /// Waits at the gate, then returns the result.
  public func inspect(_ url: URL) async throws -> PDFInspection {
    await gate.pass()
    return result
  }
}
