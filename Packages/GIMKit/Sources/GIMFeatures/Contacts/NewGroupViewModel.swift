import Foundation
import GIMClientKit
import Observation

/// Collects a group name and members (added by exact handle) and creates the group.
@MainActor
@Observable
public final class NewGroupViewModel {
    /// Members besides the current user.
    public static let minimumMembers = 2
    /// `createGroupChat` and `addMembers` fail with `NotFound` when every invitee is unknown or has no device (or with
    /// `ContactNotAdmitted` when one of them refused this user). Some skipped invitees do not fail the call; the
    /// timeline reports each as removed.
    public static let noneFoundMessage = NSLocalizedString(
        "Couldn't find anyone with these usernames.", tableName: "FeaturesContacts",
        bundle: FeaturesLocalization.bundle, value: "Couldn't find anyone with these usernames.", comment: "")

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
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return NSLocalizedString(
                "Enter a group name.", tableName: "FeaturesContacts", bundle: FeaturesLocalization.bundle,
                value: "Enter a group name.", comment: "")
        }
        if members.count < Self.minimumMembers {
            let format = NSLocalizedString(
                "Add at least %lld members.", tableName: "FeaturesContacts", bundle: FeaturesLocalization.bundle,
                value: "Add at least %lld members.", comment: "")
            return String(format: format, Self.minimumMembers)
        }
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
                let format = NSLocalizedString(
                    "No one has the username @%@.", tableName: "FeaturesContacts",
                    bundle: FeaturesLocalization.bundle, value: "No one has the username @%@.", comment: "")
                memberError = String(format: format, handle)
                return
            }
            if try await client.session()?.userId == user.userId {
                memberError = NSLocalizedString(
                    "You're in your own groups automatically.", tableName: "FeaturesContacts",
                    bundle: FeaturesLocalization.bundle, value: "You're in your own groups automatically.",
                    comment: "")
                return
            }
            if !members.contains(where: { $0.userId == user.userId }) { members.append(user) }
            memberHandle = ""
        } catch {
            memberError = await ErrorPresenter.message(for: error, client: client)
        }
    }

    public func removeMember(_ userId: String) {
        members.removeAll { $0.userId == userId }
    }

    /// Creates the group. Returns `nil` when the form is invalid or creation failed.
    public func create() async -> String? {
        guard canCreate else { return nil }
        isCreating = true
        errorMessage = nil
        defer { isCreating = false }
        do {
            return try await client.createGroupChat(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines), memberUserIds: members.map(\.userId))
        } catch GimError.NotFound {
            errorMessage = Self.noneFoundMessage
            return nil
        } catch GimError.ContactNotAdmitted(let userIds) {
            errorMessage = ErrorPresenter.contactNotAdmittedMessage(userIds: userIds, profiles: members)
            return nil
        } catch {
            errorMessage = await ErrorPresenter.message(for: error, client: client)
            return nil
        }
    }
}
