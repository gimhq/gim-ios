import Foundation
import GIMClientKit

/// Maps errors to user-facing text.
public enum ErrorPresenter {
    /// One user-facing error sentence, carrying what its text needs; `text(for:)` gives the localized text.
    public enum Kind: Sendable, Hashable {
        case network
        case notRegistered
        /// `InvalidInput` with a non-empty reason, shown as is.
        case invalidInput(reason: String)
        /// `InvalidInput` without a reason.
        case invalidInputEmpty
        case notFound
        case crypto
        case storage
        case server
        /// `RetryLater` with status 429: the own hub throttles.
        case serverBusy(retryAfterSecs: UInt64)
        /// `RetryLater` with any other status: a remote hub is unavailable (federation).
        case peerUnavailable(retryAfterSecs: UInt64)
        case cancelled
        case notImplemented
        /// Unknown errors and `Internal`.
        case generic
        case chatLeaving
        case chatLeft
        case hubNotVerified
        case hubOwnsGroups(count: Int)
        case lastHub
        case homeHub
        case hubNotDrained
        /// `UserSuspended`, naming the hub by `host` when known.
        case suspended(host: String?)
        /// `UserNotAdmitted`, naming the hub by `host` when known.
        case notAdmitted(host: String?)
        case notAdmittedByPeer
        /// `UserNotAdmitted` on onboarding and Add Hub: that hub refused the registration.
        case hubRefused
        /// `ContactNotAdmitted`, with the users' names (display name, else short user id); empty when unknown.
        case contactNotAdmitted(names: [String])
    }

    /// `UserSuspended` and `UserNotAdmitted` get the plain wording here and `message(for:client:)` names the hub;
    /// `ContactNotAdmitted` names the users by id (`contactNotAdmittedMessage(userIds:profiles:)` resolves names).
    public static func message(for error: any Error) -> String {
        text(for: kind(for: error))
    }

    /// The kind behind `message(for:)`.
    public static func kind(for error: any Error) -> Kind {
        guard let error = error as? GimError else { return .generic }
        switch error {
        case .Network: return .network
        case .NotRegistered: return .notRegistered
        case .InvalidInput(let reason): return reason.isEmpty ? .invalidInputEmpty : .invalidInput(reason: reason)
        case .NotFound: return .notFound
        case .Crypto: return .crypto
        case .Storage: return .storage
        case .Server: return .server
        case .RetryLater(let status, let retryAfterSecs, _):
            // 429: the own hub throttles; 503: a remote hub is unavailable (federation).
            return status == 429
                ? .serverBusy(retryAfterSecs: retryAfterSecs) : .peerUnavailable(retryAfterSecs: retryAfterSecs)
        case .Cancelled: return .cancelled
        case .NotImplemented: return .notImplemented
        case .Internal: return .generic
        case .ChatNotActive(_, .leaving): return .chatLeaving
        case .ChatNotActive: return .chatLeft
        case .HubNotVerified: return .hubNotVerified
        case .HubOwnsGroups(_, let groupCount): return .hubOwnsGroups(count: Int(groupCount))
        case .LastHub: return .lastHub
        case .HomeHub: return .homeHub
        case .HubNotDrained: return .hubNotDrained
        case .UserSuspended: return .suspended(host: nil)
        case .UserNotAdmitted: return .notAdmitted(host: nil)
        case .NotAdmittedByPeer: return .notAdmittedByPeer
        case .ContactNotAdmitted(let userIds): return contactNotAdmittedKind(userIds: userIds, profiles: [])
        }
    }

    /// Like `message(for:)`, for onboarding (`createIdentity`, `restoreFromRecovery`, `waitLink`) and Add Hub: a hub
    /// that does not admit the user refuses that hub (`hubRefusedMessage`).
    public static func registrationMessage(for error: any Error) -> String {
        text(for: registrationKind(for: error))
    }

    /// The kind behind `registrationMessage(for:)`.
    public static func registrationKind(for error: any Error) -> Kind {
        guard case .UserNotAdmitted = error as? GimError else { return kind(for: error) }
        return .hubRefused
    }

    /// Like `message(for:)`, but `UserSuspended` and `UserNotAdmitted` name the hub when the user has more than one
    /// listed hub, from the client's hubs (only read for those errors).
    @MainActor
    public static func message(for error: any Error, client: any GimClientAPI) async -> String {
        text(for: await kind(for: error, client: client))
    }

    /// The kind behind `message(for:client:)`.
    @MainActor
    public static func kind(for error: any Error, client: any GimClientAPI) async -> Kind {
        switch error as? GimError {
        case .UserSuspended(let hubId)?:
            return suspendedKind(hubId: hubId, hubs: (try? await client.hubs()) ?? [])
        case .UserNotAdmitted(let hubId)?:
            return notAdmittedKind(hubId: hubId, hubs: (try? await client.hubs()) ?? [])
        default:
            return kind(for: error)
        }
    }

    /// The "account suspended" text: names the hub `hubId` by its URL host when more than one hub is listed; the plain
    /// wording for a single hub or an empty or unknown `hubId`.
    public static func suspendedMessage(hubId: String, hubs: [HubInfo]) -> String {
        text(for: suspendedKind(hubId: hubId, hubs: hubs))
    }

    /// The kind behind `suspendedMessage(hubId:hubs:)`.
    public static func suspendedKind(hubId: String, hubs: [HubInfo]) -> Kind {
        .suspended(host: host(of: hubId, in: hubs))
    }

    /// The "account not admitted" text, naming the hub like `suspendedMessage(hubId:hubs:)`.
    public static func notAdmittedMessage(hubId: String, hubs: [HubInfo]) -> String {
        text(for: notAdmittedKind(hubId: hubId, hubs: hubs))
    }

    /// The kind behind `notAdmittedMessage(hubId:hubs:)`.
    public static func notAdmittedKind(hubId: String, hubs: [HubInfo]) -> Kind {
        .notAdmitted(host: host(of: hubId, in: hubs))
    }

    /// Why a failed send is not offered for retry (`SendFailure.userSuspended`, `.userNotAdmitted` or
    /// `.notAdmittedByPeer`); `nil` for causes that can be retried.
    public static func sendFailureMessage(_ cause: SendFailure) -> String? {
        sendFailureKind(cause).map(text(for:))
    }

    /// The kind behind `sendFailureMessage(_:)`.
    public static func sendFailureKind(_ cause: SendFailure) -> Kind? {
        switch cause {
        case .userSuspended: .suspended(host: nil)
        case .userNotAdmitted: .notAdmitted(host: nil)
        case .notAdmittedByPeer: .notAdmittedByPeer
        case .rejected, .other: nil
        }
    }

    /// "<names> doesn't/don't accept messages from you." for `ContactNotAdmitted`: each user is named by the display
    /// name of its profile in `profiles`, else its short user id (`UserLabel.shortUserId`).
    public static func contactNotAdmittedMessage(userIds: [String], profiles: [UserProfile]) -> String {
        text(for: contactNotAdmittedKind(userIds: userIds, profiles: profiles))
    }

    /// The kind behind `contactNotAdmittedMessage(userIds:profiles:)`, with the names resolved.
    public static func contactNotAdmittedKind(userIds: [String], profiles: [UserProfile]) -> Kind {
        .contactNotAdmitted(
            names: userIds.map { userId in
                guard let profile = profiles.first(where: { $0.userId == userId }), !profile.displayName.isEmpty
                else { return UserLabel.shortUserId(userId) }
                return profile.displayName
            })
    }

    /// The localized text of `kind`.
    public static func text(for kind: Kind) -> String {
        switch kind {
        case .network:
            return NSLocalizedString(
                "Can't reach the server. Check your internet and try again.", tableName: "FeaturesCommon",
                bundle: FeaturesLocalization.bundle,
                value: "Can't reach the server. Check your internet and try again.", comment: "")
        case .notRegistered:
            return NSLocalizedString(
                "This device isn't signed in. Sign in again.", tableName: "FeaturesCommon",
                bundle: FeaturesLocalization.bundle, value: "This device isn't signed in. Sign in again.", comment: "")
        case .invalidInput(let reason):
            return reason
        case .invalidInputEmpty:
            return NSLocalizedString(
                "Check what you typed and try again.", tableName: "FeaturesCommon",
                bundle: FeaturesLocalization.bundle, value: "Check what you typed and try again.", comment: "")
        case .notFound:
            return NSLocalizedString(
                "Couldn't find that. It may have been removed.", tableName: "FeaturesCommon",
                bundle: FeaturesLocalization.bundle, value: "Couldn't find that. It may have been removed.",
                comment: "")
        case .crypto:
            return NSLocalizedString(
                "Couldn't unlock this message.", tableName: "FeaturesCommon", bundle: FeaturesLocalization.bundle,
                value: "Couldn't unlock this message.", comment: "")
        case .storage:
            return NSLocalizedString(
                "Couldn't save on this device. Free up some space and try again.", tableName: "FeaturesCommon",
                bundle: FeaturesLocalization.bundle,
                value: "Couldn't save on this device. Free up some space and try again.", comment: "")
        case .server:
            return NSLocalizedString(
                "The server couldn't do that right now. Try again later.", tableName: "FeaturesCommon",
                bundle: FeaturesLocalization.bundle, value: "The server couldn't do that right now. Try again later.",
                comment: "")
        case .serverBusy(let retryAfterSecs):
            let format = NSLocalizedString(
                "The server is busy. Try again in %lld s.", tableName: "FeaturesCommon",
                bundle: FeaturesLocalization.bundle, value: "The server is busy. Try again in %lld s.", comment: "")
            return String(format: format, Int(retryAfterSecs))
        case .peerUnavailable(let retryAfterSecs):
            let format = NSLocalizedString(
                "Another server isn't answering. Try again in %lld s.", tableName: "FeaturesCommon",
                bundle: FeaturesLocalization.bundle, value: "Another server isn't answering. Try again in %lld s.",
                comment: "")
            return String(format: format, Int(retryAfterSecs))
        case .cancelled:
            return NSLocalizedString(
                "That was cancelled.", tableName: "FeaturesCommon", bundle: FeaturesLocalization.bundle,
                value: "That was cancelled.", comment: "")
        case .notImplemented:
            return NSLocalizedString(
                "This isn't available yet.", tableName: "FeaturesCommon", bundle: FeaturesLocalization.bundle,
                value: "This isn't available yet.", comment: "")
        case .generic:
            return NSLocalizedString(
                "Something went wrong. Try again.", tableName: "FeaturesCommon", bundle: FeaturesLocalization.bundle,
                value: "Something went wrong. Try again.", comment: "")
        case .chatLeaving:
            return NSLocalizedString(
                "You're leaving this chat.", tableName: "FeaturesCommon", bundle: FeaturesLocalization.bundle,
                value: "You're leaving this chat.", comment: "")
        case .chatLeft:
            return NSLocalizedString(
                "You're no longer in this chat.", tableName: "FeaturesCommon", bundle: FeaturesLocalization.bundle,
                value: "You're no longer in this chat.", comment: "")
        case .hubNotVerified:
            return NSLocalizedString(
                "Couldn't reach a server at this address. Check the address and try again.",
                tableName: "FeaturesCommon", bundle: FeaturesLocalization.bundle,
                value: "Couldn't reach a server at this address. Check the address and try again.", comment: "")
        case .hubOwnsGroups(let count):
            if count == 1 {
                return NSLocalizedString(
                    "This server hosts 1 group you own.", tableName: "FeaturesCommon",
                    bundle: FeaturesLocalization.bundle, value: "This server hosts 1 group you own.", comment: "")
            }
            let format = NSLocalizedString(
                "This server hosts %lld groups you own.", tableName: "FeaturesCommon",
                bundle: FeaturesLocalization.bundle, value: "This server hosts %lld groups you own.", comment: "")
            return String(format: format, count)
        case .lastHub:
            return NSLocalizedString(
                "This is your only server. Add another server before you remove it.", tableName: "FeaturesCommon",
                bundle: FeaturesLocalization.bundle,
                value: "This is your only server. Add another server before you remove it.", comment: "")
        case .homeHub:
            return NSLocalizedString(
                "Your main server can't be removed. Make another server the main one first.",
                tableName: "FeaturesCommon", bundle: FeaturesLocalization.bundle,
                value: "Your main server can't be removed. Make another server the main one first.", comment: "")
        case .hubNotDrained:
            return NSLocalizedString(
                "Messages sent through this server are still on their way. Try again later.",
                tableName: "FeaturesCommon", bundle: FeaturesLocalization.bundle,
                value: "Messages sent through this server are still on their way. Try again later.", comment: "")
        case .suspended(let host):
            let suspended: String
            if let host {
                let format = NSLocalizedString(
                    "Your account is suspended on %@.", tableName: "FeaturesCommon",
                    bundle: FeaturesLocalization.bundle, value: "Your account is suspended on %@.", comment: "")
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
        case .notAdmitted(let host):
            guard let host else { return text(for: .hubRefused) }
            let format = NSLocalizedString(
                "%@ doesn't accept your account.", tableName: "FeaturesCommon", bundle: FeaturesLocalization.bundle,
                value: "%@ doesn't accept your account.", comment: "")
            return String(format: format, host)
        case .notAdmittedByPeer:
            return NSLocalizedString(
                "This chat's server doesn't accept messages from you.", tableName: "FeaturesCommon",
                bundle: FeaturesLocalization.bundle, value: "This chat's server doesn't accept messages from you.",
                comment: "")
        case .hubRefused:
            return NSLocalizedString(
                "This server doesn't accept your account.", tableName: "FeaturesCommon",
                bundle: FeaturesLocalization.bundle, value: "This server doesn't accept your account.", comment: "")
        case .contactNotAdmitted(let names):
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
            let and = NSLocalizedString(
                "%@ and %@", tableName: "FeaturesCommon", bundle: FeaturesLocalization.bundle, value: "%@ and %@",
                comment: "")
            let list = String(format: and, names.dropLast().joined(separator: ", "), last)
            let format = NSLocalizedString(
                "%@ don't accept messages from you.", tableName: "FeaturesCommon", bundle: FeaturesLocalization.bundle,
                value: "%@ don't accept messages from you.", comment: "")
            return String(format: format, list)
        }
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

    /// `NotAdmittedByPeer`, and sends that failed with `SendFailure.notAdmittedByPeer`.
    public static let notAdmittedByPeerMessage = text(for: .notAdmittedByPeer)
    /// `UserNotAdmitted` on onboarding and Add Hub: that hub refused the registration.
    public static let hubRefusedMessage = text(for: .hubRefused)
}
