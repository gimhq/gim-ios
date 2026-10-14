import GIMClientKit

/// Maps errors to user-facing text.
public enum ErrorPresenter {
    public static func message(for error: any Error) -> String {
        guard let error = error as? GimError else { return genericMessage }
        switch error {
        case .unauthorized:
            return "Your session has expired. Please register this device again."
        case .notFound:
            return "We couldn't find what you were looking for."
        case .network:
            return "Can't reach the server. Check your connection and try again."
        case .invalidInput(let reason):
            return reason.isEmpty ? "Please check what you entered and try again." : reason
        case .internal:
            return genericMessage
        }
    }

    static let genericMessage = "Something went wrong. Please try again."
}
