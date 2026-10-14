import Foundation

/// Formats message and chat list dates: today -> time, within the previous 6 days -> weekday, otherwise short date.
public final class RelativeDateFormatter {
    private let calendar: Calendar
    private let now: () -> Date
    private let timeFormatter = DateFormatter()
    private let weekdayFormatter = DateFormatter()
    private let dateFormatter = DateFormatter()

    public init(
        calendar: Calendar = .autoupdatingCurrent, locale: Locale = .autoupdatingCurrent,
        now: @escaping () -> Date = { Date() }
    ) {
        self.calendar = calendar
        self.now = now
        for formatter in [timeFormatter, weekdayFormatter, dateFormatter] {
            formatter.calendar = calendar
            formatter.locale = locale
            formatter.timeZone = calendar.timeZone
        }
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        weekdayFormatter.setLocalizedDateFormatFromTemplate("EEEE")
        dateFormatter.dateStyle = .short
        dateFormatter.timeStyle = .none
    }

    public func string(from date: Date) -> String {
        let today = calendar.startOfDay(for: now())
        let day = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: day, to: today).day ?? 0
        switch days {
        case 0: return timeFormatter.string(from: date)
        case 1...6: return weekdayFormatter.string(from: date)
        default: return dateFormatter.string(from: date)
        }
    }
}
