import CoreGraphics
import Foundation

/// A saved ink signature (FR-EDIT-004): strokes in a unit box, so it can be placed at any size.
///
/// Points are stored from 0 to 1 across the signature's width and height; `aspectRatio` (width over
/// height) restores its shape when it is placed.
public struct SavedSignature: Codable, Equatable, Identifiable, Sendable {
  /// A point in the unit box, from the top-left corner.
  public struct Point: Codable, Equatable, Sendable {
    /// From 0 (left) to 1 (right).
    public var x: Double
    /// From 0 (top) to 1 (bottom).
    public var y: Double

    /// Creates a point.
    public init(x: Double, y: Double) {
      self.x = x
      self.y = y
    }
  }

  /// The signature's identity.
  public let id: UUID
  /// The strokes, each a list of points in drawing order.
  public var strokes: [[Point]]
  /// Width over height of the drawn signature.
  public var aspectRatio: Double
  /// When it was saved.
  public var createdAt: Date

  /// Creates a signature.
  public init(id: UUID = UUID(), strokes: [[Point]], aspectRatio: Double, createdAt: Date = Date()) {
    self.id = id
    self.strokes = strokes
    self.aspectRatio = aspectRatio
    self.createdAt = createdAt
  }

  /// A signature from strokes drawn in any coordinate space, fitted to the unit box.
  ///
  /// Returns `nil` when there is nothing to keep: no stroke, or strokes that are a single point.
  public init?(drawn strokes: [[CGPoint]], id: UUID = UUID(), createdAt: Date = Date()) {
    let points = strokes.flatMap(\.self)
    guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(), let minY = points.map(\.y).min(),
      let maxY = points.map(\.y).max()
    else { return nil }
    let width = maxX - minX
    let height = maxY - minY
    guard max(width, height) > 0 else { return nil }
    // A straight stroke still gets a box with some height or width, so it keeps its shape.
    let boxWidth = max(width, height / 10)
    let boxHeight = max(height, width / 10)
    self.init(
      id: id,
      strokes: strokes.filter { !$0.isEmpty }.map { stroke in
        stroke.map { Point(x: Double(($0.x - minX) / boxWidth), y: Double(($0.y - minY) / boxHeight)) }
      },
      aspectRatio: Double(boxWidth / boxHeight), createdAt: createdAt)
  }
}

/// Where saved signatures are kept: the Keychain, on this device only (FR-EDIT-004, threat model).
///
/// Signatures are restricted data (docs/data-classification.md): never stored inside documents except
/// where placed, never synced by default, never sent to any AI tier.
public protocol SignatureStoring: Sendable {
  /// Every saved signature, oldest first.
  func signatures() async throws -> [SavedSignature]
  /// Saves a signature, replacing one with the same identity.
  func save(_ signature: SavedSignature) async throws
  /// Deletes a signature; deleting one that does not exist is not an error.
  func delete(_ id: UUID) async throws
}

/// Errors from signature storage.
public enum SignatureStoreError: Error, Equatable, Sendable {
  /// The Keychain refused the operation; the status is the `OSStatus` it returned.
  case keychain(Int32)
}
