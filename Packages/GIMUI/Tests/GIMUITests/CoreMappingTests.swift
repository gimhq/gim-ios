import GIMClientKit
import GIMCore
import XCTest

@testable import GIMUI

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
