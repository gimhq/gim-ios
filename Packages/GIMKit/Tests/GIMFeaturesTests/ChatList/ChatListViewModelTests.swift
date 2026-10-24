import Foundation
import GIMClientKit
import GIMFeatures
import XCTest

final class ChatListViewModelTests: XCTestCase {
    @MainActor
    private func startedViewModel(_ client: any GimClientAPI) async -> ChatListViewModel {
        let viewModel = ChatListViewModel(client: client, dateFormatter: makeFormatter())
        XCTAssertTrue(viewModel.isLoading)
        viewModel.start()
        await eventually { viewModel.rows.count == 2 }
        return viewModel
    }

    @MainActor
    func testInitialResetMapsRows() async {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client)

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.rows.map(\.id), [FakeGimClient.demoGroupChatId, FakeGimClient.demoDirectChatId])
        let group = viewModel.rows[0]
        XCTAssertEqual(group.title, "Aegean Crew")
        XCTAssertEqual(group.preview, "Nikos Papadopoulos: Me, grilled octopus 🐙")
        XCTAssertEqual(group.unreadText, "3")
        XCTAssertNotNil(group.time)
        let direct = viewModel.rows[1]
        XCTAssertEqual(direct.title, "Sofia Marin")
        XCTAssertEqual(direct.unreadText, "2")
        await eventually { viewModel.connectionState == .connected }
    }

    @MainActor
    func testNewMessageReordersViaRemoveAndInsert() async throws {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client)

        try await client.receiveText(chatId: FakeGimClient.demoDirectChatId, from: "user-sofia", body: "On my way")

        await eventually { viewModel.rows.first?.id == FakeGimClient.demoDirectChatId }
        XCTAssertEqual(viewModel.rows.map(\.id), [FakeGimClient.demoDirectChatId, FakeGimClient.demoGroupChatId])
        XCTAssertEqual(viewModel.rows[0].preview, "On my way")
        XCTAssertEqual(viewModel.rows[0].unreadText, "3")
    }

    @MainActor
    func testUpdateInPlaceAndDeletedPreview() async throws {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client)

        try await client.markRead(chatId: FakeGimClient.demoGroupChatId, upToMessageId: "msg-crew-5")
        await eventually { viewModel.rows[0].unreadText == nil }

        let id = try await client.sendText(chatId: FakeGimClient.demoGroupChatId, body: "Wrong chat", replyTo: nil)
        try await client.deleteMessage(chatId: FakeGimClient.demoGroupChatId, messageId: id)
        await eventually { viewModel.rows[0].preview == "Alex Morgan: Message deleted" }
    }

    @MainActor
    func testNewChatIsInserted() async throws {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client)

        let chatId = try await client.createGroupChat(name: "Regatta", memberUserIds: ["user-sofia", "user-luca"])

        await eventually { viewModel.rows.count == 3 }
        XCTAssertEqual(viewModel.rows.first?.id, chatId)
        XCTAssertNil(viewModel.rows.first?.preview)
    }

    @MainActor
    func testConnectionStateFollowsClient() async {
        let (client, scheduler) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client)
        await eventually { viewModel.connectionState == .connected }

        client.setNetworkReachable(reachable: false)
        await eventually { viewModel.connectionState == .offline }

        await client.simulateNetworkReachable(true)
        await eventually { viewModel.connectionState == .connecting }
        await scheduler.advance(by: .milliseconds(500))
        await eventually { viewModel.connectionState == .syncing }
        await scheduler.runUntilIdle()
        await eventually { viewModel.connectionState == .connected }
    }

    @MainActor
    func testStopUnsubscribes() async throws {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client)

        viewModel.stop()
        await settle()
        try await client.markRead(chatId: FakeGimClient.demoGroupChatId, upToMessageId: "msg-crew-5")
        await settle()

        XCTAssertEqual(viewModel.rows[0].unreadText, "3")
    }

    @MainActor
    func testRefreshResubscribesWithReset() async throws {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client)
        viewModel.stop()
        await settle()
        try await client.markRead(chatId: FakeGimClient.demoGroupChatId, upToMessageId: "msg-crew-5")

        viewModel.refresh()

        await eventually { viewModel.rows[0].unreadText == nil }
        try await client.receiveText(chatId: FakeGimClient.demoGroupChatId, from: "user-luca", body: "Anchor's up")
        await eventually { viewModel.rows[0].preview == "Luca Bianchi: Anchor's up" }
    }

    @MainActor
    func testSubscribeFailureShowsError() async {
        let client = FailingChatListClient()
        let viewModel = ChatListViewModel(client: client, dateFormatter: makeFormatter())

        viewModel.start()

        await eventually { viewModel.errorMessage != nil }
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.errorMessage, ErrorPresenter.message(for: GimError.NotRegistered))
    }

    @MainActor
    func testSubtitleFollowsChatStateAfterOwnLeave() async throws {
        let (client, scheduler) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client)
        let groupId = FakeGimClient.demoGroupChatId
        XCTAssertEqual(
            viewModel.subtitle(for: try row(groupId, viewModel)), "Nikos Papadopoulos: Me, grilled octopus 🐙")

        try await client.leaveChat(chatId: groupId)

        await eventually { (try? self.row(groupId, viewModel).state) == .leaving }
        XCTAssertEqual(viewModel.subtitle(for: try row(groupId, viewModel)), "Leaving…")
        let direct = try row(FakeGimClient.demoDirectChatId, viewModel)
        XCTAssertEqual(viewModel.subtitle(for: direct), direct.preview)
        await settle()
        await scheduler.advance(by: FakeGimClient.leaveCommitDelay)
        await eventually { (try? self.row(groupId, viewModel).state) == .left }
        await eventually { (try? viewModel.subtitle(for: self.row(groupId, viewModel))) == "You left" }
        // A left chat stays in the list with its history.
        XCTAssertEqual(Set(viewModel.rows.map(\.id)), [groupId, FakeGimClient.demoDirectChatId])
    }

    @MainActor
    func testSubtitleOfChatTheUserWasRemovedFrom() async throws {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client)
        let groupId = FakeGimClient.demoGroupChatId

        try await client.simulateRemoval(chatId: groupId, by: "user-nikos")

        await eventually { (try? viewModel.subtitle(for: self.row(groupId, viewModel))) == "You were removed" }
        XCTAssertEqual(try row(groupId, viewModel).state, .left)
    }

    @MainActor
    func testLeftSubtitleWithoutOwnMembershipChange() async throws {
        let summary = ChatSummary(
            chatId: "h/g1", kind: .group, name: "Old crew", avatar: nil, lastMessage: nil, unreadCount: 0,
            updatedAtMs: 0, memberCount: 2, state: .left)
        let viewModel = ChatListViewModel(client: FakeGimClient(), dateFormatter: makeFormatter())

        XCTAssertEqual(viewModel.subtitle(for: ChatRow(summary: summary, dateFormatter: makeFormatter())), "Left")
        var leaving = summary
        leaving.state = .leaving
        XCTAssertEqual(viewModel.subtitle(for: ChatRow(summary: leaving, dateFormatter: makeFormatter())), "Leaving…")
    }

    @MainActor
    func testSubtitleKindFollowsChatStateAfterOwnLeave() async throws {
        let (client, scheduler) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client)
        let groupId = FakeGimClient.demoGroupChatId
        XCTAssertEqual(
            viewModel.subtitleKind(for: try row(groupId, viewModel)),
            .preview("Nikos Papadopoulos: Me, grilled octopus 🐙"))

        try await client.leaveChat(chatId: groupId)

        await eventually { (try? self.row(groupId, viewModel).state) == .leaving }
        XCTAssertEqual(viewModel.subtitleKind(for: try row(groupId, viewModel)), .leaving)
        await settle()
        await scheduler.advance(by: FakeGimClient.leaveCommitDelay)
        await eventually { (try? viewModel.subtitleKind(for: self.row(groupId, viewModel))) == .left }
    }

    @MainActor
    func testSubtitleKindOfChatTheUserWasRemovedFrom() async throws {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client)
        let groupId = FakeGimClient.demoGroupChatId

        try await client.simulateRemoval(chatId: groupId, by: "user-nikos")

        await eventually { (try? viewModel.subtitleKind(for: self.row(groupId, viewModel))) == .removed }
    }

    @MainActor
    func testSubtitleKindWithoutPreviewOrOwnMembershipChange() async throws {
        let summary = ChatSummary(
            chatId: "h/g1", kind: .group, name: "Old crew", avatar: nil, lastMessage: nil, unreadCount: 0,
            updatedAtMs: 0, memberCount: 2, state: .active)
        let viewModel = ChatListViewModel(client: FakeGimClient(), dateFormatter: makeFormatter())
        let active = ChatRow(summary: summary, dateFormatter: makeFormatter())

        XCTAssertEqual(viewModel.subtitleKind(for: active), .noMessages)
        XCTAssertEqual(viewModel.subtitle(for: active), "No messages yet")
        var left = summary
        left.state = .left
        XCTAssertEqual(
            viewModel.subtitleKind(for: ChatRow(summary: left, dateFormatter: makeFormatter())), .leftUnknown)
    }

    @MainActor
    func testLastMessageStatusIsNilForForeignLastMessages() async throws {
        let (client, _) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client)

        for row in viewModel.rows {
            XCTAssertFalse(row.lastMessageIsOwn, row.id)
            XCTAssertNil(viewModel.lastMessageStatus(for: row), row.id)
        }
        await settle()
        XCTAssertNil(viewModel.lastMessageStatus(for: try row(FakeGimClient.demoDirectChatId, viewModel)))
    }

    @MainActor
    func testLastMessageStatusFollowsOwnMessageProgression() async throws {
        let (client, scheduler) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client)
        let chatId = FakeGimClient.demoDirectChatId

        _ = try await client.sendText(chatId: chatId, body: "Ready", replyTo: nil)

        await eventually { (try? self.row(chatId, viewModel).lastMessageIsOwn) == true }
        await eventually { self.lastMessageStatus(chatId, viewModel) == .sending }
        await scheduler.advance(by: .milliseconds(300))
        await eventually { self.lastMessageStatus(chatId, viewModel) == .sent }
        await scheduler.advance(by: .milliseconds(700))
        await eventually { self.lastMessageStatus(chatId, viewModel) == .delivered }
        await scheduler.advance(by: .milliseconds(1500))
        await eventually { self.lastMessageStatus(chatId, viewModel) == .read }
        XCTAssertNil(viewModel.lastMessageStatus(for: try row(FakeGimClient.demoGroupChatId, viewModel)))

        try await client.receiveText(chatId: chatId, from: "user-sofia", body: "On my way")

        await eventually { (try? self.row(chatId, viewModel).lastMessageIsOwn) == false }
        XCTAssertNil(lastMessageStatus(chatId, viewModel))
    }

    @MainActor
    func testLastMessageStatusIsNilOnceTheChatIsLeft() async throws {
        let (client, scheduler) = await connected(makeDemoClient())
        let viewModel = await startedViewModel(client)
        let chatId = FakeGimClient.demoGroupChatId
        _ = try await client.sendText(chatId: chatId, body: "Leaving now", replyTo: nil)
        await scheduler.runUntilIdle()
        await eventually { self.lastMessageStatus(chatId, viewModel) == .read }

        try await client.leaveChat(chatId: chatId)

        await eventually { (try? self.row(chatId, viewModel).state) == .leaving }
        XCTAssertNil(lastMessageStatus(chatId, viewModel))
        await settle()
        await scheduler.advance(by: FakeGimClient.leaveCommitDelay)
        await eventually { (try? self.row(chatId, viewModel).state) == .left }
        let left = try row(chatId, viewModel)
        XCTAssertTrue(left.lastMessageIsOwn)
        XCTAssertNil(viewModel.lastMessageStatus(for: left))
    }

    @MainActor
    func testStopClosesLastMessageStatusLookups() async throws {
        let (fake, scheduler) = await connected(makeDemoClient())
        let client = TimelineCountingClient(fake)
        let viewModel = await startedViewModel(client)
        let chatId = FakeGimClient.demoDirectChatId
        _ = try await fake.sendText(chatId: chatId, body: "Ready", replyTo: nil)
        await eventually { self.lastMessageStatus(chatId, viewModel) == .sending }
        XCTAssertEqual(client.openTimelineChatIds, [chatId])

        viewModel.stop()

        await eventually { client.openTimelineChatIds.isEmpty }
        await scheduler.runUntilIdle()
        await settle()
        XCTAssertEqual(lastMessageStatus(chatId, viewModel), .sending)
    }

    @MainActor
    func testLastMessageStatusLookupsAreCappedClosingTheOldestFirst() async throws {
        let (fake, scheduler) = await connected(makeDemoClient())
        let client = TimelineCountingClient(fake)
        let viewModel = await startedViewModel(client)
        let cap = ChatListViewModel.maxStatusLookups
        var chatIds: [String] = []

        for index in 0...cap {
            let chatId = try await fake.createGroupChat(name: "Crew \(index)", memberUserIds: ["user-sofia"])
            _ = try await fake.sendText(chatId: chatId, body: "Ahoy", replyTo: nil)
            await eventually { self.lastMessageStatus(chatId, viewModel) == .sending }
            chatIds.append(chatId)
        }

        await eventually { client.openTimelineChatIds.count == cap }
        XCTAssertEqual(client.openTimelineChatIds, Array(chatIds.dropFirst()), "the oldest lookup closed first")
        XCTAssertNil(lastMessageStatus(chatIds[0], viewModel))
        await scheduler.runUntilIdle()
        await eventually { self.lastMessageStatus(chatIds[1], viewModel) == .read }
        XCTAssertNil(lastMessageStatus(chatIds[0], viewModel), "a capped chat never shows a made-up state")
        XCTAssertEqual(client.openTimelineChatIds.count, cap)
        XCTAssertTrue(chatIds.dropFirst().allSatisfy { self.lastMessageStatus($0, viewModel) == .read })
    }

    @MainActor
    private func lastMessageStatus(_ chatId: String, _ viewModel: ChatListViewModel) -> MessageStatus? {
        (try? row(chatId, viewModel)).flatMap { viewModel.lastMessageStatus(for: $0) }
    }

    @MainActor
    private func row(_ chatId: String, _ viewModel: ChatListViewModel) throws -> ChatRow {
        try XCTUnwrap(viewModel.rows.first { $0.id == chatId })
    }
}

/// Forwards to a `FakeGimClient` and lists the chats with an open timeline subscription, oldest first.
private final class TimelineCountingClient: GimClientAPI, @unchecked Sendable {
    private let fake: FakeGimClient
    private let lock = NSLock()
    private var open: [String] = []

    init(_ fake: FakeGimClient) {
        self.fake = fake
    }

    var openTimelineChatIds: [String] { lock.withLock { open } }

    func timeline(chatId: String) async throws -> any Timeline {
        CountingTimeline(try await fake.timeline(chatId: chatId), client: self)
    }

    fileprivate func opened(_ chatId: String) {
        lock.withLock { open.append(chatId) }
    }

    fileprivate func closed(_ chatId: String) {
        lock.withLock { open.firstIndex(of: chatId).map { open.remove(at: $0) } }
    }

    func session() async throws -> Session? { try await fake.session() }
    func userId() -> String? { fake.userId() }
    func localStateReset() -> Bool { fake.localStateReset() }
    func createIdentity(displayName: String) async throws -> String {
        try await fake.createIdentity(displayName: displayName)
    }
    func restoreFromRecovery(userId: String, recoveryCode: String, revokeOthers: Bool) async throws {
        try await fake.restoreFromRecovery(userId: userId, recoveryCode: recoveryCode, revokeOthers: revokeOthers)
    }
    func startLink(hubs: [String]) throws -> any LinkSession { try fake.startLink(hubs: hubs) }
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
    func signOut() async throws { try await fake.signOut() }
    func startSync() async throws { try await fake.startSync() }
    func stopSync() async throws { try await fake.stopSync() }
    func setNetworkReachable(reachable: Bool) { fake.setNetworkReachable(reachable: reachable) }
    func setLocalTimeZone(zone: (any LocalTimeZone)?) { fake.setLocalTimeZone(zone: zone) }
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
    func stopTyping(chatId: String) async throws { try await fake.stopTyping(chatId: chatId) }
    func fetchMedia(chatId: String, messageId: String, destPath: String) async throws -> String {
        try await fake.fetchMedia(chatId: chatId, messageId: messageId, destPath: destPath)
    }
    func fetchThumbnail(chatId: String, messageId: String, destPath: String) async throws -> String? {
        try await fake.fetchThumbnail(chatId: chatId, messageId: messageId, destPath: destPath)
    }
    func chatList(listener: any ChatListListener) async throws -> TaskHandle {
        try await fake.chatList(listener: listener)
    }
    func connectionState(listener: any ConnectionStateListener) async throws -> TaskHandle {
        try await fake.connectionState(listener: listener)
    }
    func typing(chatId: String, listener: any TypingListener) async throws -> TaskHandle {
        try await fake.typing(chatId: chatId, listener: listener)
    }
    func hubs() async throws -> [HubInfo] { try await fake.hubs() }
    func addHub(url: String) async throws -> HubInfo { try await fake.addHub(url: url) }
    func removeHub(hubId: String, confirmOwnedGroups: Bool) async throws {
        try await fake.removeHub(hubId: hubId, confirmOwnedGroups: confirmOwnedGroups)
    }
    func setPrimaryHub(hubId: String) async throws { try await fake.setPrimaryHub(hubId: hubId) }
    func hubList(listener: any HubListListener) async throws -> TaskHandle {
        try await fake.hubList(listener: listener)
    }
    func registerPush(registration: PushRegistration) async throws {
        try await fake.registerPush(registration: registration)
    }
    func unregisterPush() async throws { try await fake.unregisterPush() }
    func processPush(payload: String) async throws -> NotificationContent {
        try await fake.processPush(payload: payload)
    }
    func ownProfile() async throws -> UserProfile? { try await fake.ownProfile() }
    func setAvatar(filePath: String, mime: String) async throws {
        try await fake.setAvatar(filePath: filePath, mime: mime)
    }
    func removeAvatar() async throws { try await fake.removeAvatar() }
    func fetchUserAvatar(userId: String, destPath: String) async throws -> String {
        try await fake.fetchUserAvatar(userId: userId, destPath: destPath)
    }
    func fetchChatAvatar(chatId: String, destPath: String) async throws -> String {
        try await fake.fetchChatAvatar(chatId: chatId, destPath: destPath)
    }
    func privacy() async throws -> PrivacySettings { try await fake.privacy() }
    func setReadReceipts(enabled: Bool) async throws { try await fake.setReadReceipts(enabled: enabled) }
    func setTypingIndicators(enabled: Bool) async throws { try await fake.setTypingIndicators(enabled: enabled) }
    func blockUser(userId: String) async throws { try await fake.blockUser(userId: userId) }
    func unblockUser(userId: String) async throws { try await fake.unblockUser(userId: userId) }
    func setChatMuted(chatId: String, mutedUntilMs: UInt64) async throws {
        try await fake.setChatMuted(chatId: chatId, mutedUntilMs: mutedUntilMs)
    }
    func setChatPinned(chatId: String, pinned: Bool) async throws {
        try await fake.setChatPinned(chatId: chatId, pinned: pinned)
    }
    func setChatArchived(chatId: String, archived: Bool) async throws {
        try await fake.setChatArchived(chatId: chatId, archived: archived)
    }
    func reportUser(userId: String, reason: ReportReason, note: String?, messageIds: [String]) async throws -> String {
        try await fake.reportUser(userId: userId, reason: reason, note: note, messageIds: messageIds)
    }
    func rotateRecoveryCode() async throws -> RecoveryRotation { try await fake.rotateRecoveryCode() }
    func deleteAccount() async throws -> [String] { try await fake.deleteAccount() }
}

/// Timeline whose subscriptions are counted by `TimelineCountingClient`.
private final class CountingTimeline: Timeline {
    private let base: any Timeline
    private let client: TimelineCountingClient

    init(_ base: any Timeline, client: TimelineCountingClient) {
        self.base = base
        self.client = client
    }

    func chatId() -> String { base.chatId() }

    func addListener(listener: any TimelineListener) async -> TaskHandle {
        let handle = await base.addListener(listener: listener)
        let chatId = base.chatId()
        let client = client
        client.opened(chatId)
        return TaskHandle {
            handle.cancel()
            client.closed(chatId)
        }
    }

    func paginateBackwards(count: UInt16) async throws -> Bool { try await base.paginateBackwards(count: count) }
    func chatState() -> ChatState? { base.chatState() }
}

/// Client whose chat list listener fails; the connection state listener works.
private final class FailingChatListClient: GimClientAPI {
    private let base = FakeGimClient()

    func session() async throws -> Session? { nil }
    func userId() -> String? { nil }
    func localStateReset() -> Bool { false }
    func createIdentity(displayName: String) async throws -> String { throw GimError.NotImplemented }
    func restoreFromRecovery(userId: String, recoveryCode: String, revokeOthers: Bool) async throws {}
    func startLink(hubs: [String]) throws -> any LinkSession { throw GimError.NotImplemented }
    func waitLink(link: any LinkSession) async throws -> String { throw GimError.NotImplemented }
    func confirmLink(accepted: Bool) async throws {}
    func approveLink(qrString: String) async throws -> any PendingApproval { throw GimError.NotRegistered }
    func confirmApproval(approval: any PendingApproval, accepted: Bool) async throws {}
    func devices() async throws -> [DeviceInfo] { throw GimError.NotRegistered }
    func userDevices(userId: String) async throws -> [DeviceInfo] { throw GimError.NotRegistered }
    func revokeDevice(deviceId: String) async throws {}
    func setDisplayName(name: String) async throws {}
    func claimHandle(handle: String) async throws {}
    func releaseHandle() async throws {}
    func signOut() async throws {}
    func startSync() async throws {}
    func stopSync() async throws {}
    func setNetworkReachable(reachable: Bool) {}
    func setLocalTimeZone(zone: (any LocalTimeZone)?) {}
    func findUser(handle: String) async throws -> UserProfile? { nil }
    func createDirectChat(userId: String) async throws -> String { throw GimError.NotRegistered }
    func createGroupChat(name: String, memberUserIds: [String]) async throws -> String {
        throw GimError.NotRegistered
    }
    func chatMembers(chatId: String) async throws -> [UserProfile] { throw GimError.NotRegistered }
    func addMembers(chatId: String, userIds: [String]) async throws {}
    func removeMember(chatId: String, userId: String) async throws {}
    func leaveChat(chatId: String) async throws {}
    func chatState(chatId: String) async throws -> ChatState { .active }
    func setGroupInfo(chatId: String, name: String?, avatarFilePath: String?) async throws {}
    func sendText(chatId: String, body: String, replyTo: String?) async throws -> String {
        throw GimError.NotRegistered
    }
    func sendMedia(
        chatId: String, filePath: String, mime: String, caption: String?, replyTo: String?
    ) async throws -> String {
        throw GimError.NotRegistered
    }
    func editMessage(chatId: String, messageId: String, newBody: String) async throws {}
    func deleteMessage(chatId: String, messageId: String) async throws {}
    func react(chatId: String, messageId: String, emoji: String) async throws {}
    func unreact(chatId: String, messageId: String, emoji: String) async throws {}
    func retrySend(chatId: String, messageId: String) async throws {}
    func cancelSend(chatId: String, messageId: String) async throws {}
    func markRead(chatId: String, upToMessageId: String) async throws {}
    func setTyping(chatId: String, active: Bool) async throws {}
    func stopTyping(chatId: String) async throws {}
    func fetchMedia(chatId: String, messageId: String, destPath: String) async throws -> String {
        throw GimError.NotFound(reason: "media")
    }
    func fetchThumbnail(chatId: String, messageId: String, destPath: String) async throws -> String? { nil }
    func chatList(listener: any ChatListListener) async throws -> TaskHandle { throw GimError.NotRegistered }
    func timeline(chatId: String) async throws -> any Timeline { throw GimError.NotRegistered }
    func connectionState(listener: any ConnectionStateListener) async throws -> TaskHandle {
        try await base.connectionState(listener: listener)
    }
    func typing(chatId: String, listener: any TypingListener) async throws -> TaskHandle {
        throw GimError.NotRegistered
    }

    func hubs() async throws -> [HubInfo] {
        throw GimError.NotRegistered
    }

    func addHub(url: String) async throws -> HubInfo {
        throw GimError.NotRegistered
    }

    func removeHub(hubId: String, confirmOwnedGroups: Bool) async throws {
        throw GimError.NotRegistered
    }

    func setPrimaryHub(hubId: String) async throws {
        throw GimError.NotRegistered
    }

    func hubList(listener: any HubListListener) async throws -> TaskHandle {
        throw GimError.NotRegistered
    }

    func registerPush(registration: PushRegistration) async throws {
        throw GimError.NotRegistered
    }

    func unregisterPush() async throws {
        throw GimError.NotRegistered
    }

    func processPush(payload: String) async throws -> NotificationContent {
        throw GimError.NotRegistered
    }

    func ownProfile() async throws -> UserProfile? {
        throw GimError.NotRegistered
    }

    func setAvatar(filePath: String, mime: String) async throws {
        throw GimError.NotRegistered
    }

    func removeAvatar() async throws {
        throw GimError.NotRegistered
    }

    func fetchUserAvatar(userId: String, destPath: String) async throws -> String {
        throw GimError.NotRegistered
    }

    func fetchChatAvatar(chatId: String, destPath: String) async throws -> String {
        throw GimError.NotRegistered
    }

    func privacy() async throws -> PrivacySettings {
        throw GimError.NotRegistered
    }

    func setReadReceipts(enabled: Bool) async throws {
        throw GimError.NotRegistered
    }

    func setTypingIndicators(enabled: Bool) async throws {
        throw GimError.NotRegistered
    }

    func blockUser(userId: String) async throws {
        throw GimError.NotRegistered
    }

    func unblockUser(userId: String) async throws {
        throw GimError.NotRegistered
    }

    func setChatMuted(chatId: String, mutedUntilMs: UInt64) async throws {
        throw GimError.NotRegistered
    }

    func setChatPinned(chatId: String, pinned: Bool) async throws {
        throw GimError.NotRegistered
    }

    func setChatArchived(chatId: String, archived: Bool) async throws {
        throw GimError.NotRegistered
    }

    func reportUser(userId: String, reason: ReportReason, note: String?, messageIds: [String]) async throws -> String {
        throw GimError.NotRegistered
    }

    func rotateRecoveryCode() async throws -> RecoveryRotation {
        throw GimError.NotRegistered
    }

    func deleteAccount() async throws -> [String] {
        throw GimError.NotRegistered
    }
}
