import Foundation
import Observation

/// Deletes the account after the user typed the confirmation word.
@MainActor
@Observable
public final class DeleteAccountViewModel {
    /// The localized word the user has to type, e.g. "DELETE".
    public let confirmationWord: String
    public var typedConfirmation = ""
    public private(set) var isDeleting = false
    /// Error from the last failed deletion, as returned by the delete action.
    public private(set) var errorMessage: String?

    private let deleteAccount: @MainActor () async -> String?

    /// - Parameter deleteAccount: deletes the account and returns the error text when it fails, e.g.
    ///   `AppModel.deleteAccount`.
    public init(confirmationWord: String, deleteAccount: @escaping @MainActor () async -> String?) {
        self.confirmationWord = confirmationWord
        self.deleteAccount = deleteAccount
    }

    /// The typed text is the confirmation word, ignoring surrounding whitespace and case.
    public var canConfirm: Bool {
        let typed = typedConfirmation.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed.caseInsensitiveCompare(confirmationWord) == .orderedSame
    }

    public func confirm() async {
        guard canConfirm, !isDeleting else { return }
        isDeleting = true
        errorMessage = await deleteAccount()
        isDeleting = false
    }
}
