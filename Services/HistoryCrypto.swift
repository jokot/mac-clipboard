import Foundation
import CryptoKit
import Security

enum HistoryCryptoError: Error {
    case sealFailed
    case keychainStatus(OSStatus)
}

/// Holds the raw bytes of the history key.
protocol HistoryKeyStore: AnyObject {
    func read() throws -> Data?
    func write(_ data: Data) throws
    func delete()
}

enum HistoryCrypto {

    /// Under XCTest, the key stays in memory, so tests never read or change the real Keychain item.
    static var keyStore: HistoryKeyStore = AppEnvironment.isRunningTests ? InMemoryKeyStore() : KeychainKeyStore()

    // MARK: - Public

    static func seal(_ plaintext: Data) throws -> Data {
        let k = try key()
        let sealed = try AES.GCM.seal(plaintext, using: k)
        guard let combined = sealed.combined else {
            throw HistoryCryptoError.sealFailed
        }
        return combined
    }

    static func open(_ ciphertext: Data) throws -> Data {
        let k = try key()
        let box = try AES.GCM.SealedBox(combined: ciphertext)
        return try AES.GCM.open(box, using: k)
    }

    static func key() throws -> SymmetricKey {
        if let existing = try keyStore.read() { return SymmetricKey(data: existing) }
        let new = SymmetricKey(size: .bits256)
        try keyStore.write(new.withUnsafeBytes { Data($0) })
        return new
    }

    /// Removes the key. Call this only when no file on disk is encrypted with it.
    static func deleteKey() {
        keyStore.delete()
    }
}

/// Keeps the key in the login Keychain.
final class KeychainKeyStore: HistoryKeyStore {

    private let service = "com.jokot.MacClipboard.HistoryEncryptionKey"
    private let account = "default"

    func read() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            return item as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw HistoryCryptoError.keychainStatus(status)
        }
    }

    func write(_ data: Data) throws {
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: data,
        ]
        SecItemDelete(attrs as CFDictionary)
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw HistoryCryptoError.keychainStatus(status)
        }
    }

    func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

final class InMemoryKeyStore: HistoryKeyStore {
    private var data: Data?
    func read() throws -> Data? { data }
    func write(_ data: Data) throws { self.data = data }
    func delete() { data = nil }
}

/// Static one-launch flag set by the repository when decryption fails.
enum HistoryDecryptFailure {
    private static let lock = NSLock()
    private static var _didFailOnThisLaunch = false

    static var didFailOnThisLaunch: Bool {
        lock.lock(); defer { lock.unlock() }
        return _didFailOnThisLaunch
    }

    static func flag() {
        lock.lock(); defer { lock.unlock() }
        _didFailOnThisLaunch = true
    }
}
