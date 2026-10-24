import Foundation
import GIMClientKit
import Observation

/// Mirrors gim-core's chat list and connection state. gim-core serves the list from its database, so this works
/// offline; sync is the core's job.
@MainActor
@Observable
public final class ChatListViewModel {
    /// The chats that are not archived, in the client's order: pinned first, then by recent activity.
    public var rows: [ChatRow] { allRows.filter { !$0.isArchived } }
    /// The archived chats, in the client's order.
    public var archivedRows: [ChatRow] { allRows.filter(\.isArchived) }
    public var hasArchived: Bool { allRows.contains(where: \.isArchived) }
    public private(set) var connectionState: ConnectionState = .offline
    /// True until the first chat list arrives.
    public private(set) var isLoading = true
    /// Set when subscribing failed.
    public private(set) var errorMessage: String?
    /// Set when pinning, muting or archiving a chat failed.
    public private(set) var actionErrorMessage: String?

    /// Every chat as the client lists it, archived ones included.
    private var allRows: [ChatRow] = []
    private let client: any GimClientAPI
    private let dateFormatter: RelativeDateFormatter
    private let now: () -> Date
    /// How the user left each left chat whose timeline was looked up: the newest own `left` or `removed` change.
    private var exits: [String: MembershipChangeKind] = [:]
    /// Lookups of `exits`, by chat id; kept once finished so each left chat is looked up once.
    @ObservationIgnored private var exitLookups: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var listTask: Task<Void, Never>?
    @ObservationIgnored private var connectionTask: Task<Void, Never>?

    /// - Parameter now: the clock for mutes: when they end and whether a row is muted.
    public init(
        client: any GimClientAPI, dateFormatter: RelativeDateFormatter = RelativeDateFormatter(),
        now: @escaping () -> Date = Date.init
    ) {
        self.client = client
        self.dateFormatter = dateFormatter
        self.now = now
    }

    /// The text under the row's title: `subtitleKind(for:)` in the FeaturesChat table.
    public func subtitle(for row: ChatRow) -> String {
        subtitleKind(for: row).text
    }

    /// What the text under the row's title says: the last message while the chat is active, otherwise its
    /// `ChatState`. A left chat says how the user left when its timeline shows the own `left` or `removed` change.
    public func subtitleKind(for row: ChatRow) -> ChatRowSubtitle {
        switch row.state {
        case .active: row.preview.map(ChatRowSubtitle.preview) ?? .noMessages
        case .leaving: .leaving
        case .left:
            switch exits[row.id] {
            case .left: .left
            case .removed: .removed
            case .added, nil: .leftUnknown
            }
        }
    }

    /// Status ticks of the row's last message: set while the chat is active and its last message is the user's own,
    /// from the preview's send state.
    public func lastMessageStatus(for row: ChatRow) -> MessageStatus? {
        guard row.state == .active else { return nil }
        return row.lastMessageStatus
    }

    deinit {
        listTask?.cancel()
        connectionTask?.cancel()
        for lookup in exitLookups.values { lookup.cancel() }
    }

    /// Subscribes to the chat list and the connection state. Does nothing while already subscribed.
    public func start() {
        guard listTask == nil else { return }
        errorMessage = nil
        let client = client
        listTask = Task { [weak self] in
            do {
                for await diffs in try await ListenerBridge.chatList(client) {
                    self?.apply(diffs)
                }
            } catch {
                self?.fail(error)
            }
        }
        connectionTask = Task { [weak self] in
            do {
                for await state in try await ListenerBridge.connectionState(client) {
                    self?.connectionState = state
                }
            } catch {
                self?.fail(error)
            }
        }
    }

    /// Cancels both subscriptions.
    public func stop() {
        listTask?.cancel()
        connectionTask?.cancel()
        listTask = nil
        connectionTask = nil
    }

    /// Subscribes again; the new subscription starts with a full reset.
    public func refresh() {
        stop()
        start()
    }

    private func apply(_ diffs: [ChatListDiff]) {
        isLoading = false
        let formatter = dateFormatter
        let date = now()
        let rowDiffs = diffs.map { $0.vectorDiff.map { ChatRow(summary: $0, dateFormatter: formatter, now: date) } }
        do {
            try DiffApplier.apply(rowDiffs, to: &allRows)
        } catch {
            // Out of sync with the core; a new subscription starts with a reset.
            refresh()
            return
        }
        lookUpExits()
    }

    public func setPinned(_ row: ChatRow, _ pinned: Bool) async {
        await perform { try await $0.setChatPinned(chatId: row.id, pinned: pinned) }
    }

    public func mute(_ row: ChatRow, _ option: ChatMuteOption) async {
        let mutedUntilMs = option.mutedUntilMs(now: now())
        await perform { try await $0.setChatMuted(chatId: row.id, mutedUntilMs: mutedUntilMs) }
    }

    public func unmute(_ row: ChatRow) async {
        await perform { try await $0.setChatMuted(chatId: row.id, mutedUntilMs: 0) }
    }

    public func setArchived(_ row: ChatRow, _ archived: Bool) async {
        await perform { try await $0.setChatArchived(chatId: row.id, archived: archived) }
    }

    public func dismissActionError() {
        actionErrorMessage = nil
    }

    /// Runs a chat setting change; the list follows through the subscription.
    private func perform(_ action: (any GimClientAPI) async throws -> Void) async {
        actionErrorMessage = nil
        do {
            try await action(client)
        } catch {
            actionErrorMessage = await ErrorPresenter.message(for: error, client: client)
        }
    }

    /// Looks up how the user left each newly left chat; forgets chats that are no longer left.
    private func lookUpExits() {
        let leftIds = Set(allRows.filter { $0.state == .left }.map(\.id))
        for (chatId, lookup) in exitLookups where !leftIds.contains(chatId) {
            lookup.cancel()
            exitLookups[chatId] = nil
            exits[chatId] = nil
        }
        let client = client
        for chatId in leftIds where exitLookups[chatId] == nil {
            exitLookups[chatId] = Task { [weak self] in
                guard let change = await Self.ownExit(client, chatId: chatId), !Task.isCancelled else { return }
                self?.exits[chatId] = change
            }
        }
    }

    /// The newest own `left` or `removed` change among the timeline items loaded so far; `nil` if there is none.
    private static func ownExit(_ client: any GimClientAPI, chatId: String) async -> MembershipChangeKind? {
        guard let ownUserId = client.userId(),
            let stream = try? await ListenerBridge.timeline(client, chatId: chatId)
        else { return nil }
        var items: [TimelineItem] = []
        // The first callback is the reset with the loaded items; ending the iteration cancels the subscription.
        for await diffs in stream {
            _ = try? DiffApplier.apply(diffs, to: &items)
            break
        }
        for case .membershipChange(_, let change, _, let userId, _) in items.reversed()
        where userId == ownUserId && change != .added {
            return change
        }
        return nil
    }

    private func fail(_ error: any Error) {
        isLoading = false
        errorMessage = ErrorPresenter.message(for: error)
    }
}

/// What the text under a chat row's title says.
public enum ChatRowSubtitle: Sendable, Hashable {
    /// The chat is active; the preview of its last message, shown as is.
    case preview(String)
    /// The chat is active and has no message yet.
    case noMessages
    /// The user's leave is pending.
    case leaving
    /// The user left the chat.
    case left
    /// The user was removed from the chat.
    case removed
    /// The chat is left; how is not known (yet).
    case leftUnknown

    /// The English text, localized through the FeaturesChat table.
    public var text: String {
        switch self {
        case .preview(let preview): preview
        case .noMessages:
            NSLocalizedString(
                "No messages yet", tableName: "FeaturesChat", bundle: FeaturesLocalization.bundle,
                value: "No messages yet", comment: "")
        case .leaving:
            NSLocalizedString(
                "Leaving…", tableName: "FeaturesChat", bundle: FeaturesLocalization.bundle, value: "Leaving…",
                comment: "")
        case .left:
            NSLocalizedString(
                "You left", tableName: "FeaturesChat", bundle: FeaturesLocalization.bundle, value: "You left",
                comment: "")
        case .removed:
            NSLocalizedString(
                "You were removed", tableName: "FeaturesChat", bundle: FeaturesLocalization.bundle,
                value: "You were removed", comment: "")
        case .leftUnknown:
            NSLocalizedString(
                "Left", tableName: "FeaturesChat", bundle: FeaturesLocalization.bundle, value: "Left",
                comment: "")
        }
    }
}
