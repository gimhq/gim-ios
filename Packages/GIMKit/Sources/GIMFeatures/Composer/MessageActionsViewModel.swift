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

    /// The actions for `message`, in menu order. A read-only chat (leaving or left) only offers Copy and, for unsent
    /// own messages, Delete (which removes them from the outbox).
    public nonisolated static func actions(for message: MessageItem, isReadOnly: Bool = false) -> [MessageAction] {
        if case .deleted = message.content { return [] }
        guard !isReadOnly else {
            var actions: [MessageAction] = copyText(for: message) != nil ? [.copy] : []
            if isUnsent(message) { actions.append(.delete) }
            return actions
        }
        var actions: [MessageAction] = [.reply, .react]
        if copyText(for: message) != nil { actions.append(.copy) }
        if ComposerViewModel.canEdit(message) { actions.append(.edit) }
        if message.isOwn { actions.append(.delete) }
        if canRetry(message) { actions.append(.retry) }
        return actions
    }

    /// Whether a failed send can be resent: not when it failed because a hub suspended or does not admit the user.
    public nonisolated static func canRetry(_ message: MessageItem) -> Bool {
        guard case .failed(_, let cause) = message.sendState else { return false }
        return canRetry(cause)
    }

    /// Whether a send that failed with `cause` can be resent: only for `rejected` and `other`.
    public nonisolated static func canRetry(_ cause: SendFailure) -> Bool {
        ErrorPresenter.sendFailureMessage(cause) == nil
    }

    private nonisolated static func isUnsent(_ message: MessageItem) -> Bool {
        switch message.sendState {
        case .pending, .failed: message.isOwn
        default: false
        }
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
            await fail(error)
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
            if Self.isUnsent(message) {
                try await client.cancelSend(chatId: chatId, messageId: message.messageId)
            } else {
                try await client.deleteMessage(chatId: chatId, messageId: message.messageId)
            }
        } catch {
            await fail(error)
        }
    }

    public func dismissError() {
        errorMessage = nil
    }

    /// `ChatNotActive` shows no error: gim-core moved the chat out of `active`, so the chat list and timeline bring
    /// the new state and the conversation turns read-only.
    private func fail(_ error: any Error) async {
        if case .ChatNotActive = error as? GimError { return }
        errorMessage = await ErrorPresenter.message(for: error, client: client)
    }
}
