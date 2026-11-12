import Foundation
import GIMClientKit
import Observation

/// Collects a group name and members (added by Account ID) and creates the group.
@MainActor
@Observable
public final class NewGroupViewModel {
    /// Members besides the current user.
    public static let minimumMembers = 2
    /// `createGroupChat` and `addMembers` fail with `NotFound` when every invitee is unknown or has no device (or with
    /// `ContactNotAdmitted` when one of them refused this user). Some skipped invitees do not fail the call; the
    /// timeline reports each as removed.
    public static let noneFoundMessage = NSLocalizedString(
        "Couldn't find anyone with these Account IDs.", tableName: "FeaturesContacts",
        bundle: FeaturesLocalization.bundle, value: "Couldn't find anyone with these Account IDs.", comment: "")

    public var name = ""
    /// Account ID typed or pasted into the "add member" field.
    public var memberAccountId = ""
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

    /// Adds the user of the first Account ID in `memberAccountId` as a chip. The ID is not looked up: an unknown user
    /// fails `create()` with `NotFound`, or is reported as removed in the timeline.
    public func addMember() async {
        guard !isAddingMember, !memberAccountId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        memberError = nil
        guard let userId = UserID.firstValid(in: memberAccountId) else {
            memberError = ContactsText.notAnAccountId
            return
        }
        isAddingMember = true
        defer { isAddingMember = false }
        do {
            if try await client.session()?.userId == userId {
                memberError = ContactsText.ownGroup
                return
            }
        } catch {
            memberError = await ErrorPresenter.message(for: error, client: client)
            return
        }
        if !members.contains(where: { $0.userId == userId }) {
            members.append(UserProfile(userId: userId, displayName: ""))
        }
        memberAccountId = ""
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

/// Messages of the `FeaturesContacts` table shared by the contact view models.
enum ContactsText {
    static let notAnAccountId = NSLocalizedString(
        "This isn't a gim Account ID.", tableName: "FeaturesContacts", bundle: FeaturesLocalization.bundle,
        value: "This isn't a gim Account ID.", comment: "")
    static let ownGroup = NSLocalizedString(
        "You're in your own groups automatically.", tableName: "FeaturesContacts",
        bundle: FeaturesLocalization.bundle, value: "You're in your own groups automatically.", comment: "")
}
