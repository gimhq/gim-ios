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
            return "Can't reach the server. Check your connection and try again."
        case .NotRegistered:
            return "This device isn't signed in. Please register again."
        case .InvalidInput(let reason):
            return reason.isEmpty ? "Please check what you entered and try again." : reason
        case .NotFound:
            return "We couldn't find what you were looking for."
        case .Crypto:
            return "This content couldn't be decrypted."
        case .Storage:
            return "Couldn't save data on this device. Check the free storage and try again."
        case .Server(let status, _):
            return "The server couldn't complete the request (error \(status)). Please try again later."
        case .RetryLater(let status, let retryAfterSecs, _):
            // 429: the own hub throttles; 503: a remote hub is unavailable (federation).
            let cause = status == 429 ? "The server is busy." : "Another server is unavailable."
            return "\(cause) Try again in \(retryAfterSecs) s."
        case .Cancelled:
            return "The operation was cancelled."
        case .NotImplemented:
            return "This isn't available in this version yet."
        case .Internal:
            return genericMessage
        case .ChatNotActive(_, .leaving):
            return "You're leaving this chat."
        case .ChatNotActive:
            return "You're no longer a member of this chat."
        case .HubNotVerified:
            return "This hub couldn't prove it is reachable at this address. Check the address and try again."
        case .HubOwnsGroups(_, let groupCount):
            return groupCount == 1 ? "This hub hosts 1 group you own." : "This hub hosts \(groupCount) groups you own."
        case .LastHub:
            return "This is your only hub. Add another hub before removing it."
        case .HomeHub:
            return "This device's home hub can't be removed. Make another hub primary instead."
        case .HubNotDrained:
            return "Messages sent through this hub are still on their way. Try again later."
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

    /// "<names> does/do not accept contacts from you." for `ContactNotAdmitted`: each user is named by the display name
    /// of its profile in `profiles`, else its handle, else its user id.
    public static func contactNotAdmittedMessage(userIds: [String], profiles: [UserProfile]) -> String {
        let names = userIds.map { userId in
            guard let profile = profiles.first(where: { $0.userId == userId }) else { return userId }
            if !profile.displayName.isEmpty { return profile.displayName }
            return profile.handle.isEmpty ? userId : "@\(profile.handle)"
        }
        guard let last = names.last else { return "This user does not accept contacts from you." }
        let list = names.count == 1 ? last : names.dropLast().joined(separator: ", ") + " and " + last
        return list + (names.count == 1 ? " does" : " do") + " not accept contacts from you."
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
        let suspended = host.map { "Your account is suspended on \($0)." } ?? "Your account is suspended."
        return suspended + " Your chats on this device stay readable. Contact the hub's operator to restore access."
    }

    static func notAdmittedMessage(host: String?) -> String {
        "Your account is not admitted on \(host ?? "this hub")."
    }

    static let genericMessage = "Something went wrong. Please try again."
    /// `NotAdmittedByPeer`, and sends that failed with `SendFailure.notAdmittedByPeer`.
    public static let notAdmittedByPeerMessage = "This chat's hub does not accept messages from you."
    /// `UserNotAdmitted` on onboarding and Add Hub: that hub refused the registration.
    public static let hubRefusedMessage = "This hub does not admit your account."
}
