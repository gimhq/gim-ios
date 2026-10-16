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
    ///   - unavailableMedia: ids of the messages whose attachment couldn't be downloaded for now.
    ///   - ownUserId: the signed-in user, named "you" in membership changes.
    ///   - names: display names by user id (see `UserLabel`) for the users membership changes refer to.
    public func build(
        _ items: [TimelineItem], isGroup: Bool, typingText: String?, unavailableMedia: Set<String> = [],
        ownUserId: String? = nil, names: [String: String] = [:]
    ) -> [TimelineDisplayItem] {
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
                    hasTail: !Self.continuesRun(.message(item: message), next),
                    isMediaUnavailable: unavailableMedia.contains(message.messageId))
                append(TimelineDisplayItem.id(forMessage: message.messageId), .message(row))
            case .dateSeparator(let dayStartMs):
                append("day:\(dayStartMs)", .dateSeparator(dayLabel(dayStartMs)))
            case .membershipChange(let userName, let change, let atMs, let userId, let actorUserId):
                let text = Self.membershipText(
                    userName: userName, change: change, userId: userId, actorUserId: actorUserId,
                    ownUserId: ownUserId, names: names)
                append("member:\(atMs):\(userId):\(change)", .membership(text))
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

    /// "Alice added Bob", "Alice removed Bob", "Bob left"; the signed-in user is "you" ("You added Bob", "You were
    /// removed by Alice", "You left"). Without a known actor other than the user the change is passive ("Bob was
    /// removed"). Users are named from `names`, else the change's `userName` for its user, else a short user id.
    static func membershipText(
        userName: String, change: MembershipChangeKind, userId: String, actorUserId: String?, ownUserId: String?,
        names: [String: String]
    ) -> String {
        func name(_ id: String) -> String {
            names[id] ?? (id == userId ? UserLabel.name(userName) : UserLabel.shortUserId(id))
        }
        let isOwn = userId == ownUserId
        let user = isOwn ? "you" : name(userId)
        let actor = actorUserId.flatMap { $0 == userId ? nil : $0 }
        switch change {
        case .left:
            return isOwn ? "You left" : "\(user) left"
        case .added:
            guard let actor else { return isOwn ? "You were added" : "\(user) was added" }
            return actor == ownUserId ? "You added \(user)" : "\(name(actor)) added \(user)"
        case .removed:
            guard let actor else { return isOwn ? "You were removed" : "\(user) was removed" }
            if isOwn { return "You were removed by \(name(actor))" }
            return actor == ownUserId ? "You removed \(user)" : "\(name(actor)) removed \(user)"
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
        _ message: MessageItem, isGroup: Bool, isFirstInRun: Bool, hasTail: Bool, isMediaUnavailable: Bool
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
            senderName: isGroup && !message.isOwn && isFirstInRun ? UserLabel.name(for: message.sender) : nil,
            isFirstInRun: isFirstInRun, hasTail: hasTail,
            reply: isDeleted ? nil : message.replyTo.map(Self.labelled),
            reactions: isDeleted ? [] : message.reactions,
            isEdited: !isDeleted && message.edited,
            timeText: timeFormatter.string(from: Date(epochMilliseconds: message.sentAtMs)),
            status: message.isOwn && !isDeleted ? message.sendState.map(MessageStatus.init) : nil,
            isMediaUnavailable: isMediaUnavailable)
    }

    private static func labelled(_ reply: ReplyPreview) -> ReplyPreview {
        var reply = reply
        reply.senderName = UserLabel.name(reply.senderName)
        return reply
    }
}
