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
        case .Cancelled:
            return "The operation was cancelled."
        case .NotImplemented:
            return "This isn't available in this version yet."
        case .Internal:
            return genericMessage
        }
    }

    static let genericMessage = "Something went wrong. Please try again."
}
