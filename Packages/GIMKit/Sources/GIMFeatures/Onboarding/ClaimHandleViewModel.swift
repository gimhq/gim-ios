import Foundation
import GIMClientKit
import Observation

/// Claims a handle in the hub directory so others can find the user; skipping is allowed.
@MainActor
@Observable
public final class ClaimHandleViewModel {
    /// An error of a claim or skip; `text` gives the localized message.
    public enum ErrorKind: Sendable, Hashable {
        /// Another user holds the handle.
        case taken
        /// An error forwarded from gim-core or from finishing the step.
        case error(ErrorPresenter.Kind)

        /// The localized message.
        public var text: String {
            switch self {
            case .taken: onboardingText("Someone already has this username. Try another one.")
            case .error(let kind): ErrorPresenter.text(for: kind)
            }
        }
    }

    public var handle = ""

    public private(set) var isSubmitting = false
    /// Error from the last failed claim or skip.
    public var errorMessage: String? { errorKind?.text }
    /// The kind behind `errorMessage`.
    public private(set) var errorKind: ErrorKind?
    /// Set by the first claim attempt so an empty field also shows its message.
    public private(set) var showsAllErrors = false

    public static let takenMessage = ErrorKind.taken.text

    private let client: any GimClientAPI
    private let onFinished: @MainActor () async throws -> Void

    /// - Parameter onFinished: runs after a successful claim or a skip; its error is shown and the step stays.
    public init(client: any GimClientAPI, onFinished: @escaping @MainActor () async throws -> Void) {
        self.client = client
        self.onFinished = onFinished
    }

    /// Inline message for the handle field; `nil` while the field is untouched.
    public var handleError: String? {
        handleErrorKind?.text
    }

    /// The kind behind `handleError`.
    public var handleErrorKind: OnboardingValidation.HandleError? {
        let error = OnboardingValidation.handleErrorKind(handle)
        return showsAllErrors || !handle.isEmpty ? error : nil
    }

    public var canClaim: Bool { OnboardingValidation.handleError(handle) == nil && !isSubmitting }

    public func claim() async {
        showsAllErrors = true
        guard canClaim else { return }
        isSubmitting = true
        errorKind = nil
        defer { isSubmitting = false }
        do {
            try await client.claimHandle(handle: OnboardingValidation.normalizedHandle(handle))
        } catch GimError.Server(status: 409, reason: _) {
            errorKind = .taken
            return
        } catch {
            errorKind = .error(await ErrorPresenter.kind(for: error, client: client))
            return
        }
        await finish()
    }

    /// Continues without a handle.
    public func skip() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        errorKind = nil
        defer { isSubmitting = false }
        await finish()
    }

    private func finish() async {
        do {
            try await onFinished()
        } catch {
            errorKind = .error(ErrorPresenter.kind(for: error))
        }
    }
}
