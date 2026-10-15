import Foundation
import GIMClientKit
import GIMFeatures
import Observation

/// Owns the client and decides whether the app shows onboarding or the signed-in UI.
@MainActor
@Observable
public final class AppModel {
    public enum Phase {
        case launching
        case onboarding
        case ready(any GimClientAPI)
    }

    public private(set) var phase: Phase = .launching
    public private(set) var session: Session?
    /// Set when the client could not be created or queried while launching.
    public private(set) var launchError: String?
    public private(set) var onboarding: OnboardingViewModel?

    private let factory: any GimClientFactory
    private let makeHooks: @MainActor () throws -> PlatformHooks
    private var client: (any GimClientAPI)?
    private var reachability: ReachabilityMonitor?

    /// - Parameters:
    ///   - factory: the single swap point between the demo client and the gim-core bindings.
    ///   - makeHooks: builds the platform hooks handed to the factory.
    public init(
        factory: any GimClientFactory = FakeGimClientFactory(),
        makeHooks: @escaping @MainActor () throws -> PlatformHooks = AppModel.defaultHooks
    ) {
        self.factory = factory
        self.makeHooks = makeHooks
    }

    public static func defaultHooks() throws -> PlatformHooks {
        PlatformHooks(secureStorage: KeychainSecureStorage(), dataDirectory: try AppDirectories.dataDirectory.path)
    }

    /// Creates the client (once) and routes by its login state. Safe to call again after a launch error.
    public func start() async {
        guard case .launching = phase else { return }
        launchError = nil
        do {
            let client = try await existingOrNewClient()
            switch try await client.loginState() {
            case .unregistered:
                showOnboarding(client)
            case .registered(let session):
                showReady(client, session: session)
            }
        } catch {
            launchError = ErrorPresenter.message(for: error)
        }
    }

    /// Logs out and returns to onboarding. Returns the error text when logout fails.
    public func signOut() async -> String? {
        guard let client else { return nil }
        do {
            try await client.logout()
        } catch {
            return ErrorPresenter.message(for: error)
        }
        session = nil
        showOnboarding(client)
        return nil
    }

    private func existingOrNewClient() async throws -> any GimClientAPI {
        if let client { return client }
        let client = try await factory.make(hooks: makeHooks())
        self.client = client
        let reachability = ReachabilityMonitor(client: client)
        reachability.start()
        self.reachability = reachability
        return client
    }

    private func showOnboarding(_ client: any GimClientAPI) {
        onboarding = OnboardingViewModel(client: client) { [weak self] session in
            self?.showReady(client, session: session)
        }
        phase = .onboarding
    }

    private func showReady(_ client: any GimClientAPI, session: Session) {
        self.session = session
        onboarding = nil
        phase = .ready(client)
    }
}
