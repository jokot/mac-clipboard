import Foundation
import CryptoKit
import Security

enum HistoryCryptoError: Error {
    case sealFailed
    case keychainStatus(OSStatus)
}

enum HistoryCrypto {

    private static let service = "com.jokot.MacClipboard.HistoryEncryptionKey"
    private static let account = "default"

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
        if let existing = try fetchKey() { return existing }
        let new = SymmetricKey(size: .bits256)
        try storeKey(new)
        return new
    }

    // MARK: - Keychain

    private static func fetchKey() throws -> SymmetricKey? {
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
            guard let data = item as? Data else { return nil }
            return SymmetricKey(data: data)
        case errSecItemNotFound:
            return nil
        default:
            throw HistoryCryptoError.keychainStatus(status)
        }
    }

    private static func storeKey(_ key: SymmetricKey) throws {
        let data = key.withUnsafeBytes { Data($0) }
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
