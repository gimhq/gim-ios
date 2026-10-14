import Foundation
import GIMFeatures
import XCTest

final class RelativeDateFormatterTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Athens")!
        return calendar
    }

    /// Wednesday 2026-10-14 15:30 in Athens.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 15, minute: 30))!
    }

    private func format(_ components: DateComponents) -> String {
        let now = now
        let formatter = RelativeDateFormatter(
            calendar: calendar, locale: Locale(identifier: "en_US"), now: { now })
        // ICU may separate the time and AM/PM with a narrow no-break space.
        return formatter.string(from: calendar.date(from: components)!)
            .replacingOccurrences(of: "\u{202F}", with: " ")
    }

    func testTodayShowsTime() {
        XCTAssertEqual(format(DateComponents(year: 2026, month: 10, day: 14, hour: 9, minute: 5)), "9:05 AM")
        XCTAssertEqual(format(DateComponents(year: 2026, month: 10, day: 14, hour: 0, minute: 0)), "12:00 AM")
    }

    func testWithinSixDaysShowsWeekday() {
        XCTAssertEqual(format(DateComponents(year: 2026, month: 10, day: 13, hour: 23, minute: 59)), "Tuesday")
        XCTAssertEqual(format(DateComponents(year: 2026, month: 10, day: 8, hour: 0, minute: 1)), "Thursday")
    }

    func testOlderOrFutureShowsShortDate() {
        XCTAssertEqual(format(DateComponents(year: 2026, month: 10, day: 7, hour: 12)), "10/7/26")
        XCTAssertEqual(format(DateComponents(year: 2025, month: 12, day: 24, hour: 12)), "12/24/25")
        XCTAssertEqual(format(DateComponents(year: 2026, month: 10, day: 15, hour: 8)), "10/15/26")
    }

    func testUsesInjectedLocale() {
        let now = now
        let formatter = RelativeDateFormatter(calendar: calendar, locale: Locale(identifier: "de_DE"), now: { now })
        let date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 10))!
        XCTAssertEqual(formatter.string(from: date), "Montag")
    }
}
