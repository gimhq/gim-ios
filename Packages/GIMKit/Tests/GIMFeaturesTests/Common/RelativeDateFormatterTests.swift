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

    func testWeekdayAndDateFollowChineseAndSpanishLocales() {
        let now = now
        let weekday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 10))!
        let older = calendar.date(from: DateComponents(year: 2025, month: 12, day: 24, hour: 12))!
        let english = RelativeDateFormatter(calendar: calendar, locale: Locale(identifier: "en_US"), now: { now })
        for identifier in ["zh_Hans", "es"] {
            let locale = Locale(identifier: identifier)
            let formatter = RelativeDateFormatter(calendar: calendar, locale: locale, now: { now })
            XCTAssertEqual(formatter.string(from: weekday), reference(locale: locale, template: "EEEE", date: weekday))
            XCTAssertEqual(formatter.string(from: older), reference(locale: locale, dateStyle: .short, date: older))
            XCTAssertNotEqual(formatter.string(from: weekday), english.string(from: weekday), identifier)
            XCTAssertNotEqual(formatter.string(from: older), english.string(from: older), identifier)
        }
    }

    private func reference(
        locale: Locale, template: String? = nil, dateStyle: DateFormatter.Style = .none, date: Date
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        if let template {
            formatter.setLocalizedDateFormatFromTemplate(template)
        } else {
            formatter.dateStyle = dateStyle
            formatter.timeStyle = .none
        }
        return formatter.string(from: date)
    }
}
