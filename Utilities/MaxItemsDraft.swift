import Foundation

/// The "Keep up to" field in Settings. The number takes effect only on Apply.
enum MaxItemsDraft {
    static let range = 1...1000

    struct Note: Equatable {
        let text: String
        /// Orange: Apply deletes clips, or the number is not allowed.
        let isWarning: Bool
    }

    static func canApply(draft: Int, saved: Int) -> Bool {
        draft != saved && range.contains(draft)
    }

    /// What Apply does with this number. Nil when the number did not change.
    static func note(draft: Int, saved: Int, count: Int) -> Note? {
        guard draft != saved else { return nil }
        guard range.contains(draft) else {
            return Note(text: "Enter a number from \(range.lowerBound) to \(range.upperBound).", isWarning: true)
        }
        let deletes = count - draft
        switch deletes {
        case ...0:
            return Note(text: "Press Apply or \u{21A9} to keep up to \(draft) clips.", isWarning: false)
        case 1:
            return Note(text: "Apply deletes the oldest clip. You cannot undo this.", isWarning: true)
        default:
            return Note(text: "Apply deletes the \(deletes) oldest clips. You cannot undo this.", isWarning: true)
        }
    }
}
