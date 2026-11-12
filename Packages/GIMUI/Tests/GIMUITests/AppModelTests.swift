import Foundation
import GIMClientKit
import GIMFeatures
import GIMPlatform
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

    /// Forwards to a `FakeGimClient`, except that `signOut` and `deleteAccount` can fail and `localStateReset` is
    /// configurable; records the zones passed to `setLocalTimeZone`.
    private actor StubClient: GimClientAPI {
        let fake: FakeGimClient
        let signOutError: GimError?
        let deleteAccountError: GimError?
        let reportsLocalStateReset: Bool
        private nonisolated let zoneLock = NSLock()
        private nonisolated(unsafe) var zones: [(any LocalTimeZone)?] = []

        nonisolated var timeZones: [(any LocalTimeZone)?] { zoneLock.withLock { zones } }

        init(
            _ fake: FakeGimClient, signOutError: GimError? = nil, deleteAccountError: GimError? = nil,
            localStateReset: Bool = false
        ) {
            self.fake = fake
            self.signOutError = signOutError
            self.deleteAccountError = deleteAccountError
            reportsLocalStateReset = localStateReset
        }

        func signOut() async throws {
            if let signOutError { throw signOutError }
            try await fake.signOut()
        }

        func session() async throws -> Session? { try await fake.session() }
        nonisolated func userId() -> String? { fake.userId() }
        nonisolated func recoveryCode() throws -> String? { try fake.recoveryCode() }
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
        func stopTyping(chatId: String) async throws { try await fake.stopTyping(chatId: chatId) }
        func startSync() async throws { try await fake.startSync() }
        func stopSync() async throws { try await fake.stopSync() }
        nonisolated func setNetworkReachable(reachable: Bool) { fake.setNetworkReachable(reachable: reachable) }
        nonisolated func setLocalTimeZone(zone: (any LocalTimeZone)?) {
            zoneLock.withLock { zones.append(zone) }
            fake.setLocalTimeZone(zone: zone)
        }
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

        func hubs() async throws -> [HubInfo] {
            try await fake.hubs()
        }

        func addHub(url: String) async throws -> HubInfo {
            try await fake.addHub(url: url)
        }

        func removeHub(hubId: String, confirmOwnedGroups: Bool) async throws {
            try await fake.removeHub(hubId: hubId, confirmOwnedGroups: confirmOwnedGroups)
        }

        func setPrimaryHub(hubId: String) async throws {
            try await fake.setPrimaryHub(hubId: hubId)
        }

        func hubList(listener: any HubListListener) async throws -> TaskHandle {
            try await fake.hubList(listener: listener)
        }

        func registerPush(registration: PushRegistration) async throws {
            try await fake.registerPush(registration: registration)
        }

        func unregisterPush() async throws {
            try await fake.unregisterPush()
        }

        func processPush(payload: String) async throws -> NotificationContent {
            try await fake.processPush(payload: payload)
        }

        func ownProfile() async throws -> UserProfile? {
            try await fake.ownProfile()
        }

        func setAvatar(filePath: String, mime: String) async throws {
            try await fake.setAvatar(filePath: filePath, mime: mime)
        }

        func removeAvatar() async throws {
            try await fake.removeAvatar()
        }

        func fetchUserAvatar(userId: String, destPath: String) async throws -> String {
            try await fake.fetchUserAvatar(userId: userId, destPath: destPath)
        }

        func fetchChatAvatar(chatId: String, destPath: String) async throws -> String {
            try await fake.fetchChatAvatar(chatId: chatId, destPath: destPath)
        }

        func privacy() async throws -> PrivacySettings {
            try await fake.privacy()
        }

        func setReadReceipts(enabled: Bool) async throws {
            try await fake.setReadReceipts(enabled: enabled)
        }

        func setTypingIndicators(enabled: Bool) async throws {
            try await fake.setTypingIndicators(enabled: enabled)
        }

        func blockUser(userId: String) async throws {
            try await fake.blockUser(userId: userId)
        }

        func unblockUser(userId: String) async throws {
            try await fake.unblockUser(userId: userId)
        }

        func setChatMuted(chatId: String, mutedUntilMs: UInt64) async throws {
            try await fake.setChatMuted(chatId: chatId, mutedUntilMs: mutedUntilMs)
        }

        func setChatPinned(chatId: String, pinned: Bool) async throws {
            try await fake.setChatPinned(chatId: chatId, pinned: pinned)
        }

        func setChatArchived(chatId: String, archived: Bool) async throws {
            try await fake.setChatArchived(chatId: chatId, archived: archived)
        }

        func reportUser(userId: String, reason: ReportReason, note: String?, messageIds: [String]) async throws
            -> String
        {
            try await fake.reportUser(userId: userId, reason: reason, note: note, messageIds: messageIds)
        }

        func rotateRecoveryCode() async throws -> RecoveryRotation {
            try await fake.rotateRecoveryCode()
        }

        func deleteAccount() async throws -> [String] {
            if let deleteAccountError { throw deleteAccountError }
            return try await fake.deleteAccount()
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

    private let session = Session(userId: "user-alex", deviceId: "device-1", displayName: "Alex")

    private func makeDefaults() -> UserDefaults {
        let suite = "gim-tests-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suite) }
        return UserDefaults(suiteName: suite)!
    }

    /// The keep server is off by default here, so configs compare without one; the keep server tests set it.
    @MainActor
    private func makeModel(
        factory: ClientFactory, defaults: UserDefaults, bundledServerUrl: String? = nil,
        bundledKeepServerUrl: String? = KeepServer.offValue, hooks: MemoryHooks = MemoryHooks()
    ) -> AppModel {
        AppModel(
            factory: factory, defaults: defaults, bundledServerUrl: bundledServerUrl,
            bundledKeepServerUrl: bundledKeepServerUrl
        ) { hooks }
    }

    /// Runs the create flow: display name `Alex` and the recovery kit ending check.
    @MainActor
    private func register(_ onboarding: OnboardingViewModel) async throws {
        onboarding.choose(.createIdentity)
        let create = try XCTUnwrap(onboarding.createIdentity)
        create.displayName = "Alex"
        await create.submit()
        guard case .recoveryKit(let recovery) = onboarding.stage else {
            return XCTFail("expected the recovery kit, got \(String(describing: onboarding.stage))")
        }
        recovery.continueToCheck()
        recovery.endingInput = CoreRecoveryKitFunctions().recoveryKeyEnding(recoveryCode: recovery.groupedCode)
        recovery.confirm()
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
            XCTAssertEqual(sendStates, [.failed(reason: "rejected (403 not_member)", cause: .rejected)])
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
        XCTAssertEqual(model.onboarding?.serverUrl, "https://hub.g.im")

        let onboarding = try XCTUnwrap(model.onboarding)
        onboarding.serverUrl = "http://192.168.1.20:8080"
        try await register(onboarding)

        guard case .ready = model.phase else { return XCTFail("expected ready, got \(model.phase)") }
        XCTAssertEqual(factory.configs, [ClientConfig(serverUrl: "http://192.168.1.20:8080")])
        XCTAssertEqual(model.session?.displayName, "Alex")
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
    func testSuspensionKeepsTheAppSignedInWithoutWiping() async throws {
        let session = session
        let hooks = MemoryHooks()
        let client = FakeGimClient(session: session)
        await client.simulateSuspension(hubId: FakeGimClient.hubId(forUrl: "https://gim.example.eu"))
        let defaults = makeDefaults()
        defaults.set("https://gim.example.eu", forKey: AppModel.serverUrlKey)
        let model = makeModel(factory: ClientFactory(client), defaults: defaults, hooks: hooks)

        await model.start()
        await model.scenePhaseChanged(.active)
        await model.refreshSession()
        let devices = DevicesViewModel(client: client)
        await devices.load()

        XCTAssertEqual(devices.errorMessage, ErrorPresenter.message(for: GimError.UserSuspended(hubId: "")))
        guard case .ready = model.phase else { return XCTFail("expected ready, got \(model.phase)") }
        XCTAssertEqual(model.session, session)
        XCTAssertNil(model.launchError)
        XCTAssertEqual(hooks.wipeCount, 0)
        let kept = try await client.session()
        XCTAssertEqual(kept, session, "not signed out")
    }

    @MainActor
    func testNotAdmittedKeepsTheAppSignedInWithoutWiping() async throws {
        let session = session
        let hooks = MemoryHooks()
        let client = FakeGimClient(session: session)
        await client.simulateNotAdmitted(hubId: FakeGimClient.hubId(forUrl: FakeGimClient.defaultHomeHubUrl))
        let defaults = makeDefaults()
        defaults.set("https://gim.example.eu", forKey: AppModel.serverUrlKey)
        let model = makeModel(factory: ClientFactory(client), defaults: defaults, hooks: hooks)

        await model.start()
        await model.scenePhaseChanged(.active)
        await model.refreshSession()
        let devices = DevicesViewModel(client: client)
        await devices.load()

        XCTAssertEqual(devices.errorMessage, "This server doesn't accept your account.")
        guard case .ready = model.phase else { return XCTFail("expected ready, got \(model.phase)") }
        XCTAssertEqual(model.session, session)
        XCTAssertNil(model.launchError)
        XCTAssertEqual(hooks.wipeCount, 0)
        let kept = try await client.session()
        XCTAssertEqual(kept, session, "not signed out")
    }

    @MainActor
    func testHeldSyncStaysStoppedWhileActiveUntilReleased() async throws {
        let session = session
        let scheduler = ManualFakeScheduler()
        let client = FakeGimClient(scheduler: scheduler, session: session)
        let defaults = makeDefaults()
        defaults.set("https://gim.example.eu", forKey: AppModel.serverUrlKey)
        let model = makeModel(factory: ClientFactory(client), defaults: defaults)
        await model.start()
        var states = try await ListenerBridge.connectionState(client).makeAsyncIterator()
        _ = await states.next()
        await model.scenePhaseChanged(.active)
        let connecting = await states.next()
        XCTAssertEqual(connecting, .connecting)
        // A started sync schedules its connection steps.
        let scheduled = scheduler.pendingCount

        await model.holdSync(true)
        XCTAssertTrue(model.isSyncHeld)
        let held = await states.next()
        XCTAssertEqual(held, .offline)
        await model.scenePhaseChanged(.background)
        await model.scenePhaseChanged(.active)
        XCTAssertEqual(scheduler.pendingCount, scheduled, "no sync started while held")

        await model.holdSync(false)
        XCTAssertFalse(model.isSyncHeld)
        let resumed = await states.next()
        XCTAssertEqual(resumed, .connecting)
        XCTAssertGreaterThan(scheduler.pendingCount, scheduled)
    }

    @MainActor
    func testHeldSyncSurvivesARelaunch() async throws {
        let session = session
        let defaults = makeDefaults()
        defaults.set("https://gim.example.eu", forKey: AppModel.serverUrlKey)
        let first = makeModel(factory: ClientFactory(FakeGimClient(session: session)), defaults: defaults)
        await first.start()
        await first.holdSync(true)

        // A relaunched process: a new model and client on the same defaults.
        let scheduler = ManualFakeScheduler()
        let client = FakeGimClient(scheduler: scheduler, session: session)
        let model = makeModel(factory: ClientFactory(client), defaults: defaults)
        XCTAssertTrue(model.isSyncHeld)
        await model.start()
        let scheduled = scheduler.pendingCount
        await model.scenePhaseChanged(.active)
        await Task.yield()
        XCTAssertEqual(scheduler.pendingCount, scheduled, "no sync started on activation while held")
    }

    @MainActor
    func testReleasedSyncStaysReleasedAfterARelaunch() async throws {
        let session = session
        let defaults = makeDefaults()
        defaults.set("https://gim.example.eu", forKey: AppModel.serverUrlKey)
        let first = makeModel(factory: ClientFactory(FakeGimClient(session: session)), defaults: defaults)
        await first.start()
        await first.holdSync(true)
        await first.holdSync(false)

        let scheduler = ManualFakeScheduler()
        let client = FakeGimClient(scheduler: scheduler, session: session)
        let model = makeModel(factory: ClientFactory(client), defaults: defaults)
        XCTAssertFalse(model.isSyncHeld)
        await model.start()
        var states = try await ListenerBridge.connectionState(client).makeAsyncIterator()
        _ = await states.next()
        await model.scenePhaseChanged(.active)
        let connecting = await states.next()
        XCTAssertEqual(connecting, .connecting)
    }

    @MainActor
    func testSignedInHookRunsAtLaunchAndAfterEachSignIn() async throws {
        let launched = FakeGimClient(session: session)
        let factory = ClientFactory(launched, FakeGimClient())
        let defaults = makeDefaults()
        defaults.set("https://gim.example.eu", forKey: AppModel.serverUrlKey)
        var signedIn: [ObjectIdentifier] = []
        let hooks = MemoryHooks()
        let model = AppModel(
            factory: factory, defaults: defaults, bundledServerUrl: nil, makeHooks: { hooks },
            signedIn: { signedIn.append(ObjectIdentifier($0)) })

        await model.start()
        for _ in 0..<100 where signedIn.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(signedIn, [ObjectIdentifier(launched)])

        _ = await model.signOut()
        try await register(try XCTUnwrap(model.onboarding))
        for _ in 0..<100 where signedIn.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(signedIn.count, 2)
        XCTAssertNotEqual(signedIn.last, ObjectIdentifier(launched))
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
    func testClientsGetTheBuiltInKeepServerByDefault() async {
        let factory = ClientFactory(FakeGimClient(session: session))
        let defaults = makeDefaults()
        defaults.set("https://gim.example.eu", forKey: AppModel.serverUrlKey)
        let model = makeModel(factory: factory, defaults: defaults, bundledKeepServerUrl: nil)

        await model.start()

        XCTAssertEqual(
            factory.configs, [ClientConfig(serverUrl: "https://gim.example.eu", keepServerUrl: "https://keep.g.im")])
        XCTAssertEqual(model.keepServerUrl, "https://keep.g.im")
    }

    @MainActor
    func testTheStoredKeepServerChoiceWinsAtLaunchAndInOnboarding() async throws {
        let factory = ClientFactory(FakeGimClient())
        let defaults = makeDefaults()
        KeepServer.store(.custom("https://keep.example.eu"), in: defaults)
        let model = makeModel(factory: factory, defaults: defaults, bundledKeepServerUrl: "https://bundled.example.eu")
        await model.start()

        try await register(try XCTUnwrap(model.onboarding))

        XCTAssertEqual(factory.configs.map(\.keepServerUrl), ["https://keep.example.eu"])
        XCTAssertEqual(model.keepServerUrl, "https://keep.example.eu")
    }

    @MainActor
    func testATurnedOffKeepServerGivesClientsNone() async {
        let factory = ClientFactory(FakeGimClient(session: session))
        let defaults = makeDefaults()
        defaults.set("https://gim.example.eu", forKey: AppModel.serverUrlKey)
        KeepServer.store(.off, in: defaults)
        let model = makeModel(factory: factory, defaults: defaults, bundledKeepServerUrl: nil)

        await model.start()

        XCTAssertEqual(factory.configs, [ClientConfig(serverUrl: "https://gim.example.eu")])
        XCTAssertNil(model.keepServerUrl)
    }

    @MainActor
    func testSignOutForgetsTheKeepServerChoice() async throws {
        let factory = ClientFactory(FakeGimClient(session: session), FakeGimClient())
        let defaults = makeDefaults()
        defaults.set("https://gim.example.eu", forKey: AppModel.serverUrlKey)
        KeepServer.store(.custom("https://keep.example.eu"), in: defaults)
        let model = makeModel(factory: factory, defaults: defaults, bundledKeepServerUrl: nil)
        await model.start()

        _ = await model.signOut()

        XCTAssertNil(defaults.object(forKey: KeepServer.settingKey))
        XCTAssertNil(model.keepServerUrl)
        try await register(try XCTUnwrap(model.onboarding))
        XCTAssertEqual(
            factory.configs.map(\.keepServerUrl), ["https://keep.example.eu", "https://keep.g.im"],
            "the next account starts with the default keep server")
    }

    @MainActor
    func testTheKeepServerScreenKnowsTheDefaultAndTheRunningClientsServer() async {
        let factory = ClientFactory(FakeGimClient(session: session))
        let defaults = makeDefaults()
        defaults.set("https://gim.example.eu", forKey: AppModel.serverUrlKey)
        KeepServer.store(.off, in: defaults)
        let model = makeModel(factory: factory, defaults: defaults, bundledKeepServerUrl: "https://bundled.example.eu")
        await model.start()

        let keepServer = model.makeKeepServerViewModel()

        XCTAssertEqual(keepServer.defaultUrl, "https://bundled.example.eu")
        XCTAssertNil(keepServer.activeUrl)
        XCTAssertFalse(keepServer.isOn)
        keepServer.resetToDefault()
        XCTAssertTrue(keepServer.needsRestart)
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
    func testDeleteAccountWipesAndReturnsToOnboarding() async throws {
        let hooks = MemoryHooks()
        let fake = FakeGimClient(session: session)
        let factory = ClientFactory(fake, FakeGimClient())
        let defaults = makeDefaults()
        defaults.set("https://gim.example.eu", forKey: AppModel.serverUrlKey)
        let model = makeModel(factory: factory, defaults: defaults, hooks: hooks)
        await model.start()

        let error = await model.deleteAccount()

        XCTAssertNil(error)
        let remaining = try await fake.session()
        XCTAssertNil(remaining, "the client deleted the account")
        XCTAssertEqual(hooks.wipeCount, 1)
        XCTAssertNil(model.session)
        guard case .onboarding = model.phase else { return XCTFail("expected onboarding, got \(model.phase)") }
        let onboarding = try XCTUnwrap(model.onboarding)
        XCTAssertEqual(onboarding.serverUrl, "https://gim.example.eu")
        try await register(onboarding)
        XCTAssertEqual(factory.configs.count, 2, "a new client is created after deleting the account")
    }

    @MainActor
    func testFailedDeleteAccountStaysSignedInWithoutWiping() async {
        let hooks = MemoryHooks()
        let defaults = makeDefaults()
        defaults.set("https://gim.example.eu", forKey: AppModel.serverUrlKey)
        let client = StubClient(FakeGimClient(session: session), deleteAccountError: .Network(reason: "offline"))
        let model = makeModel(factory: ClientFactory(client), defaults: defaults, hooks: hooks)
        await model.start()

        let error = await model.deleteAccount()

        XCTAssertNotNil(error)
        XCTAssertEqual(hooks.wipeCount, 0)
        XCTAssertNotNil(model.session)
        guard case .ready = model.phase else { return XCTFail("expected ready, got \(model.phase)") }
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
    func testRefreshSessionPicksUpAChangedName() async throws {
        let alex = Session(userId: "user-alex", deviceId: "device-1", displayName: "Alex")
        let client = FakeGimClient(session: alex)
        let defaults = makeDefaults()
        defaults.set("https://gim.example.eu", forKey: AppModel.serverUrlKey)
        let model = makeModel(factory: ClientFactory(client), defaults: defaults)
        await model.start()
        XCTAssertEqual(model.session?.displayName, "Alex")

        try await client.setDisplayName(name: "Alex M.")
        await model.refreshSession()

        XCTAssertEqual(model.session?.displayName, "Alex M.")
    }
}
