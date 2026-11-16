import Foundation

/// Decides how MaClip saves a new clip: as a normal clip, as a concealed clip, or not at all.
/// A pure function, so tests cover every rule without a pasteboard.
enum SecretCapture {
    enum Decision: Equatable {
        case skip
        case save(isConcealed: Bool, expiresAt: Date?, secretKind: SecretKind?)
    }

    /// - Parameters:
    ///   - text: the raw text of a text clip or a link clip, before MaClip makes a URL from it.
    ///     Nil for an image clip or a file clip.
    ///   - hasConcealedMark: the pasteboard has a concealed type, for example from a password manager.
    ///   - findSecrets: the switch "Find secrets in copied text".
    ///   - skipConcealed: the switch "Don't save concealed clips".
    ///   - timeout: "Delete concealed clips after", in seconds. -1 means never.
    static func decide(text: String?, hasConcealedMark: Bool, findSecrets: Bool,
                       skipConcealed: Bool, timeout: TimeInterval, now: Date) -> Decision {
        let kind = findSecrets ? text.flatMap(SecretDetector.kind(in:)) : nil
        guard hasConcealedMark || kind != nil else {
            return .save(isConcealed: false, expiresAt: nil, secretKind: nil)
        }
        if skipConcealed { return .skip }
        return .save(isConcealed: true, expiresAt: expiry(timeout: timeout, now: now), secretKind: kind)
    }

    /// The countdown end of a new concealed clip.
    static func expiry(timeout: TimeInterval, now: Date) -> Date {
        timeout == -1 ? .distantFuture : now.addingTimeInterval(timeout)
    }
}
