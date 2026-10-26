import Foundation
import GIMClientKit
import Observation

/// A message of the `FeaturesOnboarding` table; `key` is the English text.
func onboardingText(_ key: String) -> String {
    NSLocalizedString(
        key, tableName: "FeaturesOnboarding", bundle: FeaturesLocalization.bundle, value: key, comment: "")
}

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

    /// Why a server URL is not accepted; `text` gives the localized message.
    public enum ServerUrlError: Sendable, Hashable {
        case empty
        /// Not an http(s) URL with a host.
        case notAFullAddress

        /// The localized message.
        public var text: String {
            switch self {
            case .empty: onboardingText("Enter the server address.")
            case .notAFullAddress: onboardingText("Enter a full address, like https://example.com")
            }
        }
    }

    /// Why a handle is not accepted; `text` gives the localized message.
    public enum HandleError: Sendable, Hashable {
        case empty
        /// Not 3 to 32 characters long.
        case length
        /// Contains a character other than `a-z`, `0-9`, `_` and `.`.
        case characters

        /// The localized message.
        public var text: String {
            switch self {
            case .empty: onboardingText("Choose a username.")
            case .length: onboardingText("Usernames are 3 to 32 characters long.")
            case .characters: onboardingText("Use only letters, digits, underscores and dots.")
            }
        }
    }

    /// Why a display name is not accepted; `text` gives the localized message.
    public enum DisplayNameError: Sendable, Hashable {
        case empty
        /// Longer than `displayNameMaxLength`.
        case tooLong

        /// The localized message.
        public var text: String {
            switch self {
            case .empty: onboardingText("Enter your name.")
            case .tooLong: onboardingText("Your name can be 1 to 64 characters long.")
            }
        }
    }

    /// Returns an error message, or `nil` when the normalised URL is an http(s) URL with a host.
    public static func serverUrlError(_ raw: String) -> String? {
        serverUrlErrorKind(raw)?.text
    }

    /// The kind behind `serverUrlError(_:)`.
    public static func serverUrlErrorKind(_ raw: String) -> ServerUrlError? {
        let url = normalizedServerUrl(raw)
        if url.isEmpty { return .empty }
        guard let components = URLComponents(string: url),
            let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = components.host, !host.isEmpty
        else {
            return .notAFullAddress
        }
        return nil
    }

    /// The production hub: the last fallback of `defaultServerUrl`, only pre-filled, never probed.
    public static let builtInServerUrl = "https://hub.g.im"

    /// The initial server field value: the first of the last used server, the launch argument and the bundled
    /// default that is a valid server URL, normalised; `builtInServerUrl` when none is.
    public static func defaultServerUrl(stored: String?, argument: String?, bundled: String?) -> String {
        for candidate in [stored, argument, bundled] {
            if let candidate, serverUrlError(candidate) == nil { return normalizedServerUrl(candidate) }
        }
        return builtInServerUrl
    }

    /// Returns an error message, or `nil` when the normalised handle matches `^[a-z0-9_.]{3,32}$`.
    public static func handleError(_ raw: String) -> String? {
        handleErrorKind(raw)?.text
    }

    /// The kind behind `handleError(_:)`.
    public static func handleErrorKind(_ raw: String) -> HandleError? {
        let handle = normalizedHandle(raw)
        if handle.isEmpty { return .empty }
        guard (3...32).contains(handle.count) else { return .length }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789_.")
        guard handle.allSatisfy(allowed.contains) else { return .characters }
        return nil
    }

    /// Returns an error message, or `nil` when the trimmed name is 1 to 64 characters long.
    public static func displayNameError(_ raw: String) -> String? {
        displayNameErrorKind(raw)?.text
    }

    /// The kind behind `displayNameError(_:)`.
    public static func displayNameErrorKind(_ raw: String) -> DisplayNameError? {
        let name = normalizedDisplayName(raw)
        if name.isEmpty { return .empty }
        guard name.count <= displayNameMaxLength else { return .tooLong }
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
    /// Formats, parses and checks the recovery kit.
    public let recoveryKit: any RecoveryKitFunctions
    /// Signs in with a client that has a session.
    public let onRegistered: @MainActor (Registration) -> Void

    public init(
        config: ClientConfig,
        client: @escaping @MainActor () async throws -> any GimClientAPI,
        discardClient: @escaping @MainActor () -> Void,
        recoveryKit: any RecoveryKitFunctions,
        onRegistered: @escaping @MainActor (Registration) -> Void
    ) {
        self.config = config
        self.client = client
        self.discardClient = discardClient
        self.recoveryKit = recoveryKit
        self.onRegistered = onRegistered
    }
}

/// The steps after `createIdentity` succeeded; there is no way back to the start screen from here.
@MainActor
public enum IdentityStage {
    case recoveryKit(RecoveryKitViewModel)
    case claimHandle(ClaimHandleViewModel)
}

/// Drives onboarding: the server address, the choice between creating, linking and restoring an identity, and the
/// create flow (display name, recovery kit, optional handle). Creates the client for the typed server URL (the URL
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
    /// Whether the server field is shown; hidden while the initial server URL is valid until revealed.
    public private(set) var showsServerField: Bool

    private let factory: any GimClientFactory
    private let hooks: any PlatformHooks
    private let recoveryKit: any RecoveryKitFunctions
    private let keepServerUrl: String?
    private let onRegistered: @MainActor (Registration) -> Void
    @ObservationIgnored private var client: (any GimClientAPI)?
    @ObservationIgnored private var clientConfig: ClientConfig?

    /// - Parameters:
    ///   - recoveryKit: formats, parses and checks the recovery kit for the create and restore flows.
    ///   - serverUrl: initial value of the server field.
    ///   - client: a client without a session already created for `serverUrl`; reused while the URL is unchanged.
    ///   - localStateReset: whether `client` discarded the local database when it was opened.
    ///   - keepServerUrl: `ClientConfig.keepServerUrl` of the clients it creates (`KeepServer.resolvedUrl`).
    public init(
        factory: any GimClientFactory,
        hooks: any PlatformHooks,
        recoveryKit: any RecoveryKitFunctions,
        serverUrl: String = "",
        client: (any GimClientAPI)? = nil,
        localStateReset: Bool = false,
        keepServerUrl: String? = nil,
        onRegistered: @escaping @MainActor (Registration) -> Void
    ) {
        self.factory = factory
        self.hooks = hooks
        self.recoveryKit = recoveryKit
        self.keepServerUrl = keepServerUrl
        self.serverUrl = serverUrl
        self.onRegistered = onRegistered
        showsLocalStateResetNotice = localStateReset
        showsServerField = OnboardingValidation.serverUrlError(serverUrl) != nil
        if let client {
            self.client = client
            clientConfig = ClientConfig(
                serverUrl: OnboardingValidation.normalizedServerUrl(serverUrl), keepServerUrl: keepServerUrl)
        }
    }

    /// Inline message for the server URL field; `nil` while the field is untouched.
    public var serverUrlError: String? {
        serverUrlErrorKind?.text
    }

    /// The kind behind `serverUrlError`.
    public var serverUrlErrorKind: OnboardingValidation.ServerUrlError? {
        let error = OnboardingValidation.serverUrlErrorKind(serverUrl)
        return showsAllErrors || !serverUrl.isEmpty ? error : nil
    }

    public func dismissLocalStateResetNotice() {
        showsLocalStateResetNotice = false
    }

    public func revealServerField() {
        showsServerField = true
    }

    /// Opens `route` for the typed server; while the server URL is invalid it only reveals the server field.
    public func choose(_ route: OnboardingRoute) {
        showsAllErrors = true
        guard OnboardingValidation.serverUrlError(serverUrl) == nil else {
            showsServerField = true
            return
        }
        let config = ClientConfig(
            serverUrl: OnboardingValidation.normalizedServerUrl(serverUrl), keepServerUrl: keepServerUrl)
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
            recoveryKit: recoveryKit,
            onRegistered: { [weak self] in self?.onRegistered($0) })
        self.context = context
        createIdentity =
            route == .createIdentity
            ? CreateIdentityViewModel(context: context) { [weak self] client, userId, recoveryCode in
                self?.identityCreated(client: client, context: context, userId: userId, recoveryCode: recoveryCode)
            } : nil
        path = [route]
    }

    private func identityCreated(
        client: any GimClientAPI, context: OnboardingContext, userId: String, recoveryCode: String?
    ) {
        let claimHandle = ClaimHandleViewModel(client: client) {
            guard let session = try await client.session() else { throw GimError.NotRegistered }
            context.onRegistered(Registration(client: client, config: context.config, session: session))
        }
        guard let recoveryCode else {
            stage = .claimHandle(claimHandle)
            return
        }
        stage = .recoveryKit(
            RecoveryKitViewModel(userId: userId, code: recoveryCode, recoveryKit: context.recoveryKit) { [weak self] in
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
