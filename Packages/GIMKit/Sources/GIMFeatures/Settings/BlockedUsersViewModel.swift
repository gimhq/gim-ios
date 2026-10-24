import Foundation
import GIMClientKit
import Observation

/// The blocked people list, with names resolved from the local chats where possible.
@MainActor
@Observable
public final class BlockedUsersViewModel {
    public struct Row: Sendable, Hashable, Identifiable {
        public var userId: String
        /// `UserLabel.name(for:)` of the user, or `nil` when no chat knows them: show the Account ID instead.
        public var name: String?
        /// `UserLabel.detail(for:)` of the user; `nil` with `name`.
        public var detail: String?

        public var id: String { userId }

        public init(userId: String, name: String?, detail: String?) {
            self.userId = userId
            self.name = name
            self.detail = detail
        }
    }

    public private(set) var rows: [Row] = []
    /// `false` until the first `load()` finished, so the empty state does not flash.
    public private(set) var isLoaded = false
    /// Users whose unblock is in flight.
    public private(set) var unblocking: Set<String> = []
    /// Error from the last failed load or unblock, already localized by `ErrorPresenter`.
    public private(set) var errorMessage: String?

    private let client: any GimClientAPI

    public init(client: any GimClientAPI) {
        self.client = client
    }

    public func load() async {
        do {
            let blockedUserIds = try await client.privacy().blockedUserIds
            let profiles = await knownProfiles(of: Set(blockedUserIds))
            rows = blockedUserIds.map { userId in
                let profile = profiles[userId]
                return Row(
                    userId: userId, name: profile.map(UserLabel.name(for:)), detail: profile.map(UserLabel.detail(for:))
                )
            }
        } catch {
            errorMessage = await ErrorPresenter.message(for: error, client: client)
        }
        isLoaded = true
    }

    public func unblock(userId: String) async {
        guard !unblocking.contains(userId) else { return }
        unblocking.insert(userId)
        defer { unblocking.remove(userId) }
        do {
            try await client.unblockUser(userId: userId)
            rows.removeAll { $0.userId == userId }
            errorMessage = nil
        } catch {
            errorMessage = await ErrorPresenter.message(for: error, client: client)
        }
    }

    /// Profiles of `userIds` from the peers of direct chats, then from the members of group chats while some are still
    /// unknown. Best effort: chats that cannot be read are skipped.
    private func knownProfiles(of userIds: Set<String>) async -> [String: UserProfile] {
        guard !userIds.isEmpty else { return [:] }
        let chats = await currentChats()
        var profiles: [String: UserProfile] = [:]
        for case let peer? in chats.map(\.peer) where userIds.contains(peer.userId) {
            profiles[peer.userId] = peer
        }
        for chat in chats where chat.kind == .group && profiles.count < userIds.count {
            guard let members = try? await client.chatMembers(chatId: chat.chatId) else { continue }
            for member in members where userIds.contains(member.userId) && profiles[member.userId] == nil {
                profiles[member.userId] = member
            }
        }
        return profiles
    }

    /// The chat list's first batch, which carries the current list.
    private func currentChats() async -> [ChatSummary] {
        guard let stream = try? await ListenerBridge.chatList(client) else { return [] }
        var chats: [ChatSummary] = []
        for await diffs in stream {
            try? DiffApplier.apply(diffs, to: &chats)
            break
        }
        return chats
    }
}
