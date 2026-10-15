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

    /// The initial server field value: the first of the last used server, the launch argument and the bundled
    /// default that is a valid server URL, normalised; empty when none is.
    public static func defaultServerUrl(stored: String?, argument: String?, bundled: String?) -> String {
        for candidate in [stored, argument, bundled] {
            if let candidate, serverUrlError(candidate) == nil { return normalizedServerUrl(candidate) }
        }
        return ""
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

/// The outcome of a successful registration: the client created for the typed server URL and its new session.
public struct Registration: Sendable {
    public let client: any GimClientAPI
    public let config: ClientConfig
    public let session: Session

    public init(client: any GimClientAPI, config: ClientConfig, session: Session) {
        self.client = client
        self.config = config
        self.session = session
    }
}

/// Drives the registration form: validates input, creates the client for the typed server URL (the URL is part of
/// `ClientConfig`), registers this device and reports the result.
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

    private let factory: any GimClientFactory
    private let hooks: any PlatformHooks
    private let onRegistered: @MainActor (Registration) -> Void
    @ObservationIgnored private var client: (any GimClientAPI)?
    @ObservationIgnored private var clientConfig: ClientConfig?

    /// - Parameters:
    ///   - serverUrl: initial value of the server field.
    ///   - client: an unregistered client already created for `serverUrl`; reused while the URL is unchanged.
    public init(
        factory: any GimClientFactory,
        hooks: any PlatformHooks,
        serverUrl: String = "",
        client: (any GimClientAPI)? = nil,
        onRegistered: @escaping @MainActor (Registration) -> Void
    ) {
        self.factory = factory
        self.hooks = hooks
        self.serverUrl = serverUrl
        self.onRegistered = onRegistered
        if let client {
            self.client = client
            clientConfig = ClientConfig(serverUrl: OnboardingValidation.normalizedServerUrl(serverUrl))
        }
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
        let config = ClientConfig(serverUrl: OnboardingValidation.normalizedServerUrl(serverUrl))
        do {
            let client = try await client(for: config)
            let session = try await client.register(
                handle: OnboardingValidation.normalizedHandle(handle),
                displayName: OnboardingValidation.normalizedDisplayName(displayName))
            onRegistered(Registration(client: client, config: config, session: session))
        } catch {
            errorMessage = ErrorPresenter.message(for: error)
        }
    }

    /// The client for `config`, created through the factory when the server URL changed.
    private func client(for config: ClientConfig) async throws -> any GimClientAPI {
        if let client, clientConfig == config { return client }
        // Release the old client first: both would use the same data directory.
        client = nil
        clientConfig = nil
        let client = try await factory.make(config: config, hooks: hooks)
        self.client = client
        clientConfig = config
        return client
    }

    private func visible(_ error: String?, for value: String) -> String? {
        showsAllErrors || !value.isEmpty ? error : nil
    }
}
