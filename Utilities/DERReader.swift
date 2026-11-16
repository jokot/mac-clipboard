import Foundation

/// Reads DER (ASN.1) elements. Each read checks the length against the bytes that are left,
/// so bad input returns nil and never reads past the end.
struct DERReader {
    struct Element {
        let tag: UInt8
        let content: [UInt8]
    }

    private let bytes: [UInt8]
    private(set) var position = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    var isAtEnd: Bool { position >= bytes.count }

    mutating func read() -> Element? {
        guard position < bytes.count else { return nil }
        let tag = bytes[position]
        var p = position + 1
        guard p < bytes.count else { return nil }
        let first = Int(bytes[p])
        p += 1
        var length: Int
        if first < 0x80 {
            length = first
        } else {
            let count = first & 0x7F
            guard (1...4).contains(count), p + count <= bytes.count else { return nil }
            length = 0
            for i in 0..<count { length = length << 8 | Int(bytes[p + i]) }
            p += count
        }
        guard length >= 0, length <= bytes.count - p else { return nil }
        position = p + length
        return Element(tag: tag, content: Array(bytes[p..<(p + length)]))
    }

    /// Reads one element and checks its tag.
    mutating func read(tag: UInt8) -> [UInt8]? {
        guard let element = read(), element.tag == tag else { return nil }
        return element.content
    }

    static let sequence: UInt8 = 0x30
    static let integer: UInt8 = 0x02
    static let octetString: UInt8 = 0x04
    static let bitString: UInt8 = 0x03
    static let objectID: UInt8 = 0x06
}

/// Reads the SSH wire format: a 4-byte length, then the bytes. Each read checks the length.
struct SSHReader {
    private let bytes: [UInt8]
    private var position = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    mutating func readUInt32() -> Int? {
        guard bytes.count - position >= 4 else { return nil }
        let v = bytes[position..<(position + 4)].reduce(0) { $0 << 8 | Int($1) }
        position += 4
        return v
    }

    mutating func readString() -> [UInt8]? {
        guard let length = readUInt32(), length <= bytes.count - position else { return nil }
        defer { position += length }
        return Array(bytes[position..<(position + length)])
    }

    mutating func readBytes(_ count: Int) -> [UInt8]? {
        guard count >= 0, count <= bytes.count - position else { return nil }
        defer { position += count }
        return Array(bytes[position..<(position + count)])
    }
}

/// Writes the SSH wire format.
enum SSHWriter {
    static func string(_ bytes: [UInt8]) -> [UInt8] {
        let n = bytes.count
        return [UInt8(n >> 24 & 0xFF), UInt8(n >> 16 & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n & 0xFF)] + bytes
    }

    static func string(_ text: String) -> [UInt8] { string(Array(text.utf8)) }

    /// A positive big-endian integer (RFC 4251, section 5): no leading zeros, and a zero byte
    /// first when the high bit is set.
    static func mpint(_ magnitude: [UInt8]) -> [UInt8] {
        var m = Array(magnitude.drop { $0 == 0 })
        if let first = m.first, first & 0x80 != 0 { m.insert(0, at: 0) }
        return string(m)
    }
}
