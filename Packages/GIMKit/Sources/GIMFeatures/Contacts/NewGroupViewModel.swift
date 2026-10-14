import Foundation
import GIMClientKit
import Observation

/// Collects a group name and members (added by exact handle) and creates the group.
@MainActor
@Observable
public final class NewGroupViewModel {
    /// Members besides the current user.
    public static let minimumMembers = 2

    public var name = ""
    /// Handle typed into the "add member" field.
    public var memberHandle = ""
    public private(set) var members: [UserProfile] = []
    public private(set) var isAddingMember = false
    /// Error from the last `addMember()`.
    public private(set) var memberError: String?
    public private(set) var isCreating = false
    /// Error from the last `create()`.
    public private(set) var errorMessage: String?

    private let client: any GimClientAPI

    public init(client: any GimClientAPI) {
        self.client = client
    }

    /// Why the group can't be created yet, or `nil` when it can.
    public var validationMessage: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter a group name." }
        if members.count < Self.minimumMembers { return "Add at least \(Self.minimumMembers) members." }
        return nil
    }

    public var canCreate: Bool { validationMessage == nil && !isCreating }

    /// Looks up `memberHandle` and adds the user as a chip.
    public func addMember() async {
        let handle = OnboardingValidation.normalizedHandle(memberHandle)
        guard !handle.isEmpty, !isAddingMember else { return }
        isAddingMember = true
        memberError = nil
        defer { isAddingMember = false }
        do {
            guard let user = try await client.findUser(handle: handle) else {
                memberError = "No one uses the handle @\(handle)."
                return
            }
            if case .registered(let session) = try await client.loginState(), session.userId == user.userId {
                memberError = "You are added to your groups automatically."
                return
            }
            if !members.contains(where: { $0.userId == user.userId }) { members.append(user) }
            memberHandle = ""
        } catch {
            memberError = ErrorPresenter.message(for: error)
        }
    }

    public func removeMember(_ userId: UserId) {
        members.removeAll { $0.userId == userId }
    }

    /// Creates the group. Returns `nil` when the form is invalid or creation failed.
    public func create() async -> ChatId? {
        guard canCreate else { return nil }
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }
        do {
            return try await client.createGroupChat(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines), members: members.map(\.userId))
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
            return nil
        }
    }
}
