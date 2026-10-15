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

/// A screen pushed from the onboarding start screen.
public enum OnboardingRoute: Sendable, Hashable {
    case createIdentity
    case linkDevice
    case restore
}

/// What the create, link and restore flows need: the server chosen on the start screen, its client and the
/// completion that hands the signed-in client to the app.
@MainActor
public struct OnboardingContext {
    public let config: ClientConfig
    /// The client for `config`: created through the factory on first use and reused afterwards.
    public let client: @MainActor () async throws -> any GimClientAPI
    /// Drops the client after it wiped itself (e.g. a rejected device link); the next `client()` creates a new one.
    public let discardClient: @MainActor () -> Void
    /// Signs in with a client that has a session.
    public let onRegistered: @MainActor (Registration) -> Void

    public init(
        config: ClientConfig,
        client: @escaping @MainActor () async throws -> any GimClientAPI,
        discardClient: @escaping @MainActor () -> Void,
        onRegistered: @escaping @MainActor (Registration) -> Void
    ) {
        self.config = config
        self.client = client
        self.discardClient = discardClient
        self.onRegistered = onRegistered
    }
}

/// The steps after `createIdentity` succeeded; there is no way back to the start screen from here.
@MainActor
public enum IdentityStage {
    case recoveryCode(RecoveryCodeViewModel)
    case claimHandle(ClaimHandleViewModel)
}

/// Drives onboarding: the server address, the choice between creating, linking and restoring an identity, and the
/// create flow (display name, recovery code, optional handle). Creates the client for the typed server URL (the URL
/// is part of `ClientConfig`) and reports the signed-in client.
@MainActor
@Observable
public final class OnboardingViewModel {
    public var serverUrl: String
    /// Screens pushed on the start screen.
    public var path: [OnboardingRoute] = []
    /// Shown on the start screen until dismissed when opening the client discarded the local database.
    public private(set) var showsLocalStateResetNotice: Bool
    /// The server, client and completion for the pushed screens; set by `choose(_:)`.
    public private(set) var context: OnboardingContext?
    /// The display name form of the create flow; set by `choose(.createIdentity)`.
    public private(set) var createIdentity: CreateIdentityViewModel?
    /// Replaces the start screen once the identity exists.
    public private(set) var stage: IdentityStage?
    /// Set by the first `choose(_:)` so an empty server field also shows its message.
    public private(set) var showsAllErrors = false

    private let factory: any GimClientFactory
    private let hooks: any PlatformHooks
    private let onRegistered: @MainActor (Registration) -> Void
    private let chooseGroup: @MainActor (Int) -> Int
    @ObservationIgnored private var client: (any GimClientAPI)?
    @ObservationIgnored private var clientConfig: ClientConfig?

    /// - Parameters:
    ///   - serverUrl: initial value of the server field.
    ///   - client: a client without a session already created for `serverUrl`; reused while the URL is unchanged.
    ///   - localStateReset: whether `client` discarded the local database when it was opened.
    ///   - chooseGroup: picks the recovery code group to re-enter, given the number of groups.
    public init(
        factory: any GimClientFactory,
        hooks: any PlatformHooks,
        serverUrl: String = "",
        client: (any GimClientAPI)? = nil,
        localStateReset: Bool = false,
        chooseGroup: @escaping @MainActor (Int) -> Int = { Int.random(in: 0..<$0) },
        onRegistered: @escaping @MainActor (Registration) -> Void
    ) {
        self.factory = factory
        self.hooks = hooks
        self.serverUrl = serverUrl
        self.chooseGroup = chooseGroup
        self.onRegistered = onRegistered
        showsLocalStateResetNotice = localStateReset
        if let client {
            self.client = client
            clientConfig = ClientConfig(serverUrl: OnboardingValidation.normalizedServerUrl(serverUrl))
        }
    }

    /// Inline message for the server URL field; `nil` while the field is untouched.
    public var serverUrlError: String? {
        let error = OnboardingValidation.serverUrlError(serverUrl)
        return showsAllErrors || !serverUrl.isEmpty ? error : nil
    }

    public func dismissLocalStateResetNotice() {
        showsLocalStateResetNotice = false
    }

    /// Opens `route` for the typed server; does nothing while the server URL is invalid.
    public func choose(_ route: OnboardingRoute) {
        showsAllErrors = true
        guard OnboardingValidation.serverUrlError(serverUrl) == nil else { return }
        let config = ClientConfig(serverUrl: OnboardingValidation.normalizedServerUrl(serverUrl))
        let context = OnboardingContext(
            config: config,
            client: { [weak self] in
                guard let self else { throw GimError.Cancelled }
                return try await self.client(for: config)
            },
            discardClient: { [weak self] in
                self?.client = nil
                self?.clientConfig = nil
            },
            onRegistered: { [weak self] in self?.onRegistered($0) })
        self.context = context
        createIdentity =
            route == .createIdentity
            ? CreateIdentityViewModel(context: context) { [weak self] client, recoveryCode in
                self?.identityCreated(client: client, context: context, recoveryCode: recoveryCode)
            } : nil
        path = [route]
    }

    private func identityCreated(client: any GimClientAPI, context: OnboardingContext, recoveryCode: String?) {
        let claimHandle = ClaimHandleViewModel(client: client) {
            guard let session = try await client.session() else { throw GimError.NotRegistered }
            context.onRegistered(Registration(client: client, config: context.config, session: session))
        }
        guard let recoveryCode else {
            stage = .claimHandle(claimHandle)
            return
        }
        stage = .recoveryCode(
            RecoveryCodeViewModel(code: recoveryCode, chooseGroup: chooseGroup) { [weak self] in
                self?.stage = .claimHandle(claimHandle)
            })
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
}
