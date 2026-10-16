import Foundation
import GIMClientKit
import GIMFeatures
import GIMPlatform
import Observation
import SwiftUI

/// Owns the client and decides whether the app shows onboarding or the signed-in UI.
///
/// The server URL is part of `ClientConfig`, so the client is created for the last used server (stored in
/// `defaults`, the App Group's by default, where the Notification Service Extension reads it too) or by onboarding for
/// the URL the user types. Sync runs while the scene is active. Signing out drops
/// the client; onboarding creates a new one. Every client created through the factory gets the system time zone
/// for its date separators (`TimeZoneMonitor`), also when it changes.
@MainActor
@Observable
public final class AppModel {
    public enum Phase {
        case launching
        case onboarding
        case ready(any GimClientAPI)
    }

    public static let serverUrlKey = AppGroup.serverUrlKey
    /// Launch argument (`-GIMDefaultServerURL <url>`) and Info.plist key (`GIM_DEFAULT_SERVER_URL` build setting)
    /// for the server pre-filled when no server was used yet.
    public nonisolated static let defaultServerUrlKey = "GIMDefaultServerURL"
    /// Debug builds use the demo client instead of gim-core when launched with `-GIMUseFakeCore YES`.
    public nonisolated static let useFakeCoreKey = "GIMUseFakeCore"
    /// With the demo client, `-GIMFakeRejectFirstSend YES` makes the hub reject the first own send for good (403
    /// `not_member`), for UI tests of failed messages.
    public nonisolated static let fakeRejectFirstSendKey = "GIMFakeRejectFirstSend"

    public private(set) var phase: Phase = .launching
    public private(set) var session: Session?
    /// Server of the signed-in client.
    public private(set) var serverUrl: String?
    /// Set when the platform hooks, the client (e.g. the keystore is locked) or the session could not be read while
    /// launching.
    public private(set) var launchError: String?
    public private(set) var onboarding: OnboardingViewModel?
    /// Debug builds: sync stays stopped while the scene is active (`holdSync`).
    public private(set) var isSyncHeld = false

    private let factory: any GimClientFactory
    private let defaults: UserDefaults
    private let bundledServerUrl: String?
    private let makeHooks: @MainActor () throws -> any PlatformHooks
    private let signedIn: @MainActor (any GimClientAPI) async -> Void
    @ObservationIgnored private var hooks: (any PlatformHooks)?
    @ObservationIgnored private var client: (any GimClientAPI)?
    @ObservationIgnored private var isActive = false
    @ObservationIgnored private var isSyncing = false

    /// - Parameters:
    ///   - factory: the single swap point between `createClient` and test clients; see `defaultFactory()`. Wrapped so
    ///     that every client it makes is attached to `timeZones`.
    ///   - defaults: remembers the last server URL; its argument domain may hold `defaultServerUrlKey`.
    ///   - bundledServerUrl: the Info.plist `defaultServerUrlKey` value.
    ///   - makeHooks: builds the platform hooks handed to the factory (once per process).
    ///   - timeZones: sets the system time zone on each new client and on time zone changes.
    ///   - signedIn: called with the client after each sign-in and at launch when signed in, e.g.
    ///     `AppNotifications.signedIn`.
    public init(
        factory: any GimClientFactory = AppModel.defaultFactory(),
        defaults: UserDefaults = AppGroup.defaults,
        bundledServerUrl: String? = Bundle.main.object(forInfoDictionaryKey: AppModel.defaultServerUrlKey) as? String,
        makeHooks: @escaping @MainActor () throws -> any PlatformHooks = AppModel.defaultHooks,
        timeZones: TimeZoneMonitor = TimeZoneMonitor(),
        signedIn: @escaping @MainActor (any GimClientAPI) async -> Void = { _ in }
    ) {
        self.factory = TimeZoneAttachingFactory(base: factory, timeZones: timeZones)
        self.defaults = defaults
        self.bundledServerUrl = bundledServerUrl
        self.makeHooks = makeHooks
        self.signedIn = signedIn
    }

    /// gim-core (`RealGimClientFactory`); in debug builds the `useFakeCoreKey` launch argument selects the demo
    /// client (`CoreGimClientFactory`, see `fakeRejectFirstSendKey`). Release builds always use gim-core.
    public nonisolated static func defaultFactory(defaults: UserDefaults = .standard) -> any GimClientFactory {
        #if DEBUG
            if defaults.bool(forKey: useFakeCoreKey) {
                guard defaults.bool(forKey: fakeRejectFirstSendKey) else { return CoreGimClientFactory() }
                return RejectingFakeFactory()
            }
        #endif
        return RealGimClientFactory()
    }

    /// The data directory and Keychain items are shared with the Notification Service Extension through the App
    /// Group; the data directory from before the App Group is removed.
    public static func defaultHooks() throws -> any PlatformHooks {
        AppDirectories.removeLegacyDataDirectory()
        return AppPlatformHooks(dataDirectory: try AppDirectories.dataDirectory.path)
    }

    /// Creates the client for the last used server and routes by its session. Safe to call again after a launch
    /// error.
    public func start() async {
        guard case .launching = phase else { return }
        launchError = nil
        do {
            let hooks = try existingOrNewHooks()
            guard let url = defaults.string(forKey: Self.serverUrlKey) else {
                showOnboarding(hooks: hooks, serverUrl: defaultServerUrl(stored: nil), client: nil)
                return
            }
            let config = ClientConfig(serverUrl: url)
            let client: any GimClientAPI
            do {
                client = try await factory.make(config: config, hooks: hooks)
            } catch {
                // The keystore can't be read (e.g. locked): retry instead of onboarding over the existing identity.
                if let error = error as? GimError, case .Storage = error { throw error }
                // The stored URL is no longer accepted; let the user fix it.
                showOnboarding(hooks: hooks, serverUrl: url, client: nil)
                return
            }
            if let session = try await client.session() {
                showReady(client, config: config, session: session)
            } else {
                showOnboarding(
                    hooks: hooks, serverUrl: url, client: client, localStateReset: client.localStateReset())
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

    #if DEBUG
        /// Debug builds: stops sync and keeps it stopped while `held`, even when the scene becomes active; releasing
        /// starts it again if the scene is active. For `DebugPushURL.holdSyncURL`.
        public func holdSync(_ held: Bool) async {
            isSyncHeld = held
            await updateSync()
        }
    #endif

    /// Signs out, wipes the platform keystore and data directory (`PlatformWiping`), drops the client and returns to
    /// onboarding. Returns the error text when signing out or wiping fails; a failed wipe still returns to onboarding.
    public func signOut() async -> String? {
        guard let client, let hooks else { return nil }
        do {
            try await client.signOut()
        } catch {
            return ErrorPresenter.message(for: error)
        }
        var wipeError: String?
        do {
            try (hooks as? any PlatformWiping)?.wipe()
        } catch {
            wipeError = ErrorPresenter.message(for: error)
        }
        (hooks as? AppPlatformHooks)?.reachability.attach(nil)
        self.client = nil
        isSyncing = false
        session = nil
        showOnboarding(hooks: hooks, serverUrl: defaultServerUrl(stored: serverUrl), client: nil)
        serverUrl = nil
        return wipeError
    }

    /// Re-reads the session, e.g. after claiming a handle in Settings.
    public func refreshSession() async {
        guard let client, let session = try? await client.session(), client === self.client else { return }
        self.session = session
    }

    private func defaultServerUrl(stored: String?) -> String {
        OnboardingValidation.defaultServerUrl(
            stored: stored, argument: defaults.string(forKey: Self.defaultServerUrlKey), bundled: bundledServerUrl)
    }

    private func existingOrNewHooks() throws -> any PlatformHooks {
        if let hooks { return hooks }
        let hooks = try makeHooks()
        self.hooks = hooks
        return hooks
    }

    private func showOnboarding(
        hooks: any PlatformHooks, serverUrl: String, client: (any GimClientAPI)?, localStateReset: Bool = false
    ) {
        onboarding = OnboardingViewModel(
            factory: factory, hooks: hooks, serverUrl: serverUrl, client: client, localStateReset: localStateReset
        ) { [weak self] registration in
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
        Task { await signedIn(client) }
    }

    private func updateSync() async {
        let start = isActive && !isSyncHeld
        guard let client, session != nil, start != isSyncing else { return }
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

/// Attaches every client `base` creates to `timeZones`, so the real and the demo client bucket their date separators
/// in the system time zone.
private struct TimeZoneAttachingFactory: GimClientFactory {
    let base: any GimClientFactory
    let timeZones: TimeZoneMonitor

    func make(config: ClientConfig, hooks: any PlatformHooks) async throws -> any GimClientAPI {
        let client = try await base.make(config: config, hooks: hooks)
        timeZones.attach(client)
        return client
    }
}

#if DEBUG
    /// Demo clients whose first own send the hub rejects for good; see `AppModel.fakeRejectFirstSendKey`.
    private struct RejectingFakeFactory: GimClientFactory {
        func make(config: ClientConfig, hooks: any PlatformHooks) async throws -> any GimClientAPI {
            let client = try await CoreGimClientFactory().make(config: config, hooks: hooks)
            await (client as? FakeGimClient)?.rejectNextSend()
            return client
        }
    }
#endif
