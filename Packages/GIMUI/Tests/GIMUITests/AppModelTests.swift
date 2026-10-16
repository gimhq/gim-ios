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

    /// Forwards to a `FakeGimClient`, except that `signOut` can fail and `localStateReset` is configurable; records
    /// the zones passed to `setLocalTimeZone`.
    private actor StubClient: GimClientAPI {
        let fake: FakeGimClient
        let signOutError: GimError?
        let reportsLocalStateReset: Bool
        private nonisolated let zoneLock = NSLock()
        private nonisolated(unsafe) var zones: [(any LocalTimeZone)?] = []

        nonisolated var timeZones: [(any LocalTimeZone)?] { zoneLock.withLock { zones } }

        init(_ fake: FakeGimClient, signOutError: GimError? = nil, localStateReset: Bool = false) {
            self.fake = fake
            self.signOutError = signOutError
            reportsLocalStateReset = localStateReset
        }

        func signOut() async throws {
            if let signOutError { throw signOutError }
            try await fake.signOut()
        }

        func session() async throws -> Session? { try await fake.session() }
        nonisolated func userId() -> String? { fake.userId() }
        nonisolated func localStateReset() -> Bool { reportsLocalStateReset }
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
        nonisolated func setLocalTimeZone(zone: (any LocalTimeZone)?) {
            zoneLock.withLock { zones.append(zone) }
            fake.setLocalTimeZone(zone: zone)
        }
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
        func chatState(chatId: String) async throws -> ChatState { try await fake.chatState(chatId: chatId) }
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

    /// Returns `clients` in order (the last one repeatedly) and records every config; throws `error` while set.
    private final class ClientFactory: GimClientFactory, @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [ClientConfig] = []
        private var made = 0
        private let clients: [any GimClientAPI]
        private var failure: (any Error)?

        init(_ clients: any GimClientAPI...) {
            self.clients = clients
        }

        var configs: [ClientConfig] { lock.withLock { recorded } }

        var error: (any Error)? {
            get { lock.withLock { failure } }
            set { lock.withLock { failure = newValue } }
        }

        func make(config: ClientConfig, hooks: any PlatformHooks) async throws -> any GimClientAPI {
            try lock.withLock {
                recorded.append(config)
                if let failure { throw failure }
                made += 1
                return clients[min(made, clients.count) - 1]
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

    /// Runs the create flow: display name, recovery code confirmation and handle `alex`.
    @MainActor
    private func register(_ onboarding: OnboardingViewModel) async throws {
        onboarding.choose(.createIdentity)
        let create = try XCTUnwrap(onboarding.createIdentity)
        create.displayName = "Alex"
        await create.submit()
        guard case .recoveryCode(let recovery) = onboarding.stage else {
            return XCTFail("expected the recovery code, got \(String(describing: onboarding.stage))")
        }
        recovery.continueToConfirmation()
        recovery.confirmationInput = recovery.groups[recovery.confirmationGroupIndex]
        recovery.confirm()
        guard case .claimHandle(let claim) = onboarding.stage else {
            return XCTFail("expected the handle step, got \(String(describing: onboarding.stage))")
        }
        claim.handle = "alex"
        await claim.claim()
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

    func testFakeRejectFirstSendLaunchArgumentArmsTheDemoClient() async throws {
        let defaults = makeDefaults()
        defaults.set(true, forKey: AppModel.useFakeCoreKey)
        defaults.set(true, forKey: AppModel.fakeRejectFirstSendKey)
        #if DEBUG
            let client = try await AppModel.defaultFactory(defaults: defaults)
                .make(config: ClientConfig(serverUrl: "http://localhost:8080"), hooks: MemoryHooks())
            _ = try await client.createIdentity(displayName: "Alex")
            let chatId = FakeGimClient.demoGroupChatId
            let messageId = try await client.sendText(chatId: chatId, body: "Hello", replyTo: nil)
            var items: [TimelineItem] = []
            for await diffs in try await ListenerBridge.timeline(client, chatId: chatId) {
                try DiffApplier.apply(diffs, to: &items)
                break
            }
            let sendStates = items.compactMap { item -> SendState? in
                guard case .message(let message) = item, message.messageId == messageId else { return nil }
                return message.sendState
            }
            XCTAssertEqual(sendStates, [.failed(reason: "rejected (403 not_member)")])
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
        try await register(onboarding)

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
    func testClientsGetTheSystemTimeZoneAgainWhenItChanges() async throws {
        let client = StubClient(FakeGimClient(session: session))
        let defaults = makeDefaults()
        defaults.set("https://gim.example.eu", forKey: AppModel.serverUrlKey)
        let center = NotificationCenter()
        let hooks = MemoryHooks()
        let model = AppModel(
            factory: ClientFactory(client), defaults: defaults, bundledServerUrl: nil, makeHooks: { hooks },
            timeZones: TimeZoneMonitor(notificationCenter: center))

        await model.start()

        XCTAssertEqual(client.timeZones.count, 1)
        let first = try XCTUnwrap(client.timeZones.first ?? nil)
        let offset = Int32(TimeZone.current.secondsFromGMT(for: Date(timeIntervalSince1970: 1_790_000)))
        XCTAssertEqual(first.utcOffsetSecs(atMs: 1_790_000_000), offset)

        center.post(name: .NSSystemTimeZoneDidChange, object: nil)

        XCTAssertEqual(client.timeZones.count, 2)
        let second = try XCTUnwrap(client.timeZones.last ?? nil)
        XCTAssertFalse(first === second, "a fresh zone object, so gim-core drops its cached offsets")
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
        try await register(onboarding)
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
        let client = StubClient(FakeGimClient(session: session), signOutError: .Network(reason: "offline"))
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

    @MainActor
    func testLocalStateResetShowsOnboardingWithANotice() async throws {
        let client = StubClient(FakeGimClient(), localStateReset: true)
        let defaults = makeDefaults()
        defaults.set("https://gim.example.eu", forKey: AppModel.serverUrlKey)
        let model = makeModel(factory: ClientFactory(client), defaults: defaults)

        await model.start()

        guard case .onboarding = model.phase else { return XCTFail("expected onboarding, got \(model.phase)") }
        let onboarding = try XCTUnwrap(model.onboarding)
        XCTAssertTrue(onboarding.showsLocalStateResetNotice)
        XCTAssertEqual(onboarding.serverUrl, "https://gim.example.eu")
        onboarding.dismissLocalStateResetNotice()
        XCTAssertFalse(onboarding.showsLocalStateResetNotice)
    }

    @MainActor
    func testOnboardingWithoutResetShowsNoNotice() async throws {
        let defaults = makeDefaults()
        defaults.set("https://gim.example.eu", forKey: AppModel.serverUrlKey)
        let model = makeModel(factory: ClientFactory(FakeGimClient()), defaults: defaults)

        await model.start()

        XCTAssertEqual(model.onboarding?.showsLocalStateResetNotice, false)
    }

    @MainActor
    func testUnreadableKeystoreShowsALaunchErrorAndRetriesWithoutWiping() async {
        let hooks = MemoryHooks()
        let factory = ClientFactory(FakeGimClient(session: session))
        factory.error = GimError.Storage(reason: "Keychain read failed with status -25308")
        let defaults = makeDefaults()
        defaults.set("https://gim.example.eu", forKey: AppModel.serverUrlKey)
        let model = makeModel(factory: factory, defaults: defaults, hooks: hooks)

        await model.start()

        guard case .launching = model.phase else { return XCTFail("expected launching, got \(model.phase)") }
        XCTAssertNotNil(model.launchError)
        XCTAssertNil(model.onboarding)
        XCTAssertEqual(hooks.wipeCount, 0)
        XCTAssertEqual(defaults.string(forKey: AppModel.serverUrlKey), "https://gim.example.eu")

        factory.error = nil
        await model.start()

        XCTAssertNil(model.launchError)
        guard case .ready = model.phase else { return XCTFail("expected ready, got \(model.phase)") }
        XCTAssertEqual(model.session, session)
    }

    @MainActor
    func testRejectedStoredServerStillShowsOnboarding() async {
        let factory = ClientFactory(FakeGimClient())
        factory.error = GimError.InvalidInput(reason: "server_url: missing host")
        let defaults = makeDefaults()
        defaults.set("https://gim.example.eu", forKey: AppModel.serverUrlKey)
        let model = makeModel(factory: factory, defaults: defaults)

        await model.start()

        guard case .onboarding = model.phase else { return XCTFail("expected onboarding, got \(model.phase)") }
        XCTAssertNil(model.launchError)
    }

    @MainActor
    func testRefreshSessionPicksUpAClaimedHandle() async throws {
        let unnamed = Session(userId: "user-alex", deviceId: "device-1", handle: "", displayName: "Alex")
        let client = FakeGimClient(session: unnamed)
        let defaults = makeDefaults()
        defaults.set("https://gim.example.eu", forKey: AppModel.serverUrlKey)
        let model = makeModel(factory: ClientFactory(client), defaults: defaults)
        await model.start()
        XCTAssertEqual(model.session?.handle, "")

        try await client.claimHandle(handle: "alex")
        await model.refreshSession()

        XCTAssertEqual(model.session?.handle, "alex")
    }
}
