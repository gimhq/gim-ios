import Foundation
import GIMClientKit
import Observation

/// The conversation menu of one chat: pin, mute, archive and, in a direct chat, block the other user.
///
/// The state follows the chat's `ChatSummary` in the chat list; each action only calls the client, and the change
/// comes back through the list.
@MainActor
@Observable
public final class ChatActionsViewModel {
    public let chatId: String
    /// Set when a chat setting change or a block failed.
    public private(set) var errorMessage: String?

    /// The chat's last known summary; kept when the chat leaves the list. `nil` until the chat list arrives.
    private var summary: ChatSummary?
    private let client: any GimClientAPI
    private let now: () -> Date
    @ObservationIgnored private var chatList: [ChatSummary] = []
    @ObservationIgnored private var listTask: Task<Void, Never>?

    /// - Parameter now: the clock for mutes: when they end and whether the chat is muted.
    public init(client: any GimClientAPI, chatId: String, now: @escaping () -> Date = Date.init) {
        self.client = client
        self.chatId = chatId
        self.now = now
    }

    deinit {
        listTask?.cancel()
    }

    public var isGroup: Bool { summary?.kind == .group }
    public var isPinned: Bool { summary?.pinned ?? false }
    /// True while notifications are muted (`ChatSummary.mutedUntilMs`), checked like `ChatRow.isMuted`.
    public var isMuted: Bool {
        guard let mutedUntilMs = summary?.mutedUntilMs else { return false }
        return mutedUntilMs == mutedForever() || mutedUntilMs > now().epochMilliseconds
    }
    public var isArchived: Bool { summary?.archived ?? false }
    /// A direct chat whose other user is blocked.
    public var isBlocked: Bool { summary?.blocked ?? false }
    /// The other user of a direct chat; `nil` for a group or before the chat list arrives.
    public var peerName: String? { summary?.peer.map(UserLabel.name(for:)) }
    /// The note to self: there is no one to block or report.
    public var isNoteToSelf: Bool { summary?.isNoteToSelf ?? false }
    /// A direct chat with a known other user, who can be blocked or unblocked.
    public var canBlock: Bool { !isGroup && !isNoteToSelf && summary?.peer != nil }

    // MARK: - Subscription

    /// Subscribes to the chat list. Does nothing while already subscribed.
    public func start() {
        guard listTask == nil else { return }
        let client = client
        listTask = Task { [weak self] in
            guard let stream = try? await ListenerBridge.chatList(client) else { return }
            for await diffs in stream {
                self?.applyChatList(diffs)
            }
        }
    }

    public func stop() {
        listTask?.cancel()
        listTask = nil
        chatList = []
    }

    // MARK: - Actions

    public func setPinned(_ pinned: Bool) async {
        await perform { [chatId] in try await $0.setChatPinned(chatId: chatId, pinned: pinned) }
    }

    public func mute(_ option: ChatMuteOption) async {
        let mutedUntilMs = option.mutedUntilMs(now: now())
        await perform { [chatId] in try await $0.setChatMuted(chatId: chatId, mutedUntilMs: mutedUntilMs) }
    }

    public func unmute() async {
        await perform { [chatId] in try await $0.setChatMuted(chatId: chatId, mutedUntilMs: 0) }
    }

    public func setArchived(_ archived: Bool) async {
        await perform { [chatId] in try await $0.setChatArchived(chatId: chatId, archived: archived) }
    }

    /// Blocks the other user of a direct chat. The screen asks for confirmation first. Does nothing without one.
    public func block() async {
        guard canBlock, let userId = summary?.peer?.userId else { return }
        await perform { try await $0.blockUser(userId: userId) }
    }

    /// Unblocks the other user of a direct chat. Does nothing without one.
    public func unblock() async {
        guard canBlock, let userId = summary?.peer?.userId else { return }
        await perform { try await $0.unblockUser(userId: userId) }
    }

    public func dismissError() {
        errorMessage = nil
    }

    /// Runs a change; the state follows through the chat list.
    private func perform(_ action: (any GimClientAPI) async throws -> Void) async {
        errorMessage = nil
        do {
            try await action(client)
        } catch {
            errorMessage = await ErrorPresenter.message(for: error, client: client)
        }
    }

    private func applyChatList(_ diffs: [ChatListDiff]) {
        guard (try? DiffApplier.apply(diffs, to: &chatList)) != nil,
            let summary = chatList.first(where: { $0.chatId == chatId }), summary != self.summary
        else { return }
        self.summary = summary
    }
}
