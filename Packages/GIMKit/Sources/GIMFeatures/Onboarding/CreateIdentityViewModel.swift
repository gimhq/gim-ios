import Foundation
import GIMClientKit
import Observation

/// The display name form of the create flow: creates the client for the chosen server and a new identity on it.
@MainActor
@Observable
public final class CreateIdentityViewModel {
    public var displayName = ""

    public private(set) var isSubmitting = false
    /// Error from the last failed submission.
    public private(set) var errorMessage: String?
    /// Set by the first submit attempt so an empty field also shows its message.
    public private(set) var showsAllErrors = false

    private let context: OnboardingContext
    private let onCreated: @MainActor (any GimClientAPI, String?) -> Void

    /// - Parameter onCreated: receives the client and the recovery code of the call that succeeded. A failed
    ///   `createIdentity` keeps nothing, so a retry creates a new user with a new code on the same client.
    public init(
        context: OnboardingContext,
        onCreated: @escaping @MainActor (_ client: any GimClientAPI, _ recoveryCode: String?) -> Void
    ) {
        self.context = context
        self.onCreated = onCreated
    }

    /// Inline message for the display name field; `nil` while the field is untouched.
    public var displayNameError: String? {
        let error = OnboardingValidation.displayNameError(displayName)
        return showsAllErrors || !displayName.isEmpty ? error : nil
    }

    public var canSubmit: Bool { OnboardingValidation.displayNameError(displayName) == nil && !isSubmitting }

    public func submit() async {
        showsAllErrors = true
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            let client = try await context.client()
            let recoveryCode = try await client.createIdentity(
                displayName: OnboardingValidation.normalizedDisplayName(displayName))
            onCreated(client, recoveryCode)
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }
}
