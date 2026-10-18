import GIMClientKit
import GIMCore
import XCTest

@testable import GIMPlatform

final class CoreMappingTests: XCTestCase {
    func testClientConfigKeepsTheMode() {
        XCTAssertEqual(
            GIMCore.ClientConfig(GIMClientKit.ClientConfig(serverUrl: "https://gim.example.eu")),
            GIMCore.ClientConfig(serverUrl: "https://gim.example.eu", mode: nil))
        XCTAssertEqual(
            GIMCore.ClientConfig(GIMClientKit.ClientConfig(serverUrl: "https://gim.example.eu", mode: .app)).mode,
            .app)
        XCTAssertEqual(
            GIMCore.ClientConfig(GIMClientKit.ClientConfig(serverUrl: "https://gim.example.eu", mode: .extension)).mode,
            .extension)
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
