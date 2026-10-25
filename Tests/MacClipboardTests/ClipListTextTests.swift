import XCTest
@testable import MaClip

final class ClipListTextTests: XCTestCase {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private let locale = Locale(identifier: "en_US")

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
    }

    private func age(_ then: Date, _ now: Date) -> String {
        ClipAge.short(from: then, now: now, calendar: calendar, locale: locale)
    }

    func test_ageUnderOneMinuteIsNow() {
        let now = date(2026, 10, 25, 10, 0, 50)
        XCTAssertEqual(age(date(2026, 10, 25, 10, 0, 0), now), "now")
        XCTAssertEqual(age(now.addingTimeInterval(5), now), "now", "a clock skew into the future is still now")
    }

    func test_ageInMinutesAndHours() {
        let now = date(2026, 10, 25, 10, 0)
        XCTAssertEqual(age(date(2026, 10, 25, 9, 54), now), "6m")
        XCTAssertEqual(age(date(2026, 10, 25, 9, 1), now), "59m")
        XCTAssertEqual(age(date(2026, 10, 25, 9, 0), now), "1h")
        XCTAssertEqual(age(date(2026, 10, 25, 0, 30), now), "9h")
    }

    func test_ageYesterdayAndOlder() {
        let now = date(2026, 10, 25, 10, 0)
        XCTAssertEqual(age(date(2026, 10, 24, 8, 0), now), "Yesterday")
        XCTAssertEqual(age(date(2026, 10, 21, 8, 0), now), "Oct 21")
        XCTAssertEqual(age(date(2025, 12, 30, 8, 0), now), "Dec 30, 2025")
    }

    func test_ageJustAfterMidnightUsesHoursNotYesterday() {
        let now = date(2026, 10, 25, 0, 30)
        XCTAssertEqual(age(date(2026, 10, 24, 23, 0), now), "1h")
    }

    func test_summaryWithoutSearchShowsCountAndLimit() {
        XCTAssertEqual(ClipListSummary.text(total: 24, limit: 50, matches: nil), "24 of 50 clips")
        XCTAssertEqual(ClipListSummary.text(total: 0, limit: 50, matches: nil), "0 of 50 clips")
    }

    func test_summaryWhileSearching() {
        XCTAssertEqual(ClipListSummary.text(total: 24, limit: 50, matches: 3), "3 matches")
        XCTAssertEqual(ClipListSummary.text(total: 24, limit: 50, matches: 1), "1 match")
        XCTAssertEqual(ClipListSummary.text(total: 24, limit: 50, matches: 0), "No matches")
    }
}
