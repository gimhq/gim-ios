import Foundation
import GIMClientKit
import GIMFeatures
import SwiftUI
import XCTest

@testable import GIMUI

final class AppModelTests: XCTestCase {
    private final class MemoryHooks: PlatformHooks, PlatformWiping, @unchecked Sendable {
        private let lock = NSLock()
        private var values: [String: Data] = [:]
        private var wipes = 0
        /// Thrown by `wipe()` when set.
        var wipeError: (any Error)?
        private let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path

        func secureStoreGet(key: String) throws -> Data? { lock.withLock { values[key] } }
        func secureStoreSet(key: String, value: Data) throws { lock.withLock { values[key] = value } }
        func secureStoreDelete(key: String) { _ = lock.withLock { values.removeValue(forKey: key) } }
        func dataDir() -> String { directory }
        func isNetworkReachable() -> Bool { true }

        var wipeCount: Int { lock.withLock { wipes } }

        func wipe() throws {
            lock.withLock { wipes += 1 }
            if let wipeError { throw wipeError }
        }
    }

    /// Forwards to a `FakeGimClient`, except that `signOut` always fails.
    private actor FailingSignOutClient: GimClientAPI {
        let fake: FakeGimClient

        init(_ fake: FakeGimClient) {
            self.fake = fake
        }

        func signOut() async throws { throw GimError.Network(reason: "offline") }

        func session() async throws -> Session? { try await fake.session() }
        nonisolated func userId() -> String? { fake.userId() }
        nonisolated func localStateReset() -> Bool { fake.localStateReset() }
        func createIdentity(displayName: String) async throws -> String {
            try await fake.createIdentity(displayName: displayName)
        }
        func restoreFromRecovery(userId: String, recoveryCode: String, revokeOthers: Bool) async throws {
            try await fake.restoreFromRecovery(userId: userId, recoveryCode: recoveryCode, revokeOthers: revokeOthers)
        }
        nonisolated func startLink(hubs: [String]) throws -> any LinkSession { try fake.startLink(hubs: hubs) }
        func waitLink(link: any LinkSession) async throws -> String { try await fake.waitLink(link: link) }
        func confirmLink(accepted: Bool) async throws { try await fake.confirmLink(accepted: accepted) }
        func approveLink(qrString: String) async throws -> any PendingApproval {
            try await fake.approveLink(qrString: qrString)
        }
        func confirmApproval(approval: any PendingApproval, accepted: Bool) async throws {
            try await fake.confirmApproval(approval: approval, accepted: accepted)
        }
        func devices() async throws -> [DeviceInfo] { try await fake.devices() }
        func userDevices(userId: String) async throws -> [DeviceInfo] { try await fake.userDevices(userId: userId) }
        func revokeDevice(deviceId: String) async throws { try await fake.revokeDevice(deviceId: deviceId) }
        func setDisplayName(name: String) async throws { try await fake.setDisplayName(name: name) }
        func claimHandle(handle: String) async throws { try await fake.claimHandle(handle: handle) }
        func releaseHandle() async throws { try await fake.releaseHandle() }
        func stopTyping(chatId: String) async throws { try await fake.stopTyping(chatId: chatId) }
        func startSync() async throws { try await fake.startSync() }
        func stopSync() async throws { try await fake.stopSync() }
        nonisolated func setNetworkReachable(reachable: Bool) { fake.setNetworkReachable(reachable: reachable) }
        func findUser(handle: String) async throws -> UserProfile? { try await fake.findUser(handle: handle) }
        func createDirectChat(userId: String) async throws -> String { try await fake.createDirectChat(userId: userId) }
        func createGroupChat(name: String, memberUserIds: [String]) async throws -> String {
            try await fake.createGroupChat(name: name, memberUserIds: memberUserIds)
        }
        func chatMembers(chatId: String) async throws -> [UserProfile] { try await fake.chatMembers(chatId: chatId) }
        func addMembers(chatId: String, userIds: [String]) async throws {
            try await fake.addMembers(chatId: chatId, userIds: userIds)
        }
        func removeMember(chatId: String, userId: String) async throws {
            try await fake.removeMember(chatId: chatId, userId: userId)
        }
        func leaveChat(chatId: String) async throws { try await fake.leaveChat(chatId: chatId) }
        func setGroupInfo(chatId: String, name: String?, avatarFilePath: String?) async throws {
            try await fake.setGroupInfo(chatId: chatId, name: name, avatarFilePath: avatarFilePath)
        }
        func sendText(chatId: String, body: String, replyTo: String?) async throws -> String {
            try await fake.sendText(chatId: chatId, body: body, replyTo: replyTo)
        }
        func sendMedia(
            chatId: String, filePath: String, mime: String, caption: String?, replyTo: String?
        ) async throws -> String {
            try await fake.sendMedia(chatId: chatId, filePath: filePath, mime: mime, caption: caption, replyTo: replyTo)
        }
        func editMessage(chatId: String, messageId: String, newBody: String) async throws {
            try await fake.editMessage(chatId: chatId, messageId: messageId, newBody: newBody)
        }
        func deleteMessage(chatId: String, messageId: String) async throws {
            try await fake.deleteMessage(chatId: chatId, messageId: messageId)
        }
        func react(chatId: String, messageId: String, emoji: String) async throws {
            try await fake.react(chatId: chatId, messageId: messageId, emoji: emoji)
        }
        func unreact(chatId: String, messageId: String, emoji: String) async throws {
            try await fake.unreact(chatId: chatId, messageId: messageId, emoji: emoji)
        }
        func retrySend(chatId: String, messageId: String) async throws {
            try await fake.retrySend(chatId: chatId, messageId: messageId)
        }
        func cancelSend(chatId: String, messageId: String) async throws {
            try await fake.cancelSend(chatId: chatId, messageId: messageId)
        }
        func markRead(chatId: String, upToMessageId: String) async throws {
            try await fake.markRead(chatId: chatId, upToMessageId: upToMessageId)
        }
        func setTyping(chatId: String, active: Bool) async throws {
            try await fake.setTyping(chatId: chatId, active: active)
        }
        func fetchMedia(chatId: String, messageId: String, destPath: String) async throws -> String {
            try await fake.fetchMedia(chatId: chatId, messageId: messageId, destPath: destPath)
        }
        func fetchThumbnail(chatId: String, messageId: String, destPath: String) async throws -> String? {
            try await fake.fetchThumbnail(chatId: chatId, messageId: messageId, destPath: destPath)
        }
        func chatList(listener: any ChatListListener) async throws -> TaskHandle {
            try await fake.chatList(listener: listener)
        }
        func timeline(chatId: String) async throws -> any Timeline { try await fake.timeline(chatId: chatId) }
        func connectionState(listener: any ConnectionStateListener) async throws -> TaskHandle {
            try await fake.connectionState(listener: listener)
        }
        func typing(chatId: String, listener: any TypingListener) async throws -> TaskHandle {
            try await fake.typing(chatId: chatId, listener: listener)
        }
    }

    /// Returns `clients` in order (the last one repeatedly) and records every config.
    private final class ClientFactory: GimClientFactory, @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [ClientConfig] = []
        private let clients: [any GimClientAPI]

        init(_ clients: any GimClientAPI...) {
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
    private func makeModel(
        factory: ClientFactory, defaults: UserDefaults, bundledServerUrl: String? = nil,
        hooks: MemoryHooks = MemoryHooks()
    ) -> AppModel {
        AppModel(factory: factory, defaults: defaults, bundledServerUrl: bundledServerUrl) { hooks }
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
        XCTAssertEqual(model.onboarding?.serverUrl, "")

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

    @MainActor
    func testFirstLaunchPrefillsTheBundledDefaultServer() async {
        let model = makeModel(
            factory: ClientFactory(FakeGimClient()), defaults: makeDefaults(),
            bundledServerUrl: "http://localhost:8080/")
        await model.start()
        XCTAssertEqual(model.onboarding?.serverUrl, "http://localhost:8080")
    }

    @MainActor
    func testLaunchArgumentOverridesTheBundledDefaultServer() async {
        let defaults = makeDefaults()
        defaults.set("http://127.0.0.1:8080", forKey: AppModel.defaultServerUrlKey)
        let model = makeModel(
            factory: ClientFactory(FakeGimClient()), defaults: defaults, bundledServerUrl: "http://localhost:8080")
        await model.start()
        XCTAssertEqual(model.onboarding?.serverUrl, "http://127.0.0.1:8080")
    }

    @MainActor
    func testStoredServerWinsOverTheDefaults() async {
        let defaults = makeDefaults()
        defaults.set("https://gim.example.eu", forKey: AppModel.serverUrlKey)
        defaults.set("http://127.0.0.1:8080", forKey: AppModel.defaultServerUrlKey)
        let model = makeModel(
            factory: ClientFactory(FakeGimClient()), defaults: defaults, bundledServerUrl: "http://localhost:8080")
        await model.start()
        XCTAssertEqual(model.onboarding?.serverUrl, "https://gim.example.eu")
    }

    @MainActor
    func testSignOutWipesThePlatformOnce() async {
        let hooks = MemoryHooks()
        let defaults = makeDefaults()
        defaults.set("https://gim.example.eu", forKey: AppModel.serverUrlKey)
        let model = makeModel(
            factory: ClientFactory(FakeGimClient(session: session), FakeGimClient()), defaults: defaults, hooks: hooks)
        await model.start()

        let error = await model.signOut()

        XCTAssertNil(error)
        XCTAssertEqual(hooks.wipeCount, 1)
        XCTAssertEqual(defaults.string(forKey: AppModel.serverUrlKey), "https://gim.example.eu")
    }

    @MainActor
    func testFailedSignOutDoesNotWipe() async {
        let hooks = MemoryHooks()
        let defaults = makeDefaults()
        defaults.set("https://gim.example.eu", forKey: AppModel.serverUrlKey)
        let client = FailingSignOutClient(FakeGimClient(session: session))
        let model = makeModel(factory: ClientFactory(client), defaults: defaults, hooks: hooks)
        await model.start()

        let error = await model.signOut()

        XCTAssertNotNil(error)
        XCTAssertEqual(hooks.wipeCount, 0)
        guard case .ready = model.phase else { return XCTFail("expected ready, got \(model.phase)") }
    }

    @MainActor
    func testFailedWipeStillReturnsToOnboarding() async {
        let hooks = MemoryHooks()
        hooks.wipeError = GimError.Storage(reason: "Keychain delete failed")
        let defaults = makeDefaults()
        defaults.set("https://gim.example.eu", forKey: AppModel.serverUrlKey)
        let model = makeModel(
            factory: ClientFactory(FakeGimClient(session: session), FakeGimClient()), defaults: defaults, hooks: hooks)
        await model.start()

        let error = await model.signOut()

        XCTAssertNotNil(error)
        guard case .onboarding = model.phase else { return XCTFail("expected onboarding, got \(model.phase)") }
        XCTAssertEqual(model.onboarding?.serverUrl, "https://gim.example.eu")
    }
}
