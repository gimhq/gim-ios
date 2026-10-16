import GIMClientKit

/// Maps errors to user-facing text.
public enum ErrorPresenter {
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
        }
    }

    static let genericMessage = "Something went wrong. Please try again."
}
