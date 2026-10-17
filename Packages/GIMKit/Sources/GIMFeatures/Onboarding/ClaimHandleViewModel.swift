import Foundation
import GIMClientKit
import Observation

/// Claims a handle in the hub directory so others can find the user; skipping is allowed.
@MainActor
@Observable
public final class ClaimHandleViewModel {
    public var handle = ""

    public private(set) var isSubmitting = false
    /// Error from the last failed claim or skip.
    public private(set) var errorMessage: String?
    /// Set by the first claim attempt so an empty field also shows its message.
    public private(set) var showsAllErrors = false

    static let takenMessage = "This handle is taken."

    private let client: any GimClientAPI
    private let onFinished: @MainActor () async throws -> Void

    /// - Parameter onFinished: runs after a successful claim or a skip; its error is shown and the step stays.
    public init(client: any GimClientAPI, onFinished: @escaping @MainActor () async throws -> Void) {
        self.client = client
        self.onFinished = onFinished
    }

    /// Inline message for the handle field; `nil` while the field is untouched.
    public var handleError: String? {
        let error = OnboardingValidation.handleError(handle)
        return showsAllErrors || !handle.isEmpty ? error : nil
    }

    public var canClaim: Bool { OnboardingValidation.handleError(handle) == nil && !isSubmitting }

    public func claim() async {
        showsAllErrors = true
        guard canClaim else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await client.claimHandle(handle: OnboardingValidation.normalizedHandle(handle))
        } catch GimError.Server(status: 409, reason: _) {
            errorMessage = Self.takenMessage
            return
        } catch {
            errorMessage = await ErrorPresenter.message(for: error, client: client)
            return
        }
        await finish()
    }

    /// Continues without a handle.
    public func skip() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        await finish()
    }

    private func finish() async {
        do {
            try await onFinished()
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }
}
