import Foundation
import Security

enum LocalVaultKeyStore {
  private static let service = "bimotc.com.local"
  private static let account = "local_vault_key_v1"
  private static let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")

  static func getOrCreateCacheKey() throws -> String {
    if let saved = try readKey(), !saved.isEmpty {
      return saved
    }
    let key = newCryptKey()
    try saveKey(key)
    return key
  }

  private static func readKey() throws -> String? {
    var query = baseQuery()
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound {
      return nil
    }
    guard status == errSecSuccess else {
      throw KeyStoreError.security(status)
    }
    guard let data = item as? Data else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  private static func saveKey(_ key: String) throws {
    var query = baseQuery()
    query[kSecValueData as String] = Data(key.utf8)
    query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let status = SecItemAdd(query as CFDictionary, nil)
    if status == errSecDuplicateItem {
      let updateStatus = SecItemUpdate(
        baseQuery() as CFDictionary,
        [kSecValueData as String: Data(key.utf8)] as CFDictionary
      )
      guard updateStatus == errSecSuccess else {
        throw KeyStoreError.security(updateStatus)
      }
      return
    }
    guard status == errSecSuccess else {
      throw KeyStoreError.security(status)
    }
  }

  private static func baseQuery() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }

  private static func newCryptKey() -> String {
    var result = ""
    for _ in 0..<16 {
      result.append(alphabet[Int.random(in: 0..<alphabet.count)])
    }
    return result
  }
}

enum KeyStoreError: Error {
  case security(OSStatus)
}
