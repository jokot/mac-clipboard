import Foundation

/// The result of "Find Secrets in History…", and the text of its alert.
struct SecretScan {
    /// The number of text clips and link clips that MaClip checked.
    let checked: Int
    /// The clips with a secret, in history order.
    let found: [(id: UUID, kind: SecretKind)]

    var isEmpty: Bool { found.isEmpty }

    var title: String {
        switch found.count {
        case 0: return "No secrets found"
        case 1: return "1 secret found"
        default: return "\(found.count) secrets found"
        }
    }

    var message: String {
        if found.isEmpty { return "MaClip checked \(checked) clip\(checked == 1 ? "" : "s")." }
        // The kinds in the order of the rules table.
        let groups = SecretKind.allCases.compactMap { kind -> (SecretKind, Int)? in
            let n = found.filter { $0.kind == kind }.count
            return n > 0 ? (kind, n) : nil
        }
        var parts = groups.prefix(3).map { $0.0.count($0.1) }
        let others = groups.dropFirst(3).reduce(0) { $0 + $1.1 }
        if others > 0 { parts.append("\(others) other secret\(others == 1 ? "" : "s")") }
        let list = parts.count == 1 ? parts[0] : parts.dropLast().joined(separator: ", ") + " and " + parts.last!
        let pronoun = found.count == 1 ? "it" : "them"
        return "\(list). Hide \(pronoun), or delete \(pronoun) now."
    }
}
