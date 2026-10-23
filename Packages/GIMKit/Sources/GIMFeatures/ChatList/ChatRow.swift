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

    public init(summary: ChatSummary, dateFormatter: RelativeDateFormatter) {
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
