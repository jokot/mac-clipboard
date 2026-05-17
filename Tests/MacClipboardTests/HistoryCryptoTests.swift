import XCTest
import CryptoKit
@testable import MaClip

final class HistoryCryptoTests: XCTestCase {

    func test_sealOpenRoundTrip() throws {
        let plaintext = Data("hello world".utf8)
        let ciphertext = try HistoryCrypto.seal(plaintext)
        let recovered = try HistoryCrypto.open(ciphertext)
        XCTAssertEqual(recovered, plaintext)
    }

    func test_sealNonceIsRandom() throws {
        let plaintext = Data("same input".utf8)
        let a = try HistoryCrypto.seal(plaintext)
        let b = try HistoryCrypto.seal(plaintext)
        XCTAssertNotEqual(a, b, "AES-GCM should use a fresh random nonce per seal")
    }

    func test_tamperedCiphertextFailsAuth() throws {
        let plaintext = Data("hello".utf8)
        var ciphertext = try HistoryCrypto.seal(plaintext)
        ciphertext[ciphertext.count / 2] ^= 0x01
        XCTAssertThrowsError(try HistoryCrypto.open(ciphertext))
    }

    func test_keyIsIdempotent() throws {
        let a = try HistoryCrypto.key()
        let b = try HistoryCrypto.key()
        XCTAssertEqual(a.withUnsafeBytes { Data($0) },
                       b.withUnsafeBytes { Data($0) })
    }
}
