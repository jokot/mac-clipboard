import XCTest
import CryptoKit
import Security
@testable import MaClip

/// Every key is made at run time, and every `-----BEGIN` line is joined from parts, so no
/// private key is in the repo. The one fixed key is the public RFC 8032 test 1 key.
final class PrivateKeyInspectorTests: XCTestCase {
    private let rfcPublic = PrivateKeyInspectorTests.bytes("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a")
    private let rfcSeed = PrivateKeyInspectorTests.bytes("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60")
    private let rfcLine = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdamAGCsQq31Uv+08lkBzoO4XLz2qYjJa8CGmj3B1Ea"
    private let rfcFingerprint = "SHA256:bbXpuKG6zhzdmnxq256TlqzFBzRl2f6OOg722cYNbU8"

    private static func bytes(_ hex: String) -> [UInt8] {
        var out: [UInt8] = []
        var i = hex.startIndex
        while i < hex.endIndex {
            let j = hex.index(i, offsetBy: 2)
            out.append(UInt8(hex[i..<j], radix: 16)!)
            i = j
        }
        return out
    }

    private func pem(_ label: String, _ der: [UInt8], headers: String = "") -> String {
        let b64 = Data(der).base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return "-----" + "BEGIN " + label + "-----\n" + headers + b64 + "\n-----" + "END " + label + "-----\n"
    }

    private func u32(_ n: Int) -> [UInt8] { [UInt8(n >> 24 & 0xff), UInt8(n >> 16 & 0xff), UInt8(n >> 8 & 0xff), UInt8(n & 0xff)] }
    private func sshString(_ d: [UInt8]) -> [UInt8] { u32(d.count) + d }
    private func sshString(_ s: String) -> [UInt8] { sshString(Array(s.utf8)) }

    private func openSSHBody(cipher: String) -> [UInt8] {
        let blob = sshString("ssh-ed25519") + sshString(rfcPublic)
        let random = (0..<64).map { _ in UInt8.random(in: 0...255) }
        let kdf = cipher == "none" ? "none" : "bcrypt"
        let kdfOptions: [UInt8] = cipher == "none" ? [] : sshString(Array(repeating: 7, count: 16)) + u32(16)
        var body: [UInt8] = Array("openssh-key-v1".utf8)
        body += [0]
        body += sshString(cipher)
        body += sshString(kdf)
        body += sshString(kdfOptions)
        body += u32(1)
        body += sshString(blob)
        body += sshString(random)
        return body
    }

    func test_openSSHEd25519() throws {
        let info = try XCTUnwrap(PrivateKeyInspector.inspect(pem("OPENSSH PRIVATE KEY", openSSHBody(cipher: "none"))))
        XCTAssertEqual(info.algorithm, .ed25519)
        XCTAssertFalse(info.isEncrypted)
        XCTAssertEqual(info.publicKeyLine, rfcLine)
        XCTAssertEqual(info.fingerprint, rfcFingerprint)
        XCTAssertEqual(info.typeText, "Ed25519")
        XCTAssertEqual(info.fileName, "id_ed25519")
    }

    func test_openSSHWithAPassphraseStillGivesThePublicKey() throws {
        let info = try XCTUnwrap(PrivateKeyInspector.inspect(pem("OPENSSH PRIVATE KEY", openSSHBody(cipher: "aes256-ctr"))))
        XCTAssertTrue(info.isEncrypted)
        XCTAssertEqual(info.publicKeyLine, rfcLine)
        XCTAssertEqual(info.fingerprint, rfcFingerprint)
    }

    func test_pkcs8Ed25519() throws {
        let der = Self.bytes("302e020100300506032b657004220420") + rfcSeed
        let info = try XCTUnwrap(PrivateKeyInspector.inspect("text before\n" + pem("PRIVATE KEY", der)))
        XCTAssertEqual(info.algorithm, .ed25519)
        XCTAssertEqual(info.fingerprint, rfcFingerprint)
        XCTAssertEqual(info.publicKeyLine, rfcLine)
    }

    func test_pkcs8P256() throws {
        let key = P256.Signing.PrivateKey()
        let info = try XCTUnwrap(PrivateKeyInspector.inspect(key.pemRepresentation))
        XCTAssertEqual(info.algorithm, .ecdsa(curve: "P-256"))
        XCTAssertEqual(info.typeText, "ECDSA P-256")
        XCTAssertEqual(info.fileName, "id_ecdsa")
        let line = try XCTUnwrap(info.publicKeyLine)
        XCTAssertTrue(line.hasPrefix("ecdsa-sha2-nistp256 "))
        let blob = sshString("ecdsa-sha2-nistp256") + sshString("nistp256") + sshString(Array(key.publicKey.x963Representation))
        XCTAssertEqual(line, "ecdsa-sha2-nistp256 " + Data(blob).base64EncodedString())
    }

    func test_sec1P256() throws {
        let key = P256.Signing.PrivateKey()
        let k = Array(key.rawRepresentation), q = Array(key.publicKey.x963Representation)
        var der: [UInt8] = [0x30, 0x77, 0x02, 0x01, 0x01, 0x04, 0x20]
        der += k
        der += [0xA0, 0x0A, 0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07]
        der += [0xA1, 0x44, 0x03, 0x42, 0x00]
        der += q
        let info = try XCTUnwrap(PrivateKeyInspector.inspect(pem("EC PRIVATE KEY", der)))
        XCTAssertEqual(info.algorithm, .ecdsa(curve: "P-256"))
        let blob = sshString("ecdsa-sha2-nistp256") + sshString("nistp256") + sshString(q)
        XCTAssertEqual(info.publicKeyLine, "ecdsa-sha2-nistp256 " + Data(blob).base64EncodedString())
    }

    func test_pkcs1RSA() throws {
        let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                                         kSecAttrKeySizeInBits as String: 2048,
                                         kSecAttrIsPermanent as String: false]
        var error: Unmanaged<CFError>?
        let key = try XCTUnwrap(SecKeyCreateRandomKey(attributes as CFDictionary, &error))
        let der = try XCTUnwrap(SecKeyCopyExternalRepresentation(key, &error) as Data?)
        let info = try XCTUnwrap(PrivateKeyInspector.inspect(pem("RSA PRIVATE KEY", Array(der))))
        XCTAssertEqual(info.algorithm, .rsa(bits: 2048))
        XCTAssertEqual(info.typeText, "RSA 2048")
        XCTAssertEqual(info.fileName, "id_rsa")
        let line = try XCTUnwrap(info.publicKeyLine)
        let blob = try XCTUnwrap(Data(base64Encoded: String(line.dropFirst("ssh-rsa ".count))))
        XCTAssertTrue(line.hasPrefix("ssh-rsa "))
        // string "ssh-rsa", then mpint e = 65537.
        var expected: [UInt8] = u32(7)
        expected += Array("ssh-rsa".utf8)
        expected += u32(3)
        expected += [1, 0, 1]
        XCTAssertEqual(Array(blob.prefix(18)), expected)
        XCTAssertNotNil(info.fingerprint)
    }

    func test_encryptedPEMHasNoPublicKey() throws {
        let random = (0..<200).map { _ in UInt8.random(in: 0...255) }
        let pkcs8 = try XCTUnwrap(PrivateKeyInspector.inspect(pem("ENCRYPTED PRIVATE KEY", random)))
        XCTAssertTrue(pkcs8.isEncrypted)
        XCTAssertNil(pkcs8.publicKeyLine)
        XCTAssertEqual(pkcs8.typeText, "Private key")

        let legacy = try XCTUnwrap(PrivateKeyInspector.inspect(pem("RSA PRIVATE KEY", random,
            headers: "Proc-Type: 4,ENCRYPTED\nDEK-Info: AES-128-CBC,00112233445566778899AABBCCDDEEFF\n\n")))
        XCTAssertTrue(legacy.isEncrypted)
        XCTAssertNil(legacy.publicKeyLine)
        XCTAssertEqual(legacy.typeText, "Private key")
    }

    func test_dsaAndPGP() {
        XCTAssertEqual(PrivateKeyInspector.inspect(pem("DSA PRIVATE KEY", [1, 2, 3]))?.algorithm, .dsa)
        XCTAssertEqual(PrivateKeyInspector.inspect(pem("PGP PRIVATE KEY BLOCK", [1, 2, 3]))?.algorithm, .pgp)
        XCTAssertNil(PrivateKeyInspector.inspect(pem("DSA PRIVATE KEY", [1, 2, 3]))?.publicKeyLine)
        XCTAssertEqual(PrivateKeyInspector.inspect(pem("DSA PRIVATE KEY", [1, 2, 3]))?.typeText, "DSA key")
    }

    func test_keyBlockIsTheBlockOnly() throws {
        let block = pem("OPENSSH PRIVATE KEY", openSSHBody(cipher: "none"))
        let info = try XCTUnwrap(PrivateKeyInspector.inspect("before\n" + block + "after"))
        XCTAssertEqual(info.keyBlock, block.trimmingCharacters(in: .newlines))
    }

    func test_noBlockIsNil() {
        XCTAssertNil(PrivateKeyInspector.inspect("no key here"))
    }

    func test_randomBytesNeverCrash() {
        for label in ["OPENSSH PRIVATE KEY", "RSA PRIVATE KEY", "EC PRIVATE KEY", "PRIVATE KEY"] {
            for _ in 0..<250 {
                let body = (0..<Int.random(in: 0...600)).map { _ in UInt8.random(in: 0...255) }
                XCTAssertNotNil(PrivateKeyInspector.inspect(pem(label, body)))
            }
        }
        // Valid starts with lengths that point past the end.
        XCTAssertNotNil(PrivateKeyInspector.inspect(pem("OPENSSH PRIVATE KEY", Array("openssh-key-v1".utf8) + [0, 0xff, 0xff, 0xff, 0xff])))
        XCTAssertNotNil(PrivateKeyInspector.inspect(pem("PRIVATE KEY", [0x30, 0x84, 0xff, 0xff, 0xff, 0xff, 0x02])))
        XCTAssertNotNil(PrivateKeyInspector.inspect(pem("RSA PRIVATE KEY", [0x30, 0x82, 0x01])))
    }
}
