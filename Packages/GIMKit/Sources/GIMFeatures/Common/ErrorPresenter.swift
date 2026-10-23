import Foundation
import GIMClientKit

/// Maps errors to user-facing text.
public enum ErrorPresenter {
    /// `UserSuspended` and `UserNotAdmitted` get the plain wording here and `message(for:client:)` names the hub;
    /// `ContactNotAdmitted` names the users by id (`contactNotAdmittedMessage(userIds:profiles:)` resolves names).
    public static func message(for error: any Error) -> String {
        guard let error = error as? GimError else { return genericMessage }
        switch error {
        case .Network:
            return NSLocalizedString(
                "Can't reach the server. Check your internet and try again.", tableName: "FeaturesCommon",
                bundle: FeaturesLocalization.bundle,
                value: "Can't reach the server. Check your internet and try again.", comment: "")
        case .NotRegistered:
            return NSLocalizedString(
                "This device isn't signed in. Sign in again.", tableName: "FeaturesCommon",
                bundle: FeaturesLocalization.bundle, value: "This device isn't signed in. Sign in again.", comment: "")
        case .InvalidInput(let reason):
            guard reason.isEmpty else { return reason }
            return NSLocalizedString(
                "Check what you typed and try again.", tableName: "FeaturesCommon",
                bundle: FeaturesLocalization.bundle, value: "Check what you typed and try again.", comment: "")
        case .NotFound:
            return NSLocalizedString(
                "Couldn't find that. It may have been removed.", tableName: "FeaturesCommon",
                bundle: FeaturesLocalization.bundle, value: "Couldn't find that. It may have been removed.",
                comment: "")
        case .Crypto:
            return NSLocalizedString(
                "Couldn't unlock this message.", tableName: "FeaturesCommon", bundle: FeaturesLocalization.bundle,
                value: "Couldn't unlock this message.", comment: "")
        case .Storage:
            return NSLocalizedString(
                "Couldn't save on this device. Free up some space and try again.", tableName: "FeaturesCommon",
                bundle: FeaturesLocalization.bundle,
                value: "Couldn't save on this device. Free up some space and try again.", comment: "")
        case .Server:
            return NSLocalizedString(
                "The server couldn't do that right now. Try again later.", tableName: "FeaturesCommon",
                bundle: FeaturesLocalization.bundle, value: "The server couldn't do that right now. Try again later.",
                comment: "")
        case .RetryLater(let status, let retryAfterSecs, _):
            // 429: the own hub throttles; 503: a remote hub is unavailable (federation).
            let format =
                status == 429
                ? NSLocalizedString(
                    "The server is busy. Try again in %lld s.", tableName: "FeaturesCommon",
                    bundle: FeaturesLocalization.bundle, value: "The server is busy. Try again in %lld s.", comment: "")
                : NSLocalizedString(
                    "Another server isn't answering. Try again in %lld s.", tableName: "FeaturesCommon",
                    bundle: FeaturesLocalization.bundle, value: "Another server isn't answering. Try again in %lld s.",
                    comment: "")
            return String(format: format, Int(retryAfterSecs))
        case .Cancelled:
            return NSLocalizedString(
                "That was cancelled.", tableName: "FeaturesCommon", bundle: FeaturesLocalization.bundle,
                value: "That was cancelled.", comment: "")
        case .NotImplemented:
            return NSLocalizedString(
                "This isn't available yet.", tableName: "FeaturesCommon", bundle: FeaturesLocalization.bundle,
                value: "This isn't available yet.", comment: "")
        case .Internal:
            return genericMessage
        case .ChatNotActive(_, .leaving):
            return NSLocalizedString(
                "You're leaving this chat.", tableName: "FeaturesCommon", bundle: FeaturesLocalization.bundle,
                value: "You're leaving this chat.", comment: "")
        case .ChatNotActive:
            return NSLocalizedString(
                "You're no longer in this chat.", tableName: "FeaturesCommon", bundle: FeaturesLocalization.bundle,
                value: "You're no longer in this chat.", comment: "")
        case .HubNotVerified:
            return NSLocalizedString(
                "Couldn't reach a server at this address. Check the address and try again.",
                tableName: "FeaturesCommon", bundle: FeaturesLocalization.bundle,
                value: "Couldn't reach a server at this address. Check the address and try again.", comment: "")
        case .HubOwnsGroups(_, let groupCount):
            if groupCount == 1 {
                return NSLocalizedString(
                    "This server hosts 1 group you own.", tableName: "FeaturesCommon",
                    bundle: FeaturesLocalization.bundle, value: "This server hosts 1 group you own.", comment: "")
            }
            let format = NSLocalizedString(
                "This server hosts %lld groups you own.", tableName: "FeaturesCommon",
                bundle: FeaturesLocalization.bundle, value: "This server hosts %lld groups you own.", comment: "")
            return String(format: format, Int(groupCount))
        case .LastHub:
            return NSLocalizedString(
                "This is your only server. Add another server before you remove it.", tableName: "FeaturesCommon",
                bundle: FeaturesLocalization.bundle,
                value: "This is your only server. Add another server before you remove it.", comment: "")
        case .HomeHub:
            return NSLocalizedString(
                "Your main server can't be removed. Make another server the main one first.",
                tableName: "FeaturesCommon", bundle: FeaturesLocalization.bundle,
                value: "Your main server can't be removed. Make another server the main one first.", comment: "")
        case .HubNotDrained:
            return NSLocalizedString(
                "Messages sent through this server are still on their way. Try again later.",
                tableName: "FeaturesCommon", bundle: FeaturesLocalization.bundle,
                value: "Messages sent through this server are still on their way. Try again later.", comment: "")
        case .UserSuspended:
            return suspendedMessage(host: nil)
        case .UserNotAdmitted:
            return notAdmittedMessage(host: nil)
        case .NotAdmittedByPeer:
            return notAdmittedByPeerMessage
        case .ContactNotAdmitted(let userIds):
            return contactNotAdmittedMessage(userIds: userIds, profiles: [])
        }
    }

    /// Like `message(for:)`, for onboarding (`createIdentity`, `restoreFromRecovery`, `waitLink`) and Add Hub: a hub
    /// that does not admit the user refuses that hub (`hubRefusedMessage`).
    public static func registrationMessage(for error: any Error) -> String {
        guard case .UserNotAdmitted = error as? GimError else { return message(for: error) }
        return hubRefusedMessage
    }

    /// Like `message(for:)`, but `UserSuspended` and `UserNotAdmitted` name the hub when the user has more than one
    /// listed hub, from the client's hubs (only read for those errors).
    @MainActor
    public static func message(for error: any Error, client: any GimClientAPI) async -> String {
        switch error as? GimError {
        case .UserSuspended(let hubId)?:
            return suspendedMessage(hubId: hubId, hubs: (try? await client.hubs()) ?? [])
        case .UserNotAdmitted(let hubId)?:
            return notAdmittedMessage(hubId: hubId, hubs: (try? await client.hubs()) ?? [])
        default:
            return message(for: error)
        }
    }

    /// The "account suspended" text: names the hub `hubId` by its URL host when more than one hub is listed; the plain
    /// wording for a single hub or an empty or unknown `hubId`.
    public static func suspendedMessage(hubId: String, hubs: [HubInfo]) -> String {
        suspendedMessage(host: host(of: hubId, in: hubs))
    }

    /// The "account not admitted" text, naming the hub like `suspendedMessage(hubId:hubs:)`.
    public static func notAdmittedMessage(hubId: String, hubs: [HubInfo]) -> String {
        notAdmittedMessage(host: host(of: hubId, in: hubs))
    }

    /// Why a failed send is not offered for retry (`SendFailure.userSuspended`, `.userNotAdmitted` or
    /// `.notAdmittedByPeer`); `nil` for causes that can be retried.
    public static func sendFailureMessage(_ cause: SendFailure) -> String? {
        switch cause {
        case .userSuspended: suspendedMessage(host: nil)
        case .userNotAdmitted: notAdmittedMessage(host: nil)
        case .notAdmittedByPeer: notAdmittedByPeerMessage
        case .rejected, .other: nil
        }
    }

    /// "<names> doesn't/don't accept messages from you." for `ContactNotAdmitted`: each user is named by the display
    /// name of its profile in `profiles`, else its handle, else its user id.
    public static func contactNotAdmittedMessage(userIds: [String], profiles: [UserProfile]) -> String {
        let names = userIds.map { userId in
            guard let profile = profiles.first(where: { $0.userId == userId }) else { return userId }
            if !profile.displayName.isEmpty { return profile.displayName }
            return profile.handle.isEmpty ? userId : "@\(profile.handle)"
        }
        guard let last = names.last else {
            return NSLocalizedString(
                "This person doesn't accept messages from you.", tableName: "FeaturesCommon",
                bundle: FeaturesLocalization.bundle, value: "This person doesn't accept messages from you.",
                comment: "")
        }
        if names.count == 1 {
            let format = NSLocalizedString(
                "%@ doesn't accept messages from you.", tableName: "FeaturesCommon",
                bundle: FeaturesLocalization.bundle, value: "%@ doesn't accept messages from you.", comment: "")
            return String(format: format, last)
        }
        let list = names.dropLast().joined(separator: ", ") + " and " + last
        let format = NSLocalizedString(
            "%@ don't accept messages from you.", tableName: "FeaturesCommon", bundle: FeaturesLocalization.bundle,
            value: "%@ don't accept messages from you.", comment: "")
        return String(format: format, list)
    }

    /// The URL host of the listed hub `hubId` when more than one hub is listed; `nil` for a single hub or an empty or
    /// unknown `hubId`.
    private static func host(of hubId: String, in hubs: [HubInfo]) -> String? {
        let listed = hubs.filter { $0.state != .removed }
        guard listed.count > 1, !hubId.isEmpty, let url = listed.first(where: { $0.hubId == hubId })?.url,
            let host = URLComponents(string: url)?.host, !host.isEmpty
        else { return nil }
        return host.lowercased()
    }

    static func suspendedMessage(host: String?) -> String {
        let suspended: String
        if let host {
            let format = NSLocalizedString(
                "Your account is suspended on %@.", tableName: "FeaturesCommon", bundle: FeaturesLocalization.bundle,
                value: "Your account is suspended on %@.", comment: "")
            suspended = String(format: format, host)
        } else {
            suspended = NSLocalizedString(
                "Your account is suspended.", tableName: "FeaturesCommon", bundle: FeaturesLocalization.bundle,
                value: "Your account is suspended.", comment: "")
        }
        return suspended + " "
            + NSLocalizedString(
                "Your chats on this device stay readable. Contact the server's operator to get access back.",
                tableName: "FeaturesCommon", bundle: FeaturesLocalization.bundle,
                value: "Your chats on this device stay readable. Contact the server's operator to get access back.",
                comment: "")
    }

    static func notAdmittedMessage(host: String?) -> String {
        guard let host else {
            return NSLocalizedString(
                "This server doesn't accept your account.", tableName: "FeaturesCommon",
                bundle: FeaturesLocalization.bundle, value: "This server doesn't accept your account.", comment: "")
        }
        let format = NSLocalizedString(
            "%@ doesn't accept your account.", tableName: "FeaturesCommon", bundle: FeaturesLocalization.bundle,
            value: "%@ doesn't accept your account.", comment: "")
        return String(format: format, host)
    }

    static let genericMessage = NSLocalizedString(
        "Something went wrong. Try again.", tableName: "FeaturesCommon", bundle: FeaturesLocalization.bundle,
        value: "Something went wrong. Try again.", comment: "")
    /// `NotAdmittedByPeer`, and sends that failed with `SendFailure.notAdmittedByPeer`.
    public static let notAdmittedByPeerMessage = NSLocalizedString(
        "This chat's server doesn't accept messages from you.", tableName: "FeaturesCommon",
        bundle: FeaturesLocalization.bundle, value: "This chat's server doesn't accept messages from you.", comment: "")
    /// `UserNotAdmitted` on onboarding and Add Hub: that hub refused the registration.
    public static let hubRefusedMessage = NSLocalizedString(
        "This server doesn't accept your account.", tableName: "FeaturesCommon", bundle: FeaturesLocalization.bundle,
        value: "This server doesn't accept your account.", comment: "")
}
