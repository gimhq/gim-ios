import GIMClientKit
import Observation

/// What the long-press menu of a message offers.
public enum MessageAction: Sendable, Hashable {
    case reply
    case react
    case copy
    case edit
    case delete
    case retry
}

/// The long-press actions on messages of one chat that act directly on the client: reactions, delete (after
/// confirmation) and retry. Reply and edit go to the composer.
@MainActor
@Observable
public final class MessageActionsViewModel {
    /// The reactions offered in the menu.
    public nonisolated static let quickReactions = ["👍", "❤️", "😂", "😮", "😢", "🙏"]

    public let chatId: String
    /// The message waiting for delete confirmation.
    public private(set) var pendingDelete: MessageItem?
    public private(set) var errorMessage: String?

    private let client: any GimClientAPI

    public init(client: any GimClientAPI, chatId: String) {
        self.client = client
        self.chatId = chatId
    }

    /// The actions for `message`, in menu order.
    public nonisolated static func actions(for message: MessageItem) -> [MessageAction] {
        if case .deleted = message.content { return [] }
        var actions: [MessageAction] = [.reply, .react]
        if copyText(for: message) != nil { actions.append(.copy) }
        if ComposerViewModel.canEdit(message) { actions.append(.edit) }
        if message.isOwn { actions.append(.delete) }
        if case .failed = message.sendState { actions.append(.retry) }
        return actions
    }

    /// Text placed on the pasteboard by Copy: the body or the caption.
    public nonisolated static func copyText(for message: MessageItem) -> String? {
        switch message.content {
        case .text(let body): return body
        case .image(_, _, _, let caption), .file(_, _, let caption): return caption.flatMap { $0.isEmpty ? nil : $0 }
        case .deleted, .unsupported: return nil
        }
    }

    /// Whether the signed-in user already reacted to `message` with `emoji`.
    public nonisolated static func hasOwnReaction(_ message: MessageItem, emoji: String) -> Bool {
        message.reactions.contains { $0.emoji == emoji && $0.own }
    }

    /// Adds the own reaction, or removes it when it is already there.
    public func toggleReaction(_ emoji: String, on message: MessageItem) async {
        do {
            if Self.hasOwnReaction(message, emoji: emoji) {
                try await client.unreact(chatId: chatId, messageId: message.messageId, emoji: emoji)
            } else {
                try await client.react(chatId: chatId, messageId: message.messageId, emoji: emoji)
            }
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// Asks for confirmation before deleting an own message.
    public func requestDelete(_ message: MessageItem) {
        guard message.isOwn else { return }
        pendingDelete = message
    }

    public func cancelDelete() {
        pendingDelete = nil
    }

    /// Deletes a confirmed message. Unsent messages are removed from the outbox instead.
    public func delete(_ message: MessageItem) async {
        pendingDelete = nil
        do {
            switch message.sendState {
            case .pending, .failed:
                try await client.cancelSend(chatId: chatId, messageId: message.messageId)
            default:
                try await client.deleteMessage(chatId: chatId, messageId: message.messageId)
            }
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    public func dismissError() {
        errorMessage = nil
    }
}
