import Foundation
import XCTest

@testable import GIMClientKit

final class FakeGimClientAccountSafetyTests: XCTestCase {
    private let direct = FakeGimClient.demoDirectChatId
    private let group = FakeGimClient.demoGroupChatId
    private let sofia = "user-sofia"

    private var scheduler = ManualFakeScheduler()
    /// Subscriptions stay alive until the test ends.
    private var handles: [TaskHandle] = []

    override func setUp() {
        super.setUp()
        scheduler = ManualFakeScheduler()
        handles = []
    }

    /// The registered demo client: the group chat first, then the direct chat with Sofia.
    private func makeDemo(synced: Bool = false, mode: ClientMode? = nil) async throws -> FakeGimClient {
        let client = FakeGimClient.demo(
            scheduler: scheduler, dataDirectory: try makeTemporaryDirectory(), autoReply: false, mode: mode)
        if synced {
            try await client.startSync()
            await scheduler.runUntilIdle()
        }
        return client
    }

    private func subscribeChatList(_ client: FakeGimClient) async throws -> Recorder<[ChatListDiff]> {
        let recorder = Recorder<[ChatListDiff]>()
        handles.append(try await client.chatList(listener: recorder))
        return recorder
    }

    private func writeFile(_ name: String, _ contents: String) throws -> String {
        let path = URL(fileURLWithPath: try makeTemporaryDirectory()).appendingPathComponent(name).path
        try Data(contents.utf8).write(to: URL(fileURLWithPath: path))
        return path
    }

    // MARK: - Blocking

    func testBlockingUpdatesThePrivacySettingsAndTheDirectChatRow() async throws {
        let client = try await makeDemo()
        let list = try await subscribeChatList(client)
        XCTAssertEqual(list.items.map(\.chatId), [group, direct])
        XCTAssertEqual(list.items.map(\.blocked), [false, false])
        list.clear()

        try await client.blockUser(userId: sofia)

        let privacy = try await client.privacy()
        XCTAssertEqual(privacy.blockedUserIds, [sofia])
        guard list.events.count == 1, list.events[0].count == 1, case .set(1, let row) = list.events[0][0] else {
            return XCTFail("Expected a row update, got \(list.events)")
        }
        XCTAssertEqual(row.chatId, direct)
        XCTAssertTrue(row.blocked)
        XCTAssertFalse(list.items[0].blocked, "a group with the blocked user is not marked")

        try await client.unblockUser(userId: sofia)
        let unblocked = try await client.privacy()
        XCTAssertEqual(unblocked.blockedUserIds, [])
        XCTAssertFalse(list.items[1].blocked)
    }

    func testBlockingRefusesTheOwnUserAndNeedsASession() async throws {
        let client = try await makeDemo()
        await assertThrows(.InvalidInput(reason: "cannot block yourself")) {
            try await client.blockUser(userId: FakeGimClient.demoSelfId)
        }
        let signedOut = FakeGimClient(dataDirectory: try makeTemporaryDirectory())
        await assertThrows(.NotRegistered) { try await signedOut.blockUser(userId: self.sofia) }
    }

    func testBlockedUsersCannotBeAddedAndTheirMessagesAreDropped() async throws {
        let client = try await makeDemo()
        try await client.blockUser(userId: sofia)
        let blocked = GimError.InvalidInput(reason: "user-sofia is blocked; unblock them first")

        await assertThrows(blocked) { try await client.createDirectChat(userId: self.sofia) }
        await assertThrows(blocked) {
            try await client.createGroupChat(name: "Sail", memberUserIds: ["user-luca", self.sofia])
        }
        let other = try await client.createGroupChat(name: "Sail", memberUserIds: ["user-luca"])
        await assertThrows(blocked) { try await client.addMembers(chatId: other, userIds: [self.sofia]) }

        let list = try await subscribeChatList(client)
        list.clear()
        try await client.receiveText(chatId: direct, from: sofia, body: "Hello?")
        try await client.setPeerTyping(chatId: direct, userId: sofia, active: true)
        XCTAssertEqual(list.events.count, 0, "messages of a blocked user are dropped")

        // gim-core does not refuse sends to a blocked user's chat.
        _ = try await client.sendText(chatId: direct, body: "Bye", replyTo: nil)

        try await client.unblockUser(userId: sofia)
        try await client.receiveText(chatId: direct, from: sofia, body: "Hello again")
        XCTAssertEqual(list.items.first { $0.chatId == direct }?.lastMessage?.text, "Hello again")
    }

    // MARK: - Privacy switches

    func testPrivacyDefaultsAndSwitches() async throws {
        let client = try await makeDemo()
        let defaults = try await client.privacy()
        XCTAssertEqual(defaults, PrivacySettings(readReceipts: true, typingIndicators: true, blockedUserIds: []))

        try await client.setReadReceipts(enabled: false)
        try await client.setTypingIndicators(enabled: false)
        let off = try await client.privacy()
        XCTAssertEqual(off, PrivacySettings(readReceipts: false, typingIndicators: false, blockedUserIds: []))

        let signedOut = FakeGimClient(dataDirectory: try makeTemporaryDirectory())
        await assertThrows(.NotRegistered) { try await signedOut.setReadReceipts(enabled: false) }
    }

    func testWithReadReceiptsOffOwnMessagesStopAtDelivered() async throws {
        let client = try await makeDemo(synced: true)
        try await client.setReadReceipts(enabled: false)
        let list = try await subscribeChatList(client)

        _ = try await client.sendText(chatId: direct, body: "On my way", replyTo: nil)
        await scheduler.runUntilIdle()
        XCTAssertEqual(list.items[0].lastMessage?.sendState, .delivered)

        try await client.setReadReceipts(enabled: true)
        _ = try await client.sendText(chatId: direct, body: "Here", replyTo: nil)
        await scheduler.runUntilIdle()
        XCTAssertEqual(list.items[0].lastMessage?.sendState, .read)
    }

    func testWithTypingIndicatorsOffPeerTypingIsNotShown() async throws {
        let client = try await makeDemo()
        let typing = Recorder<[String]>()
        handles.append(try await client.typing(chatId: direct, listener: typing))
        try await client.setTypingIndicators(enabled: false)

        try await client.setPeerTyping(chatId: direct, userId: sofia, active: true)
        try await client.setTyping(chatId: direct, active: true)
        XCTAssertEqual(typing.events, [[]])

        try await client.setTypingIndicators(enabled: true)
        try await client.setPeerTyping(chatId: direct, userId: sofia, active: true)
        XCTAssertEqual(typing.events, [[], [sofia]])
    }

    // MARK: - Avatars

    func testOwnAvatarIsSetFetchedAndRemoved() async throws {
        let client = try await makeDemo()
        let me = FakeGimClient.demoSelfId
        let dest = URL(fileURLWithPath: try makeTemporaryDirectory()).appendingPathComponent("me.png").path
        let initial = try await client.ownProfile()
        XCTAssertEqual(initial?.hasAvatar, false)
        await assertThrows(.NotFound(reason: "avatar of user-alex")) {
            try await client.fetchUserAvatar(userId: me, destPath: dest)
        }
        await assertThrows(.InvalidInput(reason: "File not found")) {
            try await client.setAvatar(filePath: "/nonexistent/me.png", mime: "image/png")
        }

        try await client.setAvatar(filePath: try writeFile("me.png", "photo"), mime: "image/png")
        let withAvatar = try await client.ownProfile()
        XCTAssertEqual(withAvatar?.hasAvatar, true)
        let fetched = try await client.fetchUserAvatar(userId: me, destPath: dest)
        XCTAssertEqual(fetched, dest)
        XCTAssertEqual(try String(contentsOfFile: dest, encoding: .utf8), "photo")
        let members = try await client.chatMembers(chatId: group)
        XCTAssertEqual(members.first { $0.userId == me }?.hasAvatar, true)

        try await client.removeAvatar()
        let removed = try await client.ownProfile()
        XCTAssertEqual(removed?.hasAvatar, false)
        await assertThrows(.NotFound(reason: "avatar of user-alex")) {
            try await client.fetchUserAvatar(userId: me, destPath: dest)
        }
        let signedOut = FakeGimClient(dataDirectory: try makeTemporaryDirectory())
        await assertThrows(.NotRegistered) { try await signedOut.ownProfile() }
    }

    func testAvatarsOfOtherUsersAndGroups() async throws {
        let client = try await makeDemo()
        let directory = try makeTemporaryDirectory()
        await client.addRemoteUser(UserProfile(userId: "user-mira", displayName: "Mira", hasAvatar: true))

        let path = try await client.fetchUserAvatar(
            userId: "user-mira", destPath: directory + "/mira.png")
        XCTAssertEqual(path, directory + "/mira.png")
        XCTAssertFalse(try Data(contentsOf: URL(fileURLWithPath: path)).isEmpty, "a placeholder photo")
        await assertThrows(.NotFound(reason: "avatar of user-sofia")) {
            try await client.fetchUserAvatar(userId: self.sofia, destPath: directory + "/sofia.png")
        }
        await assertThrows(.NotFound(reason: "user user-nobody")) {
            try await client.fetchUserAvatar(userId: "user-nobody", destPath: directory + "/nobody.png")
        }

        await assertThrows(.NotFound(reason: "avatar of chat chat-crew")) {
            try await client.fetchChatAvatar(chatId: self.group, destPath: directory + "/crew.png")
        }
        await assertThrows(.NotFound(reason: "chat chat-nowhere")) {
            try await client.fetchChatAvatar(chatId: "chat-nowhere", destPath: directory + "/crew.png")
        }
        try await client.setGroupInfo(chatId: group, name: nil, avatarFilePath: try writeFile("crew.png", "crew"))
        let crew = try await client.fetchChatAvatar(chatId: group, destPath: directory + "/crew.png")
        XCTAssertEqual(try String(contentsOfFile: crew, encoding: .utf8), "crew")
    }

    // MARK: - Chat settings

    func testDirectChatsCarryThePeer() async throws {
        let client = try await makeDemo()
        let list = try await subscribeChatList(client)
        XCTAssertEqual(
            list.items.first { $0.chatId == direct }?.peer,
            UserProfile(userId: sofia, displayName: "Sofia Marin"))
        XCTAssertNil(list.items.first { $0.chatId == group }?.peer)
    }

    func testPinnedChatsComeFirst() async throws {
        let client = try await makeDemo()
        let list = try await subscribeChatList(client)
        list.clear()

        try await client.setChatPinned(chatId: direct, pinned: true)

        guard list.events.count == 1, list.events[0].count == 2, case .remove(1) = list.events[0][0],
            case .pushFront(let row) = list.events[0][1]
        else { return XCTFail("Expected move, got \(list.events)") }
        XCTAssertEqual(row.chatId, direct)
        XCTAssertTrue(row.pinned)

        // A newer message in an unpinned chat does not pass a pinned one.
        try await client.receiveText(chatId: group, from: "user-luca", body: "Wind is up")
        XCTAssertEqual(list.items.map(\.chatId), [direct, group])

        try await client.setChatPinned(chatId: direct, pinned: false)
        XCTAssertEqual(list.items.map(\.chatId), [group, direct])
        XCTAssertEqual(list.items.map(\.pinned), [false, false])
    }

    func testMutingAndArchivingUpdateTheRowInPlace() async throws {
        let client = try await makeDemo()
        let list = try await subscribeChatList(client)
        list.clear()

        try await client.setChatMuted(chatId: direct, mutedUntilMs: mutedForever())
        try await client.setChatArchived(chatId: direct, archived: true)

        XCTAssertEqual(list.events.count, 2)
        for batch in list.events {
            guard batch.count == 1, case .set(1, let row) = batch[0] else {
                return XCTFail("Expected set, got \(batch)")
            }
            XCTAssertEqual(row.chatId, direct)
        }
        XCTAssertEqual(list.items[1].mutedUntilMs, UInt64.max)
        XCTAssertTrue(list.items[1].archived)

        // A new message does not unarchive the chat.
        try await client.receiveText(chatId: direct, from: sofia, body: "Still there?")
        XCTAssertEqual(list.items[0].chatId, direct)
        XCTAssertTrue(list.items[0].archived)

        try await client.setChatMuted(chatId: direct, mutedUntilMs: 0)
        XCTAssertEqual(list.items[0].mutedUntilMs, 0)
        await assertThrows(.NotFound(reason: "chat chat-nowhere")) {
            try await client.setChatPinned(chatId: "chat-nowhere", pinned: true)
        }
        await assertThrows(.NotFound(reason: "chat chat-nowhere")) {
            try await client.setChatMuted(chatId: "chat-nowhere", mutedUntilMs: 1)
        }
        await assertThrows(.NotFound(reason: "chat chat-nowhere")) {
            try await client.setChatArchived(chatId: "chat-nowhere", archived: true)
        }
    }

    // MARK: - Reports

    func testReportUserRecordsTheReport() async throws {
        let client = try await makeDemo()
        let messageId = try await client.receiveText(chatId: direct, from: sofia, body: "Buy coins")

        let reportId = try await client.reportUser(
            userId: sofia, reason: .scam, note: "Crypto spam", messageIds: [messageId])

        XCTAssertTrue(reportId.hasPrefix("report-"), reportId)
        let reports = await client.reports
        XCTAssertEqual(
            reports,
            [
                FakeGimClient.Report(
                    reportId: reportId, userId: sofia, reason: .scam, note: "Crypto spam", messageIds: [messageId])
            ])
    }

    func testReportUserValidatesItsArguments() async throws {
        let client = try await makeDemo()
        await assertThrows(.NotFound(reason: "user user-nobody")) {
            try await client.reportUser(userId: "user-nobody", reason: .spam, note: nil, messageIds: [])
        }
        await assertThrows(.InvalidInput(reason: "cannot report yourself")) {
            try await client.reportUser(userId: FakeGimClient.demoSelfId, reason: .spam, note: nil, messageIds: [])
        }
        await assertThrows(.InvalidInput(reason: "at most 50 messages")) {
            try await client.reportUser(
                userId: self.sofia, reason: .spam, note: nil, messageIds: (0...50).map { "msg-\($0)" })
        }
        await assertThrows(.InvalidInput(reason: "note: at most 1000 characters")) {
            try await client.reportUser(
                userId: self.sofia, reason: .other, note: String(repeating: "a", count: 1001), messageIds: [])
        }
        await assertThrows(.NotFound(reason: "message msg-nowhere")) {
            try await client.reportUser(userId: self.sofia, reason: .harassment, note: nil, messageIds: ["msg-nowhere"])
        }
        let reports = await client.reports
        XCTAssertEqual(reports, [])
    }

    // MARK: - Recovery code rotation

    func testRotatedRecoveryCodeReplacesTheOldOne() async throws {
        let client = FakeGimClient(dataDirectory: try makeTemporaryDirectory())
        await assertThrows(.NotRegistered) { try await client.rotateRecoveryCode() }
        let old = try await client.createIdentity(displayName: "Kai")
        let userId = try XCTUnwrap(client.userId())

        let rotation = try await client.rotateRecoveryCode()

        XCTAssertEqual(rotation.unsyncedHubIds, [])
        XCTAssertNotEqual(rotation.recoveryCode, old)
        XCTAssertEqual(FakeGimClient.normalizedRecoveryCode(rotation.recoveryCode)?.count, 39)
        let again = try await client.rotateRecoveryCode()
        XCTAssertNotEqual(again.recoveryCode, rotation.recoveryCode)

        try await client.signOut()
        await assertThrows(.Crypto(reason: "Wrong recovery code")) {
            try await client.restoreFromRecovery(userId: userId, recoveryCode: old, revokeOthers: false)
        }
        await assertThrows(.Crypto(reason: "Wrong recovery code")) {
            try await client.restoreFromRecovery(
                userId: userId, recoveryCode: rotation.recoveryCode, revokeOthers: false)
        }
        try await client.restoreFromRecovery(userId: userId, recoveryCode: again.recoveryCode, revokeOthers: false)
        XCTAssertEqual(client.userId(), userId)
    }

    // MARK: - Account deletion

    func testDeleteAccountWipesTheDeviceAndTheAccount() async throws {
        let client = FakeGimClient.demo(
            scheduler: scheduler, dataDirectory: try makeTemporaryDirectory(), autoReply: false, registered: false)
        let code = try await client.createIdentity(displayName: "Kai")
        let userId = try XCTUnwrap(client.userId())
        try await client.blockUser(userId: sofia)
        let list = try await subscribeChatList(client)
        XCTAssertFalse(list.items.isEmpty)

        let unreached = try await client.deleteAccount()

        XCTAssertEqual(unreached, [])
        XCTAssertNil(client.userId())
        let session = try await client.session()
        XCTAssertNil(session)
        XCTAssertEqual(list.items, [])
        let privacy = try await client.privacy()
        XCTAssertEqual(privacy.blockedUserIds, [])
        await assertThrows(.NotFound(reason: "device list of \(userId)")) {
            try await client.restoreFromRecovery(userId: userId, recoveryCode: code, revokeOthers: false)
        }
        await assertThrows(.NotRegistered) { try await client.deleteAccount() }
    }

    func testAnAppExtensionCannotDeleteTheAccount() async throws {
        let client = try await makeDemo(mode: .extension)
        await assertThrows(.InvalidInput(reason: "an app extension cannot delete the account")) {
            try await client.deleteAccount()
        }
        XCTAssertNotNil(client.userId())
    }
}
