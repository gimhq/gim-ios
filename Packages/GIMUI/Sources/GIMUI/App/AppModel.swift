import Foundation
import GIMClientKit
import GIMFeatures
import Observation
import SwiftUI

/// Owns the client and decides whether the app shows onboarding or the signed-in UI.
///
/// The server URL is part of `ClientConfig`, so the client is created for the last used server (stored in
/// `defaults`) or by onboarding for the URL the user types. Sync runs while the scene is active. Signing out drops
/// the client; onboarding creates a new one.
@MainActor
@Observable
public final class AppModel {
    public enum Phase {
        case launching
        case onboarding
        case ready(any GimClientAPI)
    }

    public static let serverUrlKey = "gim.serverUrl"
    /// Debug builds use gim-core instead of the demo client when launched with `-GIMUseRealCore YES`.
    public nonisolated static let useRealCoreKey = "GIMUseRealCore"

    public private(set) var phase: Phase = .launching
    public private(set) var session: Session?
    /// Server of the signed-in client.
    public private(set) var serverUrl: String?
    /// Set when the platform hooks could not be created or the session could not be read while launching.
    public private(set) var launchError: String?
    public private(set) var onboarding: OnboardingViewModel?

    private let factory: any GimClientFactory
    private let defaults: UserDefaults
    private let makeHooks: @MainActor () throws -> any PlatformHooks
    @ObservationIgnored private var hooks: (any PlatformHooks)?
    @ObservationIgnored private var client: (any GimClientAPI)?
    @ObservationIgnored private var isActive = false
    @ObservationIgnored private var isSyncing = false

    /// - Parameters:
    ///   - factory: the single swap point between `createClient` and test clients; see `defaultFactory()`.
    ///   - defaults: remembers the last server URL.
    ///   - makeHooks: builds the platform hooks handed to the factory (once per process).
    public init(
        factory: any GimClientFactory = AppModel.defaultFactory(),
        defaults: UserDefaults = .standard,
        makeHooks: @escaping @MainActor () throws -> any PlatformHooks = AppModel.defaultHooks
    ) {
        self.factory = factory
        self.defaults = defaults
        self.makeHooks = makeHooks
    }

    /// The demo client (`CoreGimClientFactory`) until gim-core implements the client; in debug builds the
    /// `useRealCoreKey` launch argument selects `RealGimClientFactory`.
    public nonisolated static func defaultFactory(defaults: UserDefaults = .standard) -> any GimClientFactory {
        #if DEBUG
            if defaults.bool(forKey: useRealCoreKey) { return RealGimClientFactory() }
        #endif
        return CoreGimClientFactory()
    }

    public static func defaultHooks() throws -> any PlatformHooks {
        AppPlatformHooks(dataDirectory: try AppDirectories.dataDirectory.path)
    }

    /// Creates the client for the last used server and routes by its session. Safe to call again after a launch
    /// error.
    public func start() async {
        guard case .launching = phase else { return }
        launchError = nil
        do {
            let hooks = try existingOrNewHooks()
            guard let url = defaults.string(forKey: Self.serverUrlKey) else {
                showOnboarding(hooks: hooks, serverUrl: "", client: nil)
                return
            }
            let config = ClientConfig(serverUrl: url)
            guard let client = try? await factory.make(config: config, hooks: hooks) else {
                // The stored URL is no longer accepted; let the user fix it.
                showOnboarding(hooks: hooks, serverUrl: url, client: nil)
                return
            }
            if let session = try await client.session() {
                showReady(client, config: config, session: session)
            } else {
                showOnboarding(hooks: hooks, serverUrl: url, client: client)
            }
        } catch {
            launchError = ErrorPresenter.message(for: error)
        }
    }

    /// Starts sync when the scene becomes active and stops it in the background.
    public func scenePhaseChanged(_ scenePhase: ScenePhase) async {
        switch scenePhase {
        case .active: isActive = true
        case .background: isActive = false
        default: return
        }
        await updateSync()
    }

    /// Signs out, drops the client and returns to onboarding. Returns the error text when signing out fails.
    public func signOut() async -> String? {
        guard let client, let hooks else { return nil }
        do {
            try await client.signOut()
        } catch {
            return ErrorPresenter.message(for: error)
        }
        (hooks as? AppPlatformHooks)?.reachability.attach(nil)
        self.client = nil
        isSyncing = false
        session = nil
        showOnboarding(hooks: hooks, serverUrl: serverUrl ?? "", client: nil)
        serverUrl = nil
        return nil
    }

    private func existingOrNewHooks() throws -> any PlatformHooks {
        if let hooks { return hooks }
        let hooks = try makeHooks()
        self.hooks = hooks
        return hooks
    }

    private func showOnboarding(hooks: any PlatformHooks, serverUrl: String, client: (any GimClientAPI)?) {
        onboarding = OnboardingViewModel(factory: factory, hooks: hooks, serverUrl: serverUrl, client: client) {
            [weak self] registration in
            self?.showReady(registration.client, config: registration.config, session: registration.session)
        }
        phase = .onboarding
    }

    private func showReady(_ client: any GimClientAPI, config: ClientConfig, session: Session) {
        self.client = client
        (hooks as? AppPlatformHooks)?.reachability.attach(client)
        defaults.set(config.serverUrl, forKey: Self.serverUrlKey)
        serverUrl = config.serverUrl
        self.session = session
        onboarding = nil
        phase = .ready(client)
        Task { await updateSync() }
    }

    private func updateSync() async {
        guard let client, session != nil, isActive != isSyncing else { return }
        let start = isActive
        isSyncing = start
        do {
            if start {
                try await client.startSync()
            } else {
                try await client.stopSync()
            }
        } catch {
            // Retried on the next scene phase change.
            isSyncing = !start
        }
    }
}
