import Foundation
@testable import MaClip

/// Counts key reads, so a test can prove that a code path never touches the key.
final class SpyKeyStore: HistoryKeyStore {
    private(set) var data: Data?
    private(set) var readCount = 0
    private(set) var deleteCount = 0
    /// Acts like a person who clicks Deny in the Keychain prompt.
    var failReads = false

    func read() throws -> Data? {
        readCount += 1
        if failReads { throw HistoryCryptoError.keychainStatus(-128) }
        return data
    }

    func write(_ data: Data) throws { self.data = data }

    func delete() {
        deleteCount += 1
        data = nil
    }

    func resetCounts() {
        readCount = 0
        deleteCount = 0
    }
}
