import Foundation

/// The header and the payload of a JWT. It never holds the signature.
struct DecodedJWT: Equatable {
    let headerJSON: String
    let payloadJSON: String
    let algorithm: String?
    let type: String?
    let issuer: String?
    let subject: String?
    let audience: [String]
    let issuedAt: Date?
    let expiresAt: Date?
    let notBefore: Date?

    /// `alg: none`: anyone can make this token.
    var isUnsigned: Bool { algorithm?.lowercased() == "none" }

    func status(now: Date) -> JWTStatus {
        if let notBefore, notBefore > now { return .notYetValid(notBefore) }
        guard let expiresAt else { return .noExpiry }
        return expiresAt <= now ? .expired(expiresAt) : .valid(until: expiresAt)
    }
}

/// The expiry state of a JWT.
enum JWTStatus: Equatable {
    case expired(Date)
    case notYetValid(Date)
    case valid(until: Date)
    case noExpiry

    /// "Expired 3 days ago", "Not valid until Nov 16, 2026 at 09:00", "Expires in 2 hours", "No expiry date".
    func text(now: Date, locale: Locale = .current) -> String {
        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .full
        relative.locale = locale
        switch self {
        case .expired(let date): return "Expired " + relative.localizedString(for: date, relativeTo: now)
        case .valid(let date): return "Expires " + relative.localizedString(for: date, relativeTo: now)
        case .notYetValid(let date): return "Not valid until " + JWTDecoder.dateText(date, locale: locale)
        case .noExpiry: return "No expiry date"
        }
    }

    var isWarning: Bool {
        switch self {
        case .expired, .notYetValid: return true
        case .valid, .noExpiry: return false
        }
    }
}

/// Decodes a JWT on the Mac, as jwt.io does. It does not check the signature.
enum JWTDecoder {
    private static let pattern = try! NSRegularExpression(pattern:
        #"eyJ[A-Za-z0-9_\-]+=*\.eyJ[A-Za-z0-9_\-]+=*\.[A-Za-z0-9_\-]*=*"#)

    /// The first JWT in the text. Nil when its header or payload is not base64url JSON.
    static func decode(_ text: String) -> DecodedJWT? {
        let ns = text as NSString
        guard let match = pattern.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let parts = ns.substring(with: match.range).split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let header = object(fromBase64URL: String(parts[0])),
              let payload = object(fromBase64URL: String(parts[1])),
              let headerJSON = prettyJSON(header), let payloadJSON = prettyJSON(payload) else { return nil }
        let audience: [String]
        switch payload["aud"] {
        case let one as String: audience = [one]
        case let many as [Any]: audience = many.compactMap { $0 as? String }
        default: audience = []
        }
        return DecodedJWT(headerJSON: headerJSON, payloadJSON: payloadJSON,
                          algorithm: header["alg"] as? String, type: header["typ"] as? String,
                          issuer: payload["iss"] as? String, subject: payload["sub"] as? String,
                          audience: audience,
                          issuedAt: date(payload["iat"]), expiresAt: date(payload["exp"]), notBefore: date(payload["nbf"]))
    }

    /// "Nov 15, 2026 at 10:42" in the user's language.
    static func dateText(_ date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func object(fromBase64URL part: String) -> [String: Any]? {
        var base64 = part.trimmingCharacters(in: CharacterSet(charactersIn: "="))
            .replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func prettyJSON(_ object: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object,
                                                     options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private static func date(_ value: Any?) -> Date? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return Date(timeIntervalSince1970: number.doubleValue)
    }
}
