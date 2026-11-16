import Foundation
import CryptoKit

/// The facts about a private key that MaClip can show without the value.
struct PrivateKeyInfo: Equatable {
    enum Algorithm: Equatable {
        case ed25519
        case rsa(bits: Int)
        case ecdsa(curve: String)
        case dsa
        case pgp
        case unknown
    }

    let algorithm: Algorithm
    let isEncrypted: Bool
    /// The public key as in a `.pub` file, without a comment: `ssh-ed25519 AAAA…`.
    let publicKeyLine: String?
    /// The fingerprint as `ssh-keygen -lf` prints it: `SHA256:…`.
    let fingerprint: String?
    /// The key from its first line to its last line.
    let keyBlock: String

    var typeText: String {
        switch algorithm {
        case .ed25519: return "Ed25519"
        case .rsa(let bits): return "RSA \(bits)"
        case .ecdsa(let curve): return "ECDSA \(curve)"
        case .dsa: return "DSA key"
        case .pgp: return "PGP key"
        case .unknown: return "Private key"
        }
    }

    /// The usual file name in `~/.ssh`.
    var fileName: String {
        switch algorithm {
        case .ed25519: return "id_ed25519"
        case .rsa: return "id_rsa"
        case .ecdsa: return "id_ecdsa"
        case .dsa, .pgp, .unknown: return "private_key"
        }
    }
}

/// Reads the first private key in a text. It uses no Keychain, never decrypts a key, and
/// gives a "Private key" result for input that it cannot read.
enum PrivateKeyInspector {
    private static let block = try! NSRegularExpression(pattern:
        #"-----BEGIN ((?:RSA |EC |DSA |OPENSSH |ENCRYPTED |PGP )?PRIVATE KEY(?: BLOCK)?)-----([\s\S]*?)(?:-----END (?:RSA |EC |DSA |OPENSSH |ENCRYPTED |PGP )?PRIVATE KEY(?: BLOCK)?-----|\z)"#)

    /// The SSH key type and the curve name of each curve, by curve OID.
    private struct Curve {
        let name: String, sshName: String, oid: [UInt8], scalarSize: Int
    }
    private static let curves = [
        Curve(name: "P-256", sshName: "nistp256", oid: [0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07], scalarSize: 32),
        Curve(name: "P-384", sshName: "nistp384", oid: [0x2B, 0x81, 0x04, 0x00, 0x22], scalarSize: 48),
        Curve(name: "P-521", sshName: "nistp521", oid: [0x2B, 0x81, 0x04, 0x00, 0x23], scalarSize: 66),
    ]
    private static let rsaOID: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]
    private static let ecOID: [UInt8] = [0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01]
    private static let ed25519OID: [UInt8] = [0x2B, 0x65, 0x70]

    static func inspect(_ text: String) -> PrivateKeyInfo? {
        let ns = text as NSString
        guard let m = block.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let label = ns.substring(with: m.range(at: 1))
        let keyBlock = ns.substring(with: m.range).trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = ns.substring(with: m.range(at: 2)).components(separatedBy: .newlines)
        let headers = lines.filter { $0.contains(":") }
        let base64 = lines.filter { !$0.contains(":") }.joined()
            .trimmingCharacters(in: .whitespaces)
        let der = Data(base64Encoded: base64, options: .ignoreUnknownCharacters).map(Array.init) ?? []

        func result(_ algorithm: PrivateKeyInfo.Algorithm, encrypted: Bool = false, blob: [UInt8]? = nil,
                    keyType: String? = nil) -> PrivateKeyInfo {
            var line: String?, fingerprint: String?
            if let blob, let keyType {
                line = keyType + " " + Data(blob).base64EncodedString()
                let digest = Data(SHA256.hash(data: Data(blob))).base64EncodedString()
                fingerprint = "SHA256:" + digest.trimmingCharacters(in: CharacterSet(charactersIn: "="))
            }
            return PrivateKeyInfo(algorithm: algorithm, isEncrypted: encrypted, publicKeyLine: line,
                                  fingerprint: fingerprint, keyBlock: keyBlock)
        }
        let unknown = result(.unknown)

        switch label {
        case "OPENSSH PRIVATE KEY":
            return openSSH(der, result: result) ?? unknown
        case "ENCRYPTED PRIVATE KEY":
            return result(.unknown, encrypted: true)
        case "DSA PRIVATE KEY":
            return result(.dsa)
        case "PGP PRIVATE KEY BLOCK":
            return result(.pgp)
        default:
            if headers.contains(where: { $0.hasPrefix("Proc-Type:") && $0.contains("ENCRYPTED") }) {
                return result(.unknown, encrypted: true)
            }
            let parsed: (PrivateKeyInfo.Algorithm, [UInt8], String)?
            switch label {
            case "RSA PRIVATE KEY": parsed = pkcs1(der)
            case "EC PRIVATE KEY": parsed = sec1(der, curve: nil)
            case "PRIVATE KEY": parsed = pkcs8(der)
            default: parsed = nil
            }
            guard let (algorithm, blob, keyType) = parsed else { return unknown }
            return result(algorithm, blob: blob, keyType: keyType)
        }
    }

    // MARK: - OpenSSH

    private static func openSSH(_ bytes: [UInt8],
                                result: (PrivateKeyInfo.Algorithm, Bool, [UInt8]?, String?) -> PrivateKeyInfo) -> PrivateKeyInfo? {
        let magic = Array("openssh-key-v1".utf8) + [0]
        guard bytes.count > magic.count, Array(bytes.prefix(magic.count)) == magic else { return nil }
        var reader = SSHReader(Array(bytes.dropFirst(magic.count)))
        guard let cipher = reader.readString(), reader.readString() != nil, reader.readString() != nil,
              let count = reader.readUInt32(), count >= 1, let blob = reader.readString() else { return nil }
        let encrypted = cipher != Array("none".utf8)
        var pub = SSHReader(blob)
        guard let typeBytes = pub.readString(), let keyType = String(bytes: typeBytes, encoding: .utf8) else {
            return result(.unknown, encrypted, nil, nil)
        }
        let algorithm: PrivateKeyInfo.Algorithm
        switch keyType {
        case "ssh-ed25519":
            algorithm = .ed25519
        case "ssh-rsa":
            guard pub.readString() != nil, let n = pub.readString() else { return result(.unknown, encrypted, nil, nil) }
            algorithm = .rsa(bits: bitLength(n))
        case let t where t.hasPrefix("ecdsa-sha2-"):
            let ssh = String(t.dropFirst("ecdsa-sha2-".count))
            algorithm = .ecdsa(curve: curves.first { $0.sshName == ssh }?.name ?? ssh)
        case "ssh-dss":
            algorithm = .dsa
        default:
            algorithm = .unknown
        }
        return result(algorithm, encrypted, blob, keyType)
    }

    // MARK: - PEM DER formats

    /// PKCS#1: SEQUENCE { version, n, e, … }.
    private static func pkcs1(_ der: [UInt8]) -> (PrivateKeyInfo.Algorithm, [UInt8], String)? {
        var outer = DERReader(der)
        guard let seq = outer.read(tag: DERReader.sequence) else { return nil }
        var r = DERReader(seq)
        guard r.read(tag: DERReader.integer) != nil,
              let n = r.read(tag: DERReader.integer), let e = r.read(tag: DERReader.integer) else { return nil }
        let blob = SSHWriter.string("ssh-rsa") + SSHWriter.mpint(e) + SSHWriter.mpint(n)
        return (.rsa(bits: bitLength(n)), blob, "ssh-rsa")
    }

    /// SEC1: SEQUENCE { version 1, OCTET STRING k, [0] curve OID, [1] BIT STRING public point }.
    private static func sec1(_ der: [UInt8], curve hint: Curve?) -> (PrivateKeyInfo.Algorithm, [UInt8], String)? {
        var outer = DERReader(der)
        guard let seq = outer.read(tag: DERReader.sequence) else { return nil }
        var r = DERReader(seq)
        guard r.read(tag: DERReader.integer) != nil, let scalar = r.read(tag: DERReader.octetString) else { return nil }
        var curve = hint
        var point: [UInt8]?
        while let element = r.read() {
            if element.tag == 0xA0 {
                var p = DERReader(element.content)
                if let oid = p.read(tag: DERReader.objectID) { curve = curves.first { $0.oid == oid } ?? curve }
            } else if element.tag == 0xA1 {
                var p = DERReader(element.content)
                if let bits = p.read(tag: DERReader.bitString), bits.first == 0 { point = Array(bits.dropFirst()) }
            }
        }
        guard let curve else { return nil }
        let q = point ?? publicPoint(scalar: scalar, curve: curve)
        guard let q, q.first == 0x04 else { return nil }
        let keyType = "ecdsa-sha2-" + curve.sshName
        let blob = SSHWriter.string(keyType) + SSHWriter.string(curve.sshName) + SSHWriter.string(q)
        return (.ecdsa(curve: curve.name), blob, keyType)
    }

    /// PKCS#8: SEQUENCE { version, SEQUENCE { algorithm OID, parameters }, OCTET STRING key }.
    private static func pkcs8(_ der: [UInt8]) -> (PrivateKeyInfo.Algorithm, [UInt8], String)? {
        var outer = DERReader(der)
        guard let seq = outer.read(tag: DERReader.sequence) else { return nil }
        var r = DERReader(seq)
        guard r.read(tag: DERReader.integer) != nil, let algorithmID = r.read(tag: DERReader.sequence),
              let key = r.read(tag: DERReader.octetString) else { return nil }
        var a = DERReader(algorithmID)
        guard let oid = a.read(tag: DERReader.objectID) else { return nil }
        if oid == rsaOID { return pkcs1(key) }
        if oid == ecOID {
            let param = a.read(tag: DERReader.objectID)
            return sec1(key, curve: curves.first { $0.oid == param })
        }
        if oid == ed25519OID {
            var k = DERReader(key)
            guard let seed = k.read(tag: DERReader.octetString), seed.count == 32,
                  let privateKey = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed) else { return nil }
            let blob = SSHWriter.string("ssh-ed25519") + SSHWriter.string(Array(privateKey.publicKey.rawRepresentation))
            return (.ed25519, blob, "ssh-ed25519")
        }
        return nil
    }

    // MARK: - Helpers

    private static func publicPoint(scalar: [UInt8], curve: Curve) -> [UInt8]? {
        guard scalar.count == curve.scalarSize else { return nil }
        let raw = Data(scalar)
        switch curve.name {
        case "P-256": return (try? P256.Signing.PrivateKey(rawRepresentation: raw)).map { Array($0.publicKey.x963Representation) }
        case "P-384": return (try? P384.Signing.PrivateKey(rawRepresentation: raw)).map { Array($0.publicKey.x963Representation) }
        case "P-521": return (try? P521.Signing.PrivateKey(rawRepresentation: raw)).map { Array($0.publicKey.x963Representation) }
        default: return nil
        }
    }

    /// The number of bits of a big-endian positive integer.
    private static func bitLength(_ bytes: [UInt8]) -> Int {
        let trimmed = bytes.drop { $0 == 0 }
        guard let first = trimmed.first else { return 0 }
        return (trimmed.count - 1) * 8 + (8 - first.leadingZeroBitCount)
    }
}
