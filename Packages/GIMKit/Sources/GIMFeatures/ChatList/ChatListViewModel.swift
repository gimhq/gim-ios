import Foundation
import GIMClientKit
import Observation

/// Mirrors gim-core's chat list and connection state. gim-core serves the list from its database, so this works
/// offline; sync is the core's job.
@MainActor
@Observable
public final class ChatListViewModel {
    public private(set) var rows: [ChatRow] = []
    public private(set) var connectionState: ConnectionState = .offline
    /// True until the first chat list arrives.
    public private(set) var isLoading = true
    /// Set when subscribing failed.
    public private(set) var errorMessage: String?

    private let client: any GimClientAPI
    private let dateFormatter: RelativeDateFormatter
    /// How the user left each left chat whose timeline was looked up: the newest own `left` or `removed` change.
    private var exits: [String: MembershipChangeKind] = [:]
    /// Lookups of `exits`, by chat id; kept once finished so each left chat is looked up once.
    @ObservationIgnored private var exitLookups: [String: Task<Void, Never>] = [:]
    /// How many own-last-message timelines are followed at once; a chat beyond the cap closes the oldest lookup.
    public static let maxStatusLookups = 20
    /// Status of the own last message of each active chat whose timeline was looked up, by chat id.
    private var lastMessageStatuses: [String: MessageStatus] = [:]
    /// Lookups of `lastMessageStatuses`, by chat id, each with the `lastMessageSentAtMs` it was started for.
    @ObservationIgnored private var statusLookups: [String: StatusLookup] = [:]
    /// Start order of the last status lookup; lower is older.
    @ObservationIgnored private var statusLookupOrder = 0
    @ObservationIgnored private var listTask: Task<Void, Never>?
    @ObservationIgnored private var connectionTask: Task<Void, Never>?

    private struct StatusLookup {
        var sentAtMs: UInt64?
        var order: Int
        /// `nil` once the cap closed the lookup; it reopens when a slot is free.
        var task: Task<Void, Never>?
    }

    public init(client: any GimClientAPI, dateFormatter: RelativeDateFormatter = RelativeDateFormatter()) {
        self.client = client
        self.dateFormatter = dateFormatter
    }

    /// The text under the row's title: the last message while the chat is active, otherwise its `ChatState`.
    /// A left chat says how the user left when its timeline shows the own `left` or `removed` change.
    public func subtitle(for row: ChatRow) -> String {
        switch row.state {
        case .active: row.preview ?? "No messages yet"
        case .leaving: "Leaving…"
        case .left:
            switch exits[row.id] {
            case .left: "You left"
            case .removed: "You were removed"
            case .added, nil: "Left"
            }
        }
    }

    /// Status ticks of the row's last message: set once the chat is active, its last message is the user's own and
    /// the lookup in the chat's timeline finished.
    public func lastMessageStatus(for row: ChatRow) -> MessageStatus? {
        guard row.state == .active, row.lastMessageIsOwn else { return nil }
        return lastMessageStatuses[row.id]
    }

    deinit {
        listTask?.cancel()
        connectionTask?.cancel()
        for lookup in exitLookups.values { lookup.cancel() }
        for lookup in statusLookups.values { lookup.task?.cancel() }
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

    /// Cancels both subscriptions and the status lookups.
    public func stop() {
        listTask?.cancel()
        connectionTask?.cancel()
        listTask = nil
        connectionTask = nil
        for lookup in statusLookups.values { lookup.task?.cancel() }
        statusLookups = [:]
    }

    /// Subscribes again; the new subscription starts with a full reset.
    public func refresh() {
        stop()
        start()
    }

    private func apply(_ diffs: [ChatListDiff]) {
        isLoading = false
        let formatter = dateFormatter
        let rowDiffs = diffs.map { $0.vectorDiff.map { ChatRow(summary: $0, dateFormatter: formatter) } }
        do {
            try DiffApplier.apply(rowDiffs, to: &rows)
        } catch {
            // Out of sync with the core; a new subscription starts with a reset.
            refresh()
            return
        }
        lookUpExits()
        lookUpLastMessageStatuses()
    }

    /// Looks up how the user left each newly left chat; forgets chats that are no longer left.
    private func lookUpExits() {
        let leftIds = Set(rows.filter { $0.state == .left }.map(\.id))
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

    /// Follows the status of the own last message of each active chat; a chat is looked up again when its last
    /// message changes and forgotten when its last message is someone else's or it is no longer active. At most
    /// `maxStatusLookups` lookups are open: a chat that newly qualifies closes the oldest, a chat closed by the cap
    /// reopens only into a free slot.
    private func lookUpLastMessageStatuses() {
        let qualifying = rows.filter { $0.state == .active && $0.lastMessageIsOwn }
        let wanted = Dictionary(
            qualifying.map { ($0.id, $0.lastMessageSentAtMs) }, uniquingKeysWith: { _, last in last })
        for (chatId, lookup) in statusLookups where wanted[chatId] != .some(lookup.sentAtMs) {
            lookup.task?.cancel()
            statusLookups[chatId] = nil
            lastMessageStatuses[chatId] = nil
        }
        var openCount = statusLookups.values.filter { $0.task != nil }.count
        for row in qualifying {
            if let lookup = statusLookups[row.id] {
                guard lookup.task == nil, openCount < Self.maxStatusLookups else { continue }
            } else if openCount >= Self.maxStatusLookups,
                let oldest = statusLookups.filter({ $0.value.task != nil }).min(by: { $0.value.order < $1.value.order })
            {
                oldest.value.task?.cancel()
                statusLookups[oldest.key]?.task = nil
                lastMessageStatuses[oldest.key] = nil
                openCount -= 1
            }
            statusLookupOrder += 1
            statusLookups[row.id] = StatusLookup(
                sentAtMs: row.lastMessageSentAtMs, order: statusLookupOrder, task: followLastMessageStatus(row.id))
            openCount += 1
        }
    }

    /// Subscribes to the chat's timeline and stores the status of its newest own message after each batch. The
    /// subscription stays open so the ticks follow sent -> delivered -> read; cancelling the task ends it.
    private func followLastMessageStatus(_ chatId: String) -> Task<Void, Never> {
        let client = client
        return Task { [weak self] in
            guard let stream = try? await ListenerBridge.timeline(client, chatId: chatId) else { return }
            var items: [TimelineItem] = []
            for await diffs in stream {
                _ = try? DiffApplier.apply(diffs, to: &items)
                guard !Task.isCancelled else { return }
                self?.lastMessageStatuses[chatId] = Self.newestOwnMessageStatus(items)
            }
        }
    }

    /// Status of the newest message among `items` when it is the user's own; `nil` when it is someone else's or
    /// there is no message.
    private static func newestOwnMessageStatus(_ items: [TimelineItem]) -> MessageStatus? {
        for case .message(let message) in items.reversed() {
            return message.isOwn ? message.sendState.map(MessageStatus.init) : nil
        }
        return nil
    }

    private func fail(_ error: any Error) {
        isLoading = false
        errorMessage = ErrorPresenter.message(for: error)
    }
}
