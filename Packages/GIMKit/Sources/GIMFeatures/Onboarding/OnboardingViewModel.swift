import Foundation
import GIMClientKit
import Observation

/// Pure validation and normalisation rules for the registration form.
public enum OnboardingValidation {
    public static let displayNameMaxLength = 64

    /// Trims whitespace and drops trailing slashes.
    public static func normalizedServerUrl(_ raw: String) -> String {
        var url = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while url.hasSuffix("/") { url.removeLast() }
        return url
    }

    public static func normalizedHandle(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func normalizedDisplayName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns an error message, or `nil` when the normalised URL is an http(s) URL with a host.
    public static func serverUrlError(_ raw: String) -> String? {
        let url = normalizedServerUrl(raw)
        if url.isEmpty { return "Enter the server address." }
        guard let components = URLComponents(string: url),
            let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = components.host, !host.isEmpty
        else {
            return "Enter a full address starting with http:// or https://."
        }
        return nil
    }

    /// Returns an error message, or `nil` when the normalised handle matches `^[a-z0-9_.]{3,32}$`.
    public static func handleError(_ raw: String) -> String? {
        let handle = normalizedHandle(raw)
        if handle.isEmpty { return "Choose a handle." }
        guard (3...32).contains(handle.count) else { return "Handles are 3 to 32 characters long." }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_.")
        guard handle.allSatisfy(allowed.contains) else {
            return "Use only letters, digits, underscores and dots."
        }
        return nil
    }

    /// Returns an error message, or `nil` when the trimmed name is 1 to 64 characters long.
    public static func displayNameError(_ raw: String) -> String? {
        let name = normalizedDisplayName(raw)
        if name.isEmpty { return "Enter your name." }
        guard name.count <= displayNameMaxLength else {
            return "Names can be at most \(displayNameMaxLength) characters long."
        }
        return nil
    }
}

/// Drives the registration form: validates input, registers this device and reports the new session.
@MainActor
@Observable
public final class OnboardingViewModel {
    public var serverUrl: String
    public var handle = ""
    public var displayName = ""

    public private(set) var isSubmitting = false
    /// Error from the last failed submission.
    public private(set) var errorMessage: String?
    /// Set by the first submit attempt so empty fields also show their messages.
    public private(set) var showsAllErrors = false

    private let client: any GimClientAPI
    private let onRegistered: @MainActor (Session) -> Void

    public init(
        client: any GimClientAPI,
        serverUrl: String = "",
        onRegistered: @escaping @MainActor (Session) -> Void
    ) {
        self.client = client
        self.serverUrl = serverUrl
        self.onRegistered = onRegistered
    }

    /// Inline message for the server URL field; `nil` while the field is untouched.
    public var serverUrlError: String? {
        visible(OnboardingValidation.serverUrlError(serverUrl), for: serverUrl)
    }

    public var handleError: String? {
        visible(OnboardingValidation.handleError(handle), for: handle)
    }

    public var displayNameError: String? {
        visible(OnboardingValidation.displayNameError(displayName), for: displayName)
    }

    public var isValid: Bool {
        OnboardingValidation.serverUrlError(serverUrl) == nil
            && OnboardingValidation.handleError(handle) == nil
            && OnboardingValidation.displayNameError(displayName) == nil
    }

    public var canSubmit: Bool { isValid && !isSubmitting }

    public func submit() async {
        showsAllErrors = true
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            let session = try await client.register(
                serverUrl: OnboardingValidation.normalizedServerUrl(serverUrl),
                handle: OnboardingValidation.normalizedHandle(handle),
                displayName: OnboardingValidation.normalizedDisplayName(displayName))
            onRegistered(session)
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    private func visible(_ error: String?, for value: String) -> String? {
        showsAllErrors || !value.isEmpty ? error : nil
    }
}
