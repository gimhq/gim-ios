import Foundation
import GIMClientKit
import Observation

/// Adds a hub by the URL the user enters (`addHub`). gim-core lists it unverified until the hub proved it is at that
/// URL; the hub list then shows it verified and signed in.
@MainActor
@Observable
public final class AddHubViewModel {
    public var url = ""

    public private(set) var isSubmitting = false
    /// Error from the last failed attempt: `InvalidInput`, `Network`, `HubNotVerified`, `UserNotAdmitted`, …
    public private(set) var errorMessage: String?
    /// The hub once added; the screen should close.
    public private(set) var addedHub: HubInfo?

    private let client: any GimClientAPI

    public init(client: any GimClientAPI) {
        self.client = client
    }

    /// Inline message for the URL field (the server URL rule of onboarding); `nil` while the field is empty.
    public var urlError: String? {
        url.isEmpty ? nil : OnboardingValidation.serverUrlError(url)
    }

    public var canSubmit: Bool { OnboardingValidation.serverUrlError(url) == nil && !isSubmitting }

    public func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            addedHub = try await client.addHub(url: OnboardingValidation.normalizedServerUrl(url))
        } catch GimError.UserNotAdmitted {
            // The hub refused this user and was not listed.
            errorMessage = ErrorPresenter.hubRefusedMessage
        } catch {
            errorMessage = await ErrorPresenter.message(for: error, client: client)
        }
    }
}
