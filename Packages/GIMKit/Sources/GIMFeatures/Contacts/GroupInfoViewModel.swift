import Foundation
import GIMClientKit
import Observation

/// Shows a chat's details and manages group members.
@MainActor
@Observable
public final class GroupInfoViewModel {
    public let chatId: ChatId
    public private(set) var details: ChatDetails?
    public private(set) var isLoading = false
    /// Error from the last load or member change.
    public private(set) var errorMessage: String?

    /// Handle typed into the "add member" field.
    public var memberHandle = ""
    public private(set) var isUpdatingMembers = false
    /// Member waiting for the user to confirm removal.
    public private(set) var pendingRemoval: ChatMember?

    private let client: any GimClientAPI

    public init(client: any GimClientAPI, chatId: ChatId) {
        self.client = client
        self.chatId = chatId
    }

    /// Members can only be changed in groups.
    public var canEditMembers: Bool { details?.summary.kind == .group }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            details = try await client.chatDetails(chatId)
            errorMessage = nil
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// Looks up `memberHandle`, adds the user and reloads.
    public func addMember() async {
        let handle = OnboardingValidation.normalizedHandle(memberHandle)
        guard !handle.isEmpty else { return }
        await updateMembers {
            guard let user = try await self.client.findUser(handle: handle) else {
                self.errorMessage = "No one uses the handle @\(handle)."
                return false
            }
            try await self.client.addMember(self.chatId, user: user.userId)
            self.memberHandle = ""
            return true
        }
    }

    /// Asks for confirmation before removing `member`. The current user can't be removed.
    public func requestRemoval(_ member: ChatMember) {
        guard !member.isSelf else { return }
        pendingRemoval = member
    }

    public func cancelRemoval() {
        pendingRemoval = nil
    }

    /// Removes the member awaiting confirmation and reloads.
    public func confirmRemoval() async {
        guard let member = pendingRemoval else { return }
        pendingRemoval = nil
        await updateMembers {
            try await self.client.removeMember(self.chatId, user: member.user.userId)
            return true
        }
    }

    /// Runs `change` and reloads when it reports a change.
    private func updateMembers(_ change: () async throws -> Bool) async {
        guard !isUpdatingMembers else { return }
        isUpdatingMembers = true
        errorMessage = nil
        defer { isUpdatingMembers = false }
        do {
            guard try await change() else { return }
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
            return
        }
        await load()
    }
}
