import Foundation
import GIMClientKit

/// One chat list row, ready for display.
public struct ChatRow: Sendable, Hashable, Identifiable {
    public let id: ChatId
    public let kind: ChatKind
    public let title: String
    public let avatarPath: String?
    /// Last message preview, prefixed with the sender's name in groups; `nil` for chats without messages.
    public let preview: String?
    /// Relative time of the last message.
    public let time: String?
    public let unreadCount: UInt32
    /// `nil` when nothing is unread, otherwise the count capped at "99+".
    public let unreadText: String?

    public init(summary: ChatSummary, dateFormatter: RelativeDateFormatter) {
        id = summary.id
        kind = summary.kind
        title = summary.title
        avatarPath = summary.avatarPath
        preview = Self.preview(for: summary)
        time = summary.lastMessageAt.map(dateFormatter.string(from:))
        unreadCount = summary.unreadCount
        unreadText = Self.unreadText(for: summary.unreadCount)
    }

    /// gim-core already renders the last message as text ("Photo", a file name, "Message deleted", …).
    public static func preview(for summary: ChatSummary) -> String? {
        guard let text = summary.lastMessagePreview else { return nil }
        guard summary.kind == .group, let sender = summary.lastMessageSenderName, !sender.isEmpty else { return text }
        return "\(sender): \(text)"
    }

    public static func unreadText(for count: UInt32) -> String? {
        switch count {
        case 0: nil
        case 1...99: "\(count)"
        default: "99+"
        }
    }
}
