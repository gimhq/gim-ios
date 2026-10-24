import Foundation
import GIMClientKit

/// One chat list row, ready for display.
public struct ChatRow: Sendable, Hashable, Identifiable {
    public let id: String
    public let kind: ChatKind
    public let title: String
    /// Group avatar; load it with `fetchThumbnail`.
    public let avatar: MediaRef?
    /// Last message preview, prefixed with the sender's name in groups; `nil` for chats without messages.
    public let preview: String?
    /// Relative time of the last message.
    public let time: String?
    public let unreadCount: UInt32
    /// `nil` when nothing is unread, otherwise the count capped at "99+".
    public let unreadText: String?
    /// Where this device stands in the chat.
    public let state: ChatState
    /// True when the last message is the user's own; the row then shows its status ticks.
    public let lastMessageIsOwn: Bool
    /// When the last message was sent; `nil` for chats without messages.
    public let lastMessageSentAtMs: UInt64?
    /// Status ticks of the own last message, from the preview's send state; `nil` when the last message is someone
    /// else's or has no send state.
    public let lastMessageStatus: MessageStatus?
    /// Pinned chats come first in the list.
    public let isPinned: Bool
    /// True while notifications are muted at `now` (`ChatSummary.mutedUntilMs`).
    public let isMuted: Bool
    /// Archived chats are listed apart from the others.
    public let isArchived: Bool

    /// - Parameter now: the time `isMuted` is checked against.
    public init(summary: ChatSummary, dateFormatter: RelativeDateFormatter, now: Date = Date()) {
        id = summary.chatId
        kind = summary.kind
        title = UserLabel.name(summary.name)
        avatar = summary.avatar
        preview = Self.preview(for: summary)
        time = summary.lastMessage.map { dateFormatter.string(from: Date(epochMilliseconds: $0.sentAtMs)) }
        unreadCount = summary.unreadCount
        unreadText = Self.unreadText(for: summary.unreadCount)
        state = summary.state
        lastMessageIsOwn = summary.lastMessage?.isOwn ?? false
        lastMessageSentAtMs = summary.lastMessage?.sentAtMs
        lastMessageStatus = summary.lastMessage.flatMap { $0.isOwn ? $0.sendState.map(MessageStatus.init) : nil }
        isPinned = summary.pinned
        isMuted = summary.mutedUntilMs == mutedForever() || summary.mutedUntilMs > now.epochMilliseconds
        isArchived = summary.archived
    }

    /// gim-core already renders the last message as text ("Photo", "File: report.pdf", "Message deleted", …).
    public static func preview(for summary: ChatSummary) -> String? {
        guard let message = summary.lastMessage else { return nil }
        guard summary.kind == .group, !message.senderName.isEmpty else { return message.text }
        return "\(UserLabel.name(message.senderName)): \(message.text)"
    }

    public static func unreadText(for count: UInt32) -> String? {
        switch count {
        case 0: nil
        case 1...99: "\(count)"
        default: "99+"
        }
    }
}
