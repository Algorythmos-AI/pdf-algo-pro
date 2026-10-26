import CommonCrypto
import CryptoKit
import Foundation
import Security

/// The standard security handler (ISO 32000-1, 7.6.3) at the two revisions PDFKit writes, for the
/// strings the save's repair adds to an encrypted file (#309): revision 3 with RC4, which iOS 27
/// writes, and revision 4 with AES-128, which macOS writes.
///
/// It derives the file key from the user password (Algorithm 2), checks it against the file's `/U`
/// (Algorithms 5 and 6), and encrypts a string with the object's own key (Algorithm 1). Any other
/// handler, revision or cipher is not attempted: `init` returns `nil`, and the repair leaves the
/// outline as PDFKit wrote it.
struct PDFStandardSecurity {
  /// How strings are encrypted.
  enum Cipher: Equatable {
    /// RC4 with a file key of this many bytes: revision 3, `/V 2`.
    case rc4(keyLength: Int)
    /// AES-128 in CBC mode: revision 4, `/V 4` with `/CFM /AESV2`.
    case aes128

    var keyLength: Int {
      switch self {
      case .rc4(let keyLength): keyLength
      case .aes128: 16
      }
    }
  }

  private let cipher: Cipher
  private let fileKey: [UInt8]

  private static let padding: [UInt8] = [
    0x28, 0xBF, 0x4E, 0x5E, 0x4E, 0x75, 0x8A, 0x41, 0x64, 0x00, 0x4E, 0x56, 0xFF, 0xFA, 0x01, 0x08,
    0x2E, 0x2E, 0x00, 0xB6, 0xD0, 0x68, 0x3E, 0x80, 0x2F, 0x0C, 0xA9, 0xFE, 0x64, 0x53, 0x69, 0x7A,
  ]

  /// The handler for an `/Encrypt` dictionary, or `nil` when the password doesn't open the file.
  ///
  /// - Parameters:
  ///   - cipher: the cipher the dictionary names.
  ///   - owner: the `/O` string's bytes.
  ///   - user: the `/U` string's bytes.
  ///   - permissions: `/P`.
  ///   - firstID: the bytes of the trailer's first `/ID` string.
  ///   - encryptsMetadata: `/EncryptMetadata`, true when absent; read at revision 4 only.
  ///   - password: the user password; empty when the file opens without one.
  init?(
    cipher: Cipher, owner: [UInt8], user: [UInt8], permissions: Int32, firstID: [UInt8], encryptsMetadata: Bool,
    password: String
  ) {
    let length = cipher.keyLength
    guard (5...16).contains(length), owner.count >= 32, user.count >= 16 else { return nil }
    // Algorithm 2: the file key.
    let typed = Array(password.unicodeScalars.prefix(32).map { UInt8(truncatingIfNeeded: $0.value) })
    var input = typed + Self.padding.prefix(32 - typed.count)
    input += owner.prefix(32)
    let p = UInt32(bitPattern: permissions)
    input += [UInt8(p & 0xFF), UInt8((p >> 8) & 0xFF), UInt8((p >> 16) & 0xFF), UInt8((p >> 24) & 0xFF)]
    input += firstID
    if cipher == .aes128, !encryptsMetadata { input += [0xFF, 0xFF, 0xFF, 0xFF] }
    var key = Array(Insecure.MD5.hash(data: input))
    for _ in 0..<50 { key = Array(Insecure.MD5.hash(data: key.prefix(length))) }
    key = Array(key.prefix(length))
    // Algorithms 5 and 6: the password is right when it reproduces the first 16 bytes of /U.
    var check = Array(Insecure.MD5.hash(data: Self.padding + firstID))
    for round in 0..<20 {
      guard let next = Self.rc4(check, key: key.map { $0 ^ UInt8(round) }) else { return nil }
      check = next
    }
    guard check == Array(user.prefix(16)) else { return nil }
    self.cipher = cipher
    fileKey = key
  }

  /// `plain` encrypted for object `number`: with RC4, or with AES-128-CBC behind a random 16-byte IV and
  /// with PKCS #7 padding.
  func encrypt(_ plain: [UInt8], object number: Int, generation: Int) -> [UInt8]? {
    let salt =
      [UInt8(number & 0xFF), UInt8((number >> 8) & 0xFF), UInt8((number >> 16) & 0xFF)]
      + [UInt8(generation & 0xFF), UInt8((generation >> 8) & 0xFF)]
    switch cipher {
    case .rc4:
      let objectKey = Array(Insecure.MD5.hash(data: fileKey + salt).prefix(min(fileKey.count + 5, 16)))
      return Self.rc4(plain, key: objectKey)
    case .aes128:
      let objectKey = Array(Insecure.MD5.hash(data: fileKey + salt + Array("sAlT".utf8)).prefix(16))
      var iv = [UInt8](repeating: 0, count: kCCBlockSizeAES128)
      guard SecRandomCopyBytes(kSecRandomDefault, iv.count, &iv) == errSecSuccess else { return nil }
      var output = [UInt8](repeating: 0, count: plain.count + kCCBlockSizeAES128)
      var written = 0
      let status = CCCrypt(
        CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
        objectKey, objectKey.count, iv, plain, plain.count, &output, output.count, &written)
      guard status == kCCSuccess else { return nil }
      return iv + output.prefix(written)
    }
  }

  private static func rc4(_ data: [UInt8], key: [UInt8]) -> [UInt8]? {
    var output = [UInt8](repeating: 0, count: data.count)
    var written = 0
    let status = CCCrypt(
      CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmRC4), 0, key, key.count, nil, data, data.count, &output,
      output.count, &written)
    return status == kCCSuccess ? Array(output.prefix(written)) : nil
  }
}
