/// One lane per document: refreshes of the same document run one at a time, in the order they were
/// asked for, so a stale refresh can never land after a newer one (#236).
///
/// Refreshes of different documents still run side by side.
public actor RefreshLanes {
  /// The lanes every intake shares unless given its own: one library, one set of lanes.
  public static let shared = RefreshLanes()

  private var busy: Set<DocumentID> = []
  private var waiting: [DocumentID: [CheckedContinuation<Void, Never>]] = [:]

  /// Creates empty lanes.
  public init() {}

  /// Waits for the document's lane, then holds it until `leave(_:)`.
  public func enter(_ id: DocumentID) async {
    guard busy.contains(id) else {
      busy.insert(id)
      return
    }
    // The one leaving hands the lane over directly, so it stays busy.
    await withCheckedContinuation { waiting[id, default: []].append($0) }
  }

  /// Leaves the document's lane, handing it to the next refresh waiting, if any.
  public func leave(_ id: DocumentID) {
    guard var queue = waiting[id], !queue.isEmpty else {
      busy.remove(id)
      waiting[id] = nil
      return
    }
    let next = queue.removeFirst()
    waiting[id] = queue.isEmpty ? nil : queue
    next.resume()
  }
}
