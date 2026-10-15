import Foundation
import GIMClientKit
import GIMFeatures
import SwiftUI
import XCTest

@testable import GIMUI

final class AppModelTests: XCTestCase {
    private final class MemoryHooks: PlatformHooks, @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String: Data] = [:]
        private let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path

        func secureStoreGet(key: String) -> Data? { lock.withLock { values[key] } }
        func secureStoreSet(key: String, value: Data) throws { lock.withLock { values[key] = value } }
        func secureStoreDelete(key: String) { _ = lock.withLock { values.removeValue(forKey: key) } }
        func dataDir() -> String { directory }
        func isNetworkReachable() -> Bool { true }
    }

    /// Returns `clients` in order (the last one repeatedly) and records every config.
    private final class ClientFactory: GimClientFactory, @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [ClientConfig] = []
        private let clients: [FakeGimClient]

        init(_ clients: FakeGimClient...) {
            self.clients = clients
        }

        var configs: [ClientConfig] { lock.withLock { recorded } }

        func make(config: ClientConfig, hooks: any PlatformHooks) async throws -> any GimClientAPI {
            lock.withLock {
                recorded.append(config)
                return clients[min(recorded.count, clients.count) - 1]
            }
        }
    }

    private let session = Session(userId: "user-alex", deviceId: "device-1", handle: "alex", displayName: "Alex")

    private func makeDefaults() -> UserDefaults {
        let suite = "gim-tests-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        return UserDefaults(suiteName: suite)!
    }

    @MainActor
    private func makeModel(factory: ClientFactory, defaults: UserDefaults) -> AppModel {
        AppModel(factory: factory, defaults: defaults) { MemoryHooks() }
    }

    func testDefaultFactoryIsTheRealCore() {
        XCTAssertTrue(AppModel.defaultFactory(defaults: makeDefaults()) is RealGimClientFactory)
    }

    func testFakeCoreLaunchArgumentSelectsTheDemoClientInDebugBuilds() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: AppModel.useFakeCoreKey)
        #if DEBUG
            XCTAssertTrue(AppModel.defaultFactory(defaults: defaults) is CoreGimClientFactory)
        #else
            XCTAssertTrue(AppModel.defaultFactory(defaults: defaults) is RealGimClientFactory)
        #endif
    }

    @MainActor
    func testFirstLaunchShowsOnboardingAndRegistrationShowsReady() async throws {
        let factory = ClientFactory(FakeGimClient())
        let defaults = makeDefaults()
        let model = makeModel(factory: factory, defaults: defaults)
        await model.start()
        guard case .onboarding = model.phase else { return XCTFail("expected onboarding, got \(model.phase)") }
        XCTAssertTrue(factory.configs.isEmpty, "no server URL yet, so no client")

        let onboarding = try XCTUnwrap(model.onboarding)
        onboarding.serverUrl = "http://192.168.1.20:8080"
        onboarding.handle = "alex"
        onboarding.displayName = "Alex"
        await onboarding.submit()

        guard case .ready = model.phase else { return XCTFail("expected ready, got \(model.phase)") }
        XCTAssertEqual(factory.configs, [ClientConfig(serverUrl: "http://192.168.1.20:8080")])
        XCTAssertEqual(model.session?.handle, "alex")
        XCTAssertEqual(model.serverUrl, "http://192.168.1.20:8080")
        XCTAssertEqual(defaults.string(forKey: AppModel.serverUrlKey), "http://192.168.1.20:8080")
    }

    @MainActor
    func testStoredServerWithSessionGoesStraightToReady() async {
        let session = session
        let factory = ClientFactory(FakeGimClient(session: session))
        let defaults = makeDefaults()
        defaults.set("https://gim.example.eu", forKey: AppModel.serverUrlKey)
        let model = makeModel(factory: factory, defaults: defaults)

        await model.start()

        guard case .ready = model.phase else { return XCTFail("expected ready, got \(model.phase)") }
        XCTAssertEqual(factory.configs, [ClientConfig(serverUrl: "https://gim.example.eu")])
        XCTAssertEqual(model.session, session)
    }

    @MainActor
    func testScenePhaseStartsAndStopsSync() async throws {
        let session = session
        let scheduler = ManualFakeScheduler()
        let client = FakeGimClient(scheduler: scheduler, session: session)
        let defaults = makeDefaults()
        defaults.set("https://gim.example.eu", forKey: AppModel.serverUrlKey)
        let model = makeModel(factory: ClientFactory(client), defaults: defaults)
        await model.start()
        var states = try await ListenerBridge.connectionState(client).makeAsyncIterator()
        let initial = await states.next()
        XCTAssertEqual(initial, .offline)

        await model.scenePhaseChanged(.active)
        let connecting = await states.next()
        XCTAssertEqual(connecting, .connecting)

        await model.scenePhaseChanged(.background)
        let offline = await states.next()
        XCTAssertEqual(offline, .offline)
    }

    @MainActor
    func testSignOutReturnsToOnboardingAndRecreatesTheClient() async throws {
        let factory = ClientFactory(FakeGimClient(session: session), FakeGimClient())
        let defaults = makeDefaults()
        defaults.set("https://gim.example.eu", forKey: AppModel.serverUrlKey)
        let model = makeModel(factory: factory, defaults: defaults)
        await model.start()

        let error = await model.signOut()

        XCTAssertNil(error)
        XCTAssertNil(model.session)
        guard case .onboarding = model.phase else { return XCTFail("expected onboarding, got \(model.phase)") }
        let onboarding = try XCTUnwrap(model.onboarding)
        XCTAssertEqual(onboarding.serverUrl, "https://gim.example.eu")
        onboarding.handle = "alex"
        onboarding.displayName = "Alex"
        await onboarding.submit()
        XCTAssertEqual(factory.configs.count, 2, "a new client is created after signing out")
        guard case .ready = model.phase else { return XCTFail("expected ready, got \(model.phase)") }
    }
}
