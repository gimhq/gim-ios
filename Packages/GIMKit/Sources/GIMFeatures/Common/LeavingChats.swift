import Foundation
import GIMClientKit
import Observation

/// Chats the user is leaving, shared by all screens of the signed-in session.
///
/// `leaveChat` only submits a leave Proposal; another member commits it and the chat then shows the user's own
/// `Left` change. Until then (also across restarts) gim-core refuses sends to the chat with `InvalidInput`. A chat is
/// leaving after `leave(chatId:)` returns, or after a send to it was refused for that reason (see
/// `isLeavingRefusal(_:)`), and stops leaving once its timeline shows the own `Left` change or the chat is gone.
@MainActor
@Observable
public final class LeavingChats {
    public private(set) var chatIds: Set<String> = []

    private let client: any GimClientAPI
    private let now: () -> Date
    @ObservationIgnored private var watchers: [String: Task<Void, Never>] = [:]

    /// - Parameter now: clock that tells the own `Left` change from one of an earlier membership.
    public init(client: any GimClientAPI, now: @escaping () -> Date = Date.init) {
        self.client = client
        self.now = now
    }

    deinit {
        for watcher in watchers.values { watcher.cancel() }
    }

    public func contains(_ chatId: String) -> Bool {
        chatIds.contains(chatId)
    }

    /// Leaves the chat; it is leaving once the call returns.
    public func leave(chatId: String) async throws {
        let since = now()
        try await client.leaveChat(chatId: chatId)
        markLeaving(chatId, since: since)
    }

    /// Records that gim-core refused a send to the chat because it is leaving. Returns whether `error` is such a
    /// refusal; other errors are left to the caller.
    @discardableResult
    public func handleSendError(_ error: any Error, chatId: String) -> Bool {
        guard Self.isLeavingRefusal(error) else { return false }
        markLeaving(chatId, since: now())
        return true
    }

    /// gim-core refuses sends to a chat it is leaving with `InvalidInput("invalid state: leaving chat <id>")`. The
    /// reason text is not part of the API contract, so this is best effort: without it only `leave(chatId:)` marks a
    /// chat as leaving.
    public nonisolated static func isLeavingRefusal(_ error: any Error) -> Bool {
        guard case .InvalidInput(let reason) = error as? GimError else { return false }
        return reason.contains("leaving chat")
    }

    private func markLeaving(_ chatId: String, since: Date) {
        guard watchers[chatId] == nil else { return }
        chatIds.insert(chatId)
        let client = client
        let sinceMs = since.epochMilliseconds
        watchers[chatId] = Task { [weak self] in
            await Self.waitForOwnLeft(client, chatId: chatId, sinceMs: sinceMs)
            guard !Task.isCancelled else { return }
            self?.watchers[chatId] = nil
            self?.chatIds.remove(chatId)
        }
    }

    /// Returns once the timeline shows the own `Left` change applied at or after `sinceMs`, or the chat is gone.
    /// Membership changes carry the user's display name (or user id while the profile is unknown), not the id.
    private static func waitForOwnLeft(_ client: any GimClientAPI, chatId: String, sinceMs: UInt64) async {
        guard let session = try? await client.session(),
            let stream = try? await ListenerBridge.timeline(client, chatId: chatId)
        else { return }
        let ownNames: Set<String> = [session.displayName, session.userId]
        var items: [TimelineItem] = []
        for await diffs in stream {
            guard (try? DiffApplier.apply(diffs, to: &items)) != nil else { continue }
            let hasLeft = items.contains { item in
                guard case .membershipChange(let userName, .left, let atMs) = item else { return false }
                return atMs >= sinceMs && ownNames.contains(userName)
            }
            if hasLeft { return }
        }
    }
}
