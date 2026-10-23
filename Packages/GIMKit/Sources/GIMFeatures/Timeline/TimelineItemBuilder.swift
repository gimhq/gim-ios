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
        dayLabelKind(dayStartMs).text
    }

    /// What the day separator says: today, yesterday, or the formatted date.
    public func dayLabelKind(_ dayStartMs: UInt64) -> TimelineDayLabelKind {
        let date = Date(epochMilliseconds: dayStartMs)
        let today = now()
        if calendar.isDate(date, inSameDayAs: today) { return .today }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
            calendar.isDate(date, inSameDayAs: yesterday)
        {
            return .yesterday
        }
        if calendar.component(.year, from: date) == calendar.component(.year, from: today) {
            return .date(dayFormatter.string(from: date))
        }
        return .date(yearDayFormatter.string(from: date))
    }

    /// "Alice is typing…", "Alice and Bob are typing…", "3 people are typing…"; `nil` when nobody types.
    public static func typingText(names: [String]) -> String? {
        typingKind(names: names)?.text
    }

    /// What the typing row says for `names`; `nil` when nobody types.
    public static func typingKind(names: [String]) -> TimelineTypingKind? {
        switch names.count {
        case 0: nil
        case 1: .one(names[0])
        case 2: .two(names[0], names[1])
        default: .many(count: names.count)
        }
    }

    /// "Alice added Bob", "Alice removed Bob", "Bob left"; the signed-in user is "you" ("You added Bob", "You were
    /// removed by Alice", "You left"). Without a known actor other than the user the change is passive ("Bob was
    /// removed"). Users are named from `names`, else the change's `userName` for its user, else a short user id.
    static func membershipText(
        userName: String, change: MembershipChangeKind, userId: String, actorUserId: String?, ownUserId: String?,
        names: [String: String]
    ) -> String {
        membershipKind(
            userName: userName, change: change, userId: userId, actorUserId: actorUserId, ownUserId: ownUserId,
            names: names
        ).text
    }

    /// What a membership change row says, with the users named as in `membershipText`.
    public static func membershipKind(
        userName: String, change: MembershipChangeKind, userId: String, actorUserId: String?, ownUserId: String?,
        names: [String: String]
    ) -> TimelineMembershipKind {
        func name(_ id: String) -> String {
            names[id] ?? (id == userId ? UserLabel.name(userName) : UserLabel.shortUserId(id))
        }
        let isOwn = userId == ownUserId
        let user = name(userId)
        let actor = actorUserId.flatMap { $0 == userId ? nil : $0 }
        switch change {
        case .left:
            return isOwn ? .youLeft : .left(user: user)
        case .added:
            guard let actor else { return isOwn ? .youWereAdded : .wasAdded(user: user) }
            if isOwn { return .addedYou(actor: name(actor)) }
            return actor == ownUserId ? .youAdded(user: user) : .added(actor: name(actor), user: user)
        case .removed:
            guard let actor else { return isOwn ? .youWereRemoved : .wasRemoved(user: user) }
            if isOwn { return .youWereRemovedBy(actor: name(actor)) }
            return actor == ownUserId ? .youRemoved(user: user) : .removed(actor: name(actor), user: user)
        }
    }

    /// The placeholder shown instead of deleted or unsupported content; `nil` for content that is shown.
    public static func placeholderKind(for content: MessageContent) -> MessagePlaceholderKind? {
        switch content {
        case .deleted: .deleted
        case .unsupported: .unsupported
        case .text, .image, .file: nil
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
                media: media, fileName: fileName ?? MessagePreviewKind.file.text,
                sizeText: byteFormatter.string(fromByteCount: Int64(media.size)),
                caption: caption)
        case .deleted:
            body = .placeholder(MessagePlaceholderKind.deleted.text)
        case .unsupported:
            body = .placeholder(MessagePlaceholderKind.unsupported.text)
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

/// `key` from the FeaturesChat table; the key is the English text.
private func chatText(_ key: String) -> String {
    NSLocalizedString(key, tableName: "FeaturesChat", bundle: FeaturesLocalization.bundle, value: key, comment: "")
}

/// What a day separator says.
public enum TimelineDayLabelKind: Sendable, Hashable {
    case today
    case yesterday
    /// Any other day, formatted for the builder's locale.
    case date(String)

    /// The English text, localized through the FeaturesChat table.
    public var text: String {
        switch self {
        case .today: chatText("Today")
        case .yesterday: chatText("Yesterday")
        case .date(let date): date
        }
    }
}

/// What the typing row at the bottom of the timeline says.
public enum TimelineTypingKind: Sendable, Hashable {
    case one(String)
    case two(String, String)
    /// Three or more people.
    case many(count: Int)

    /// The English text, localized through the FeaturesChat table.
    public var text: String {
        switch self {
        case .one(let name):
            String(format: chatText("%@ is typing…"), name)
        case .two(let first, let second):
            String(format: chatText("%@ and %@ are typing…"), first, second)
        case .many(let count):
            String(format: chatText("%lld people are typing…"), Int64(count))
        }
    }
}

/// What a membership change row says; `user` is the member who changed, `actor` who changed them.
public enum TimelineMembershipKind: Sendable, Hashable {
    case youLeft
    case left(user: String)
    case youWereAdded
    case wasAdded(user: String)
    case youAdded(user: String)
    case addedYou(actor: String)
    case added(actor: String, user: String)
    case youWereRemoved
    case wasRemoved(user: String)
    case youWereRemovedBy(actor: String)
    case youRemoved(user: String)
    case removed(actor: String, user: String)

    /// The English text, localized through the FeaturesChat table.
    public var text: String {
        switch self {
        case .youLeft: chatText("You left")
        case .left(let user): String(format: chatText("%@ left"), user)
        case .youWereAdded: chatText("You were added")
        case .wasAdded(let user): String(format: chatText("%@ was added"), user)
        case .youAdded(let user): String(format: chatText("You added %@"), user)
        case .addedYou(let actor): String(format: chatText("%@ added you"), actor)
        case .added(let actor, let user): String(format: chatText("%@ added %@"), actor, user)
        case .youWereRemoved: chatText("You were removed")
        case .wasRemoved(let user): String(format: chatText("%@ was removed"), user)
        case .youWereRemovedBy(let actor): String(format: chatText("You were removed by %@"), actor)
        case .youRemoved(let user): String(format: chatText("You removed %@"), user)
        case .removed(let actor, let user): String(format: chatText("%@ removed %@"), actor, user)
        }
    }
}

/// What a message bubble shows instead of content that can't be shown.
public enum MessagePlaceholderKind: Sendable, Hashable {
    case deleted
    /// Content this version can't show.
    case unsupported

    /// The English text, localized through the FeaturesChat table.
    public var text: String {
        switch self {
        case .deleted: chatText("This message was deleted")
        case .unsupported: chatText("This message can't be shown in this version")
        }
    }
}
