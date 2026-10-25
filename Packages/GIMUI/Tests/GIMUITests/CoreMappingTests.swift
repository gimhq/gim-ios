import GIMClientKit
import GIMCore
import XCTest

@testable import GIMPlatform

final class CoreMappingTests: XCTestCase {
    func testClientConfigKeepsTheMode() {
        XCTAssertEqual(
            GIMCore.ClientConfig(GIMClientKit.ClientConfig(serverUrl: "https://gim.example.eu")),
            GIMCore.ClientConfig(serverUrl: "https://gim.example.eu", mode: nil, keepServerUrl: nil))
        XCTAssertEqual(
            GIMCore.ClientConfig(GIMClientKit.ClientConfig(serverUrl: "https://gim.example.eu", mode: .app)).mode,
            .app)
        XCTAssertEqual(
            GIMCore.ClientConfig(GIMClientKit.ClientConfig(serverUrl: "https://gim.example.eu", mode: .extension)).mode,
            .extension)
    }

    func testClientConfigKeepsTheKeepServerUrl() {
        XCTAssertEqual(
            GIMCore.ClientConfig(
                GIMClientKit.ClientConfig(serverUrl: "https://gim.example.eu", keepServerUrl: "https://keep.example.eu")
            ),
            GIMCore.ClientConfig(
                serverUrl: "https://gim.example.eu", mode: nil, keepServerUrl: "https://keep.example.eu"))
    }

    func testChatSummaryMapsTheAccountSafetyFields() {
        let peer = GIMCore.UserProfile(
            userId: "user-sofia", handle: "sofia", displayName: "Sofia Marin", hasAvatar: true)
        let core = GIMCore.ChatSummary(
            chatId: "chat-sofia", kind: .direct, name: "Sofia Marin", avatar: nil, lastMessage: nil, unreadCount: 2,
            updatedAtMs: 1_790_000_000_000, memberCount: 2, state: .active, peer: peer,
            mutedUntilMs: GIMCore.mutedForever(), pinned: true, archived: true, blocked: true)
        XCTAssertEqual(
            GIMClientKit.ChatSummary(core),
            GIMClientKit.ChatSummary(
                chatId: "chat-sofia", kind: .direct, name: "Sofia Marin", avatar: nil, lastMessage: nil, unreadCount: 2,
                updatedAtMs: 1_790_000_000_000, memberCount: 2, state: .active,
                peer: GIMClientKit.UserProfile(
                    userId: "user-sofia", handle: "sofia", displayName: "Sofia Marin", hasAvatar: true),
                mutedUntilMs: GIMClientKit.mutedForever(), pinned: true, archived: true, blocked: true))
        let group = GIMCore.ChatSummary(
            chatId: "chat-crew", kind: .group, name: "Aegean Crew", avatar: nil, lastMessage: nil, unreadCount: 0,
            updatedAtMs: 1_790_000_000_000, memberCount: 4, state: .active, peer: nil, mutedUntilMs: 0, pinned: false,
            archived: false, blocked: false)
        let mapped = GIMClientKit.ChatSummary(group)
        XCTAssertNil(mapped.peer)
        XCTAssertEqual(mapped.mutedUntilMs, 0)
        XCTAssertFalse(mapped.pinned || mapped.archived || mapped.blocked)
    }

    func testMutedForeverMatchesGimCore() {
        XCTAssertEqual(GIMClientKit.mutedForever(), GIMCore.mutedForever())
    }

    func testReportReasonMapsEveryCase() {
        let reasons: [(GIMClientKit.ReportReason, GIMCore.ReportReason)] = [
            (.spam, .spam), (.harassment, .harassment), (.inappropriate, .inappropriate), (.scam, .scam),
            (.other, .other),
        ]
        for (mirror, core) in reasons {
            XCTAssertEqual(GIMCore.ReportReason(mirror), core)
        }
    }

    func testPrivacySettingsAndRecoveryRotationMapEveryField() {
        XCTAssertEqual(
            GIMClientKit.PrivacySettings(
                GIMCore.PrivacySettings(readReceipts: false, typingIndicators: true, blockedUserIds: ["u1", "u2"])),
            GIMClientKit.PrivacySettings(readReceipts: false, typingIndicators: true, blockedUserIds: ["u1", "u2"]))
        XCTAssertEqual(
            GIMClientKit.RecoveryRotation(
                GIMCore.RecoveryRotation(recoveryCode: "7BQ2-K9MX", unsyncedHubIds: ["hub-b"])),
            GIMClientKit.RecoveryRotation(recoveryCode: "7BQ2-K9MX", unsyncedHubIds: ["hub-b"]))
    }

    func testUserSuspendedMapsBothWays() {
        XCTAssertEqual(
            GIMClientKit.GimError(GIMCore.GimError.UserSuspended(hubId: "hub-a")), .UserSuspended(hubId: "hub-a"))
        XCTAssertEqual(GIMCore.GimError(GIMClientKit.GimError.UserSuspended(hubId: "")), .UserSuspended(hubId: ""))
    }

    func testUserPolicyErrorsMapBothWays() {
        let cases: [(GIMCore.GimError, GIMClientKit.GimError)] = [
            (.UserNotAdmitted(hubId: "hub-a"), .UserNotAdmitted(hubId: "hub-a")),
            (.UserNotAdmitted(hubId: ""), .UserNotAdmitted(hubId: "")),
            (
                .NotAdmittedByPeer(hubId: "hub-b", chatId: "hub-b/g1"),
                .NotAdmittedByPeer(hubId: "hub-b", chatId: "hub-b/g1")
            ),
            (.ContactNotAdmitted(userIds: ["u1", "u2"]), .ContactNotAdmitted(userIds: ["u1", "u2"])),
        ]
        for (core, mirror) in cases {
            XCTAssertEqual(GIMClientKit.GimError(core), mirror)
            XCTAssertEqual(GIMCore.GimError(mirror), core)
        }
    }

    func testFailedSendStateKeepsTheReasonAndCause() {
        let causes: [(GIMCore.SendFailure, GIMClientKit.SendFailure)] = [
            (.userSuspended, .userSuspended), (.userNotAdmitted, .userNotAdmitted),
            (.notAdmittedByPeer, .notAdmittedByPeer), (.rejected, .rejected), (.other, .other),
        ]
        for (core, mirror) in causes {
            XCTAssertEqual(GIMClientKit.SendFailure(core), mirror)
            XCTAssertEqual(
                GIMClientKit.SendState(GIMCore.SendState.failed(reason: "refused", cause: core)),
                .failed(reason: "refused", cause: mirror))
        }
    }

    func testMessagePreviewMapsTheSendState() {
        let own = GIMCore.MessagePreview(
            senderName: "Alex Morgan", text: "On my way", kind: .text, sentAtMs: 1_790_000_000_000, isOwn: true,
            sendState: .delivered)
        XCTAssertEqual(
            GIMClientKit.MessagePreview(own),
            GIMClientKit.MessagePreview(
                senderName: "Alex Morgan", text: "On my way", sentAtMs: 1_790_000_000_000, isOwn: true,
                sendState: .delivered))
        let failed = GIMCore.MessagePreview(
            senderName: "Alex Morgan", text: "On my way", kind: .text, sentAtMs: 1_790_000_000_000, isOwn: true,
            sendState: .failed(reason: "refused", cause: .rejected))
        XCTAssertEqual(
            GIMClientKit.MessagePreview(failed).sendState, .failed(reason: "refused", cause: .rejected))
        let peer = GIMCore.MessagePreview(
            senderName: "Sofia Marin", text: "Ahoy", kind: .text, sentAtMs: 1_790_000_000_000, isOwn: false,
            sendState: nil)
        XCTAssertNil(GIMClientKit.MessagePreview(peer).sendState)
    }

    func testRecoveryKitStructsMapEveryField() {
        XCTAssertEqual(
            GIMCore.RecoveryKitLabels(
                GIMClientKit.RecoveryKitLabels(
                    title: "Recovery kit", accountId: "Account ID", recoveryKey: "Recovery key", note: "Keep it.")),
            GIMCore.RecoveryKitLabels(
                title: "Recovery kit", accountId: "Account ID", recoveryKey: "Recovery key", note: "Keep it."))
        XCTAssertEqual(
            GIMClientKit.ParsedRecoveryKit(GIMCore.ParsedRecoveryKit(userId: "u1", recoveryCode: nil)),
            GIMClientKit.ParsedRecoveryKit(userId: "u1", recoveryCode: nil))
    }

    /// The pure-Swift copy in GIMClientKit must stay in step with gim-core.
    func testFakeRecoveryKitFunctionsMatchGimCore() {
        let core = CoreRecoveryKitFunctions()
        let fake = FakeRecoveryKitFunctions()
        let userId = "u" + String(repeating: "abcdefghijklmnopqrstuvwxyz234567", count: 2).prefix(54) + "q"
        let code = "7BQ2-K9MX-4TVA-0HZR-PC63-W8NE-1SJD-5GFY-QK2M-V7R"
        let labels = GIMClientKit.RecoveryKitLabels(
            title: "恢复工具包", accountId: "账户 ID", recoveryKey: "恢复密钥", note: "请妥善保管。")

        for (userId, code) in [(userId, code), (" \(userId.uppercased()) ", code.lowercased()), ("", "a-b c")] {
            XCTAssertEqual(
                core.formatRecoveryKit(userId: userId, recoveryCode: code, labels: labels),
                fake.formatRecoveryKit(userId: userId, recoveryCode: code, labels: labels))
        }
        let spaced = code.replacingOccurrences(of: "-", with: " ")
        let texts = [
            core.formatRecoveryKit(userId: userId, recoveryCode: code, labels: labels),
            "Hi,\r\nAccount ID: \(userId.uppercased())\r\nmy key is \(spaced) again.\r\n",
            "\(userId)-0000", "\(userId)-\(code)", "x\(userId)", "\(userId)\n\(code.dropLast())S",
            "\(userId)\n\(code.replacingOccurrences(of: "0HZR", with: "OHZR"))", "my key is \(code)", "", "not a kit",
        ]
        for text in texts {
            XCTAssertEqual(core.parseRecoveryKit(text: text), fake.parseRecoveryKit(text: text), text)
        }
        for code in [code, code.lowercased(), "a-b", "", "ABCDE\u{301}"] {
            XCTAssertEqual(core.recoveryKeyEnding(recoveryCode: code), fake.recoveryKeyEnding(recoveryCode: code))
        }
        for typed in ["V7R", "MV7R", "mv-7r", " m v 7 r ", "MV7S", "AMV7R", ""] {
            XCTAssertEqual(
                core.matchesRecoveryKeyEnding(recoveryCode: code, typed: typed),
                fake.matchesRecoveryKeyEnding(recoveryCode: code, typed: typed), typed)
        }
    }

    func testPushRegistrationMapsEveryField() {
        let mirror = GIMClientKit.PushRegistration(
            provider: "unifiedpush", token: "https://push.example.eu/up/abc", appId: "im.g.apps", sandbox: false,
            p256dh: "BNcR", auth: "tBHI")
        XCTAssertEqual(
            GIMCore.PushRegistration(mirror),
            GIMCore.PushRegistration(
                provider: "unifiedpush", token: "https://push.example.eu/up/abc", appId: "im.g.apps", sandbox: false,
                p256dh: "BNcR", auth: "tBHI"))
    }

    func testNotificationContentMapsEveryFieldAndKind() {
        let kinds: [(GIMCore.NotificationKind, GIMClientKit.NotificationKind)] = [
            (.message, .message), (.reaction, .reaction), (.invite, .invite), (.membership, .membership),
            (.generic, .generic),
        ]
        for (core, mirror) in kinds {
            let content = GIMCore.NotificationContent(
                chatId: "chat-crew", chatTitle: "Aegean Crew", senderUserId: "user-sofia",
                senderDisplayName: "Sofia Marin", body: "Anchored in Hydra", messageId: "msg-1",
                collapseId: "collapse-1", kind: core, shouldDisplay: core != .membership,
                timestamp: 1_790_000_000_000)
            XCTAssertEqual(
                GIMClientKit.NotificationContent(content),
                GIMClientKit.NotificationContent(
                    chatId: "chat-crew", chatTitle: "Aegean Crew", senderUserId: "user-sofia",
                    senderDisplayName: "Sofia Marin", body: "Anchored in Hydra", messageId: "msg-1",
                    collapseId: "collapse-1", kind: mirror, shouldDisplay: mirror != .membership,
                    timestamp: 1_790_000_000_000))
        }
    }
}
