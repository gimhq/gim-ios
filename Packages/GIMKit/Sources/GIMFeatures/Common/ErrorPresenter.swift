import Foundation
import GIMClientKit

/// Maps errors to user-facing text.
public enum ErrorPresenter {
    /// `UserSuspended` gets the plain wording here; `message(for:client:)` names the hub.
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
        }
    }

    /// Like `message(for:)`, but `UserSuspended` names the hub when the user has more than one listed hub, from the
    /// client's hubs (only read for that error).
    @MainActor
    public static func message(for error: any Error, client: any GimClientAPI) async -> String {
        guard case .UserSuspended(let hubId) = error as? GimError else { return message(for: error) }
        return suspendedMessage(hubId: hubId, hubs: (try? await client.hubs()) ?? [])
    }

    /// The "account suspended" text: names the hub `hubId` by its URL host when more than one hub is listed; the plain
    /// wording for a single hub or an empty or unknown `hubId`.
    public static func suspendedMessage(hubId: String, hubs: [HubInfo]) -> String {
        let listed = hubs.filter { $0.state != .removed }
        guard listed.count > 1, !hubId.isEmpty, let url = listed.first(where: { $0.hubId == hubId })?.url,
            let host = URLComponents(string: url)?.host, !host.isEmpty
        else { return suspendedMessage(host: nil) }
        return suspendedMessage(host: host.lowercased())
    }

    /// The hub id of a `SendState.failed` reason that gim-core records when the hub refused the send because the user
    /// is suspended there (`user suspended on hub <hub id>`, the id may be empty); `nil` for any other reason. Such a
    /// send is not offered for retry.
    public static func suspendedHubId(failureReason reason: String) -> String? {
        guard reason.hasPrefix(suspendedReasonPrefix) else { return nil }
        return String(reason.dropFirst(suspendedReasonPrefix.count)).trimmingCharacters(in: .whitespaces)
    }

    static func suspendedMessage(host: String?) -> String {
        let suspended = host.map { "Your account is suspended on \($0)." } ?? "Your account is suspended."
        return suspended + " Your chats on this device stay readable. Contact the hub's operator to restore access."
    }

    static let genericMessage = "Something went wrong. Please try again."
    /// gim-core's text of `UserSuspended`, which a failed send keeps as its reason.
    static let suspendedReasonPrefix = "user suspended on hub"
}
