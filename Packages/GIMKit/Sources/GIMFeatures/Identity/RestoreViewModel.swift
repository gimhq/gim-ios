import Foundation
import GIMClientKit
import Observation

/// Restores the user on this device from the recovery code with the onboarding's client. After success it shows
/// that chats are not rejoined automatically; dismissing that notice signs in.
@MainActor
@Observable
public final class RestoreViewModel {
    public var userId = ""
    public var recoveryCode = ""
    /// Revokes every previously listed device of the user.
    public var revokeOthers = true

    public private(set) var isSubmitting = false
    /// Error from the last failed submission.
    public private(set) var errorMessage: String?
    /// Set by the first submit attempt so empty fields also show their messages.
    public private(set) var showsAllErrors = false
    /// Whether the restore succeeded and the notice about chats waits to be dismissed with `finish()`.
    public var showsRejoinNotice: Bool { registration != nil }

    static let notFoundMessage = "No identity with this user ID."
    static let wrongCodeMessage = "This recovery code doesn't match this user ID."

    private let context: OnboardingContext
    private var registration: Registration?

    public init(context: OnboardingContext) {
        self.context = context
    }

    /// Inline message for the user id field; `nil` while the field is untouched.
    public var userIdError: String? {
        guard showsAllErrors || !userId.isEmpty else { return nil }
        return Self.normalized(userId).isEmpty ? "Enter your user ID." : nil
    }

    /// Inline message for the recovery code field; `nil` while the field is untouched. gim-core validates the format.
    public var recoveryCodeError: String? {
        guard showsAllErrors || !recoveryCode.isEmpty else { return nil }
        return Self.normalized(recoveryCode).isEmpty ? "Enter your recovery code." : nil
    }

    public var canSubmit: Bool {
        !Self.normalized(userId).isEmpty && !Self.normalized(recoveryCode).isEmpty && !isSubmitting
            && registration == nil
    }

    public func submit() async {
        showsAllErrors = true
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            let client = try await context.client()
            // A retry after the restore itself succeeded: the client already has the identity.
            if client.userId() == nil {
                try await client.restoreFromRecovery(
                    userId: Self.normalized(userId), recoveryCode: Self.normalized(recoveryCode),
                    revokeOthers: revokeOthers)
            }
            guard let session = try await client.session() else { throw GimError.NotRegistered }
            recoveryCode = ""
            registration = Registration(client: client, config: context.config, session: session)
        } catch GimError.NotFound {
            errorMessage = Self.notFoundMessage
        } catch GimError.Crypto {
            errorMessage = Self.wrongCodeMessage
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// Signs in after the notice about chats was shown.
    public func finish() {
        guard let registration else { return }
        self.registration = nil
        context.onRegistered(registration)
    }

    /// Trims whitespace; gim-core's parser ignores case, `-` and whitespace inside the recovery code.
    static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
