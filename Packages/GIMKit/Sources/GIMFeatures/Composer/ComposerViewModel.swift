import Foundation
import GIMClientKit
import Observation

/// Unsent text per chat, kept in memory for the lifetime of the signed-in session.
@MainActor
public final class ComposerDrafts {
    private var texts: [String: String] = [:]

    public init() {}

    public subscript(chatId: String) -> String {
        get { texts[chatId] ?? "" }
        set { texts[chatId] = newValue.isEmpty ? nil : newValue }
    }
}

/// The message composer of one chat: text, reply and edit targets, sending and the typing indicator.
@MainActor
@Observable
public final class ComposerViewModel {
    /// Minimum time between two `setTyping(active: true)` calls while the user keeps typing.
    public nonisolated static let typingInterval: TimeInterval = 4

    public let chatId: String
    public private(set) var text: String
    /// The message the next send replies to.
    public private(set) var replyTarget: MessageItem?
    /// The own text message being edited; sending replaces its body.
    public private(set) var editTarget: MessageItem?
    public private(set) var isSending = false
    public private(set) var errorMessage: String?

    private let client: any GimClientAPI
    private let drafts: ComposerDrafts
    private let timeline: TimelineViewModel?
    private let now: () -> Date
    /// When `setTyping(active: true)` was last sent; `nil` while the indicator is off.
    @ObservationIgnored private var typingSentAt: Date?
    /// Serialises typing calls so they reach the client in order.
    @ObservationIgnored private var typingTask: Task<Void, Never>?
    /// The draft to restore when an edit is cancelled.
    @ObservationIgnored private var draftBeforeEdit = ""

    /// - Parameters:
    ///   - timeline: the chat's timeline, which knows the chat's state; the composer is disabled unless the chat is
    ///     active.
    ///   - now: clock for the typing throttle.
    public init(
        client: any GimClientAPI, chatId: String, drafts: ComposerDrafts = ComposerDrafts(),
        timeline: TimelineViewModel? = nil, now: @escaping () -> Date = Date.init
    ) {
        self.client = client
        self.chatId = chatId
        self.drafts = drafts
        self.timeline = timeline
        self.now = now
        text = drafts[chatId]
    }

    /// The chat is leaving or left: gim-core refuses every send (`ChatNotActive`), so the composer shows
    /// `readOnlyText` instead of the input. Also right after a restart, as the state comes from local state.
    public var isReadOnly: Bool {
        readOnlyText != nil
    }

    /// The chat's state from the timeline; `nil` until known.
    public var chatState: ChatState? {
        timeline?.chatState
    }

    /// The banner shown instead of the input; `nil` while the chat is active (or its state is not known yet).
    public var readOnlyText: String? {
        readOnlyKind?.text
    }

    /// What the banner shown instead of the input says; `nil` while the chat is active (or its state is not known
    /// yet).
    public var readOnlyKind: ComposerReadOnlyKind? {
        switch chatState {
        case .leaving: .leaving
        case .left: .left
        case .active, nil: nil
        }
    }

    /// Whether the send button is enabled.
    public var canSend: Bool {
        !isSending && !isReadOnly && !trimmedText.isEmpty
    }

    /// Whether attachments can be sent; not while editing.
    public var canAttach: Bool {
        !isSending && !isReadOnly && editTarget == nil
    }

    // MARK: - Input

    public func textChanged(_ newText: String) {
        guard newText != text else { return }
        text = newText
        if editTarget == nil {
            drafts[chatId] = newText
            updateTyping()
        }
    }

    /// Replies to `message` with the next send. Ends an edit.
    public func setReplyTarget(_ message: MessageItem?) {
        guard message != replyTarget else { return }
        if message != nil, editTarget != nil { cancelEdit() }
        replyTarget = message
    }

    /// Prefills the composer with an own text message; sending replaces its body. Ignored for other messages.
    public func beginEdit(_ message: MessageItem) {
        guard Self.canEdit(message), case .text(let body) = message.content else { return }
        if editTarget == nil { draftBeforeEdit = text }
        stopTyping()
        replyTarget = nil
        editTarget = message
        text = body
    }

    /// Leaves edit mode and restores the draft.
    public func cancelEdit() {
        guard editTarget != nil else { return }
        editTarget = nil
        text = draftBeforeEdit
        draftBeforeEdit = ""
    }

    /// Clears the text, reply and edit.
    public func clear() {
        cancelEdit()
        replyTarget = nil
        text = ""
        drafts[chatId] = ""
        stopTyping()
    }

    /// Call when the composer leaves the screen.
    public func disappear() {
        stopTyping()
    }

    public func dismissError() {
        errorMessage = nil
    }

    // MARK: - Sending

    /// Sends the text (replying to `replyTarget`) or applies the edit. Keeps the text when it fails.
    public func send() async {
        guard canSend else { return }
        let body = trimmedText
        isSending = true
        defer { isSending = false }
        stopTyping()
        do {
            if let editTarget {
                if case .text(let original) = editTarget.content, original != body {
                    try await client.editMessage(chatId: chatId, messageId: editTarget.messageId, newBody: body)
                }
                self.editTarget = nil
                text = draftBeforeEdit
                draftBeforeEdit = ""
            } else {
                _ = try await client.sendText(chatId: chatId, body: body, replyTo: replyTarget?.messageId)
                replyTarget = nil
                text = ""
                drafts[chatId] = ""
            }
        } catch {
            await fail(error)
        }
    }

    /// Sends the file at `path` as an attachment (replying to `replyTarget`). The MIME type comes from the file
    /// extension; files over `MediaPreparation.maxFileSize` are refused. The client copies the file, so the caller
    /// may delete it afterwards. Returns whether it was sent.
    @discardableResult
    public func sendAttachment(atPath path: String) async -> Bool {
        guard canAttach else { return false }
        isSending = true
        defer { isSending = false }
        do {
            try MediaPreparation.validateSize(try MediaPreparation.fileSize(atPath: path))
            _ = try await client.sendMedia(
                chatId: chatId, filePath: path, mime: MediaPreparation.mimeType(forPath: path), caption: nil,
                replyTo: replyTarget?.messageId)
            replyTarget = nil
            return true
        } catch let error as MediaPreparationError {
            errorMessage = error.message
        } catch {
            await fail(error)
        }
        return false
    }

    /// Shows an error that happened while preparing an attachment.
    public func attachmentFailed(_ error: any Error) {
        errorMessage = (error as? MediaPreparationError)?.message ?? ErrorPresenter.message(for: error)
    }

    // MARK: - Rules

    /// Whether `message` can be edited: own, text, not deleted.
    public nonisolated static func canEdit(_ message: MessageItem) -> Bool {
        guard message.isOwn, case .text = message.content else { return false }
        return true
    }

    /// One-line summary of a message for the reply and edit bars.
    public nonisolated static func previewText(for message: MessageItem) -> String {
        previewKind(for: message).text
    }

    /// What the one-line summary of a message for the reply and edit bars says.
    public nonisolated static func previewKind(for message: MessageItem) -> MessagePreviewKind {
        switch message.content {
        case .text(let body):
            return .content(body)
        case .image(_, _, _, let caption):
            return nonEmpty(caption).map(MessagePreviewKind.content) ?? .photo
        case .file(_, let fileName, let caption):
            return (nonEmpty(caption) ?? nonEmpty(fileName)).map(MessagePreviewKind.content) ?? .file
        case .deleted:
            return .deleted
        case .unsupported:
            return .unsupported
        }
    }

    // MARK: - Private

    /// A send refused because the chat is not active makes the chat read-only instead of showing an error.
    private func fail(_ error: any Error) async {
        guard timeline?.handleChatNotActive(error) != true else { return }
        errorMessage = await ErrorPresenter.message(for: error, client: client)
    }

    private nonisolated static func nonEmpty(_ value: String?) -> String? {
        value.flatMap { $0.isEmpty ? nil : $0 }
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func updateTyping() {
        guard !trimmedText.isEmpty else {
            stopTyping()
            return
        }
        let current = now()
        if let typingSentAt, current.timeIntervalSince(typingSentAt) < Self.typingInterval { return }
        typingSentAt = current
        setTyping(true)
    }

    private func stopTyping() {
        guard typingSentAt != nil else { return }
        typingSentAt = nil
        setTyping(false)
    }

    /// Best effort: a lost typing indicator is not worth an error.
    private func setTyping(_ active: Bool) {
        let previous = typingTask
        let client = client
        let chatId = chatId
        typingTask = Task {
            await previous?.value
            try? await client.setTyping(chatId: chatId, active: active)
        }
    }
}

/// What the banner shown instead of the composer input says.
public enum ComposerReadOnlyKind: Sendable, Hashable {
    /// The user's leave is pending.
    case leaving
    /// The user left or was removed.
    case left

    /// The English text, localized through the FeaturesChat table.
    public var text: String {
        switch self {
        case .leaving:
            NSLocalizedString(
                "Leaving…", tableName: "FeaturesChat", bundle: FeaturesLocalization.bundle, value: "Leaving…",
                comment: "")
        case .left:
            NSLocalizedString(
                "You can no longer send messages in this chat.", tableName: "FeaturesChat",
                bundle: FeaturesLocalization.bundle, value: "You can no longer send messages in this chat.",
                comment: "")
        }
    }
}

/// What the one-line summary of a message for the reply and edit bars says.
public enum MessagePreviewKind: Sendable, Hashable {
    /// The text, caption or file name, shown as is.
    case content(String)
    /// An image without a caption.
    case photo
    /// A file without a caption or name.
    case file
    case deleted
    /// Content this version can't show.
    case unsupported

    /// The English text, localized through the FeaturesChat table.
    public var text: String {
        switch self {
        case .content(let content): content
        case .photo:
            NSLocalizedString(
                "Photo", tableName: "FeaturesChat", bundle: FeaturesLocalization.bundle, value: "Photo", comment: "")
        case .file:
            NSLocalizedString(
                "File", tableName: "FeaturesChat", bundle: FeaturesLocalization.bundle, value: "File", comment: "")
        case .deleted:
            NSLocalizedString(
                "This message was deleted", tableName: "FeaturesChat", bundle: FeaturesLocalization.bundle,
                value: "This message was deleted", comment: "")
        case .unsupported:
            NSLocalizedString(
                "Unsupported message", tableName: "FeaturesChat", bundle: FeaturesLocalization.bundle,
                value: "Unsupported message", comment: "")
        }
    }
}
