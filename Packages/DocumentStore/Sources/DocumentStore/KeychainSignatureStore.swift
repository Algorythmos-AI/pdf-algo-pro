import Core
import Foundation
import Security

/// Saved signatures in the Keychain (FR-EDIT-004): on this device only, never synced, and readable only
/// while the device is unlocked, as restricted data requires (docs/data-classification.md).
///
/// Each signature is one generic-password item in the app's default access group, keyed by its
/// identity; its value is the signature's JSON.
public struct KeychainSignatureStore: SignatureStoring {
  /// The Keychain service every signature item shares.
  public static let defaultService = "com.algorythmos.pdfalgopro.signatures"

  private let service: String

  /// Creates a store; tests pass their own service so they never touch the app's signatures.
  public init(service: String = KeychainSignatureStore.defaultService) {
    self.service = service
  }

  /// Every saved signature, oldest first; items that cannot be read are skipped.
  public func signatures() async throws -> [SavedSignature] {
    var query = base
    query[kSecMatchLimit] = kSecMatchLimitAll
    query[kSecReturnData] = true
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return [] }
    guard status == errSecSuccess, let items = result as? [Data] else { throw SignatureStoreError.keychain(status) }
    return items.compactMap { try? JSONDecoder().decode(SavedSignature.self, from: $0) }
      .sorted { $0.createdAt < $1.createdAt }
  }

  /// Saves a signature, replacing one with the same identity.
  public func save(_ signature: SavedSignature) async throws {
    let data = try JSONEncoder().encode(signature)
    var query = base
    query[kSecAttrAccount] = signature.id.uuidString
    let updated = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
    if updated == errSecSuccess { return }
    guard updated == errSecItemNotFound else { throw SignatureStoreError.keychain(updated) }
    query[kSecValueData] = data
    query[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    let added = SecItemAdd(query as CFDictionary, nil)
    guard added == errSecSuccess else { throw SignatureStoreError.keychain(added) }
  }

  /// Deletes a signature; deleting one that does not exist is not an error.
  public func delete(_ id: UUID) async throws {
    var query = base
    query[kSecAttrAccount] = id.uuidString
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else { throw SignatureStoreError.keychain(status) }
  }

  private var base: [CFString: Any] {
    [
      kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrSynchronizable: false,
      kSecUseDataProtectionKeychain: true,
    ]
  }
}
