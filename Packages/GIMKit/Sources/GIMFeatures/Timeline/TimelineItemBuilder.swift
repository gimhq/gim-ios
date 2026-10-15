import Foundation
import GIMClientKit

/// Turns gim-core timeline items into display items.
///
/// gim-core already inserts the day separators; this formats them and adds what is presentation-only: runs of
/// messages from the same sender within `runGapMs` (any other item ends a run), the sender name on the first message
/// of a run in groups, placeholders, delivery status and the typing row at the bottom. Use
/// `TimelineChangeSet(from:to:)` on two results to drive batch updates.
public final class TimelineItemBuilder {
    /// Longest gap between two messages of the same run.
    public static let runGapMs: UInt64 = 5 * 60_000

    private let calendar: Calendar
    private let now: () -> Date
    private let timeFormatter = DateFormatter()
    private let dayFormatter = DateFormatter()
    private let yearDayFormatter = DateFormatter()
    private let byteFormatter = ByteCountFormatter()

    /// - Parameter calendar: decides "Today" and "Yesterday" and the time zone of the labels.
    public init(
        calendar: Calendar = .autoupdatingCurrent, locale: Locale = .autoupdatingCurrent,
        now: @escaping () -> Date = { Date() }
    ) {
        self.calendar = calendar
        self.now = now
        for formatter in [timeFormatter, dayFormatter, yearDayFormatter] {
            formatter.calendar = calendar
            formatter.locale = locale
            formatter.timeZone = calendar.timeZone
        }
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        dayFormatter.setLocalizedDateFormatFromTemplate("EEEEMMMMd")
        yearDayFormatter.setLocalizedDateFormatFromTemplate("yMMMMd")
        byteFormatter.countStyle = .file
    }

    /// - Parameters:
    ///   - items: the gim-core timeline, oldest first.
    ///   - typingText: adds the typing row at the bottom when set.
    public func build(_ items: [TimelineItem], isGroup: Bool, typingText: String?) -> [TimelineDisplayItem] {
        var result: [TimelineDisplayItem] = []
        result.reserveCapacity(items.count + 1)
        var usedIds: Set<String> = []
        func append(_ id: String, _ kind: TimelineDisplayItem.Kind) {
            // Ids must be unique for diffable updates; a repeated one (never expected from gim-core) gets a suffix.
            var uniqueId = id
            var suffix = 1
            while !usedIds.insert(uniqueId).inserted {
                suffix += 1
                uniqueId = "\(id)#\(suffix)"
            }
            result.append(TimelineDisplayItem(id: uniqueId, kind: kind))
        }

        for (index, item) in items.enumerated() {
            switch item {
            case .message(let message):
                let previous = index > 0 ? items[index - 1] : nil
                let next = index + 1 < items.count ? items[index + 1] : nil
                let row = messageRow(
                    message, isGroup: isGroup,
                    isFirstInRun: !Self.continuesRun(previous, message),
                    hasTail: !Self.continuesRun(.message(item: message), next))
                append(TimelineDisplayItem.id(forMessage: message.messageId), .message(row))
            case .dateSeparator(let dayStartMs):
                append("day:\(dayStartMs)", .dateSeparator(dayLabel(dayStartMs)))
            case .membershipChange(let userName, let change, let atMs):
                append("member:\(atMs):\(userName):\(change)", .membership(Self.membershipText(userName, change)))
            }
        }
        if let typingText {
            append(TimelineDisplayItem.typingId, .typing(typingText))
        }
        return result
    }

    /// "Today", "Yesterday", the weekday and date this year, otherwise the full date.
    public func dayLabel(_ dayStartMs: UInt64) -> String {
        let date = Date(epochMilliseconds: dayStartMs)
        let today = now()
        if calendar.isDate(date, inSameDayAs: today) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
            calendar.isDate(date, inSameDayAs: yesterday)
        {
            return "Yesterday"
        }
        if calendar.component(.year, from: date) == calendar.component(.year, from: today) {
            return dayFormatter.string(from: date)
        }
        return yearDayFormatter.string(from: date)
    }

    /// "Alice is typing…", "Alice and Bob are typing…", "3 people are typing…"; `nil` when nobody types.
    public static func typingText(names: [String]) -> String? {
        switch names.count {
        case 0: nil
        case 1: "\(names[0]) is typing…"
        case 2: "\(names[0]) and \(names[1]) are typing…"
        default: "\(names.count) people are typing…"
        }
    }

    static func membershipText(_ userName: String, _ change: MembershipChangeKind) -> String {
        switch change {
        case .added: "\(userName) was added"
        case .removed: "\(userName) was removed"
        case .left: "\(userName) left"
        }
    }

    /// Whether `message` continues the run of `previous`.
    private static func continuesRun(_ previous: TimelineItem?, _ message: MessageItem) -> Bool {
        guard case .message(let earlier) = previous else { return false }
        let gap =
            message.sentAtMs >= earlier.sentAtMs
            ? message.sentAtMs - earlier.sentAtMs : earlier.sentAtMs - message.sentAtMs
        return earlier.sender.userId == message.sender.userId && gap <= runGapMs
    }

    private static func continuesRun(_ previous: TimelineItem, _ next: TimelineItem?) -> Bool {
        guard case .message(let message) = next else { return false }
        return continuesRun(previous, message)
    }

    private func messageRow(
        _ message: MessageItem, isGroup: Bool, isFirstInRun: Bool, hasTail: Bool
    ) -> TimelineMessageRow {
        let isDeleted = message.content == .deleted
        let body: MessageBody
        switch message.content {
        case .text(let text):
            body = .text(text)
        case .image(let media, let width, let height, let caption):
            body = .image(media: media, width: width, height: height, caption: caption)
        case .file(let media, let fileName, let caption):
            body = .file(
                media: media, fileName: fileName ?? "File",
                sizeText: byteFormatter.string(fromByteCount: Int64(media.size)),
                caption: caption)
        case .deleted:
            body = .placeholder("This message was deleted")
        case .unsupported:
            body = .placeholder("This message can't be shown in this version")
        }
        return TimelineMessageRow(
            message: message, body: body,
            senderName: isGroup && !message.isOwn && isFirstInRun ? message.sender.displayName : nil,
            isFirstInRun: isFirstInRun, hasTail: hasTail,
            reply: isDeleted ? nil : message.replyTo,
            reactions: isDeleted ? [] : message.reactions,
            isEdited: !isDeleted && message.edited,
            timeText: timeFormatter.string(from: Date(epochMilliseconds: message.sentAtMs)),
            status: message.isOwn && !isDeleted ? message.sendState.map(MessageStatus.init) : nil)
    }
}
