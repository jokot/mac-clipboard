import Foundation

/// The short age at the right of a clip row: "now", "6m", "3h", "Yesterday", "Oct 21".
enum ClipAge {
    static func short(from date: Date, now: Date = Date(),
                      calendar: Calendar = .current, locale: Locale = .current) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 && (calendar.isDate(date, inSameDayAs: now) || seconds < 6 * 3600) {
            return "\(Int(seconds / 3600))h"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "MMMd" : "MMMdyyyy")
        return formatter.string(from: date)
    }
}

/// The text at the right of the clip window's hint bar.
enum ClipListSummary {
    /// `matches` is nil when the search field is empty.
    static func text(total: Int, limit: Int, matches: Int?) -> String {
        guard let matches else { return "\(total) of \(limit) clips" }
        switch matches {
        case 0: return "No matches"
        case 1: return "1 match"
        default: return "\(matches) matches"
        }
    }
}
