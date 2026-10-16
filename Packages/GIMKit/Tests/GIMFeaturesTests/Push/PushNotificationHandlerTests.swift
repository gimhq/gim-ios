import Foundation
import GIMClientKit
import GIMFeatures
import XCTest

final class PushNotificationHandlerTests: XCTestCase {
    private func content(
        kind: NotificationKind, chatTitle: String? = "Aegean Crew", sender: String? = "Sofia Marin",
        body: String = "Anchored in Hydra", collapseId: String? = "msg-42", shouldDisplay: Bool = true
    ) -> NotificationContent {
        NotificationContent(
            chatId: "chat-aegean", chatTitle: chatTitle, senderUserId: "user-sofia", senderDisplayName: sender,
            body: body, messageId: "msg-42", collapseId: collapseId, kind: kind, shouldDisplay: shouldDisplay,
            timestamp: 1_791_000_000_000)
    }

    private func makeHandler(
        serverUrl: String? = "https://gim.example.eu",
        _ makeClient: @escaping @Sendable (ClientConfig) throws -> any GimClientAPI
    ) -> (PushNotificationHandler, RecordingFactory) {
        let factory = RecordingFactory(makeClient)
        let directory = makeTemporaryDirectory()
        return (
            PushNotificationHandler(
                factory: factory, makeHooks: { TestHooks(dataDir: directory) }, serverUrl: serverUrl),
            factory
        )
    }

    func testMessageInAGroupNamesTheSenderAndTheChat() {
        XCTAssertEqual(
            NotificationPresentation(content(kind: .message)),
            NotificationPresentation(
                isDisplayed: true, title: "Sofia Marin in Aegean Crew", body: "Anchored in Hydra",
                threadIdentifier: "chat-aegean", collapseId: "msg-42", kind: .message))
    }

    func testMessageInADirectChatShowsTheChatTitle() {
        let presentation = NotificationPresentation(content(kind: .message, chatTitle: "Sofia Marin"))
        XCTAssertEqual(presentation.title, "Sofia Marin")
        XCTAssertEqual(presentation.body, "Anchored in Hydra")
    }

    func testReactionKeepsGimCoresBody() {
        let presentation = NotificationPresentation(content(kind: .reaction, body: "reacted 👍"))
        XCTAssertEqual(presentation.title, "Sofia Marin in Aegean Crew")
        XCTAssertEqual(presentation.body, "reacted 👍")
        XCTAssertEqual(presentation.kind, .reaction)
        XCTAssertTrue(presentation.isDisplayed)
    }

    func testInviteWithoutASenderNameShowsTheChat() {
        let presentation = NotificationPresentation(content(kind: .invite, sender: nil, body: "You were added"))
        XCTAssertEqual(presentation.title, "Aegean Crew")
        XCTAssertEqual(presentation.body, "You were added")
        XCTAssertEqual(presentation.threadIdentifier, "chat-aegean")
        XCTAssertEqual(presentation.kind, .invite)
    }

    func testGenericForAnUnknownChatHasNoTitleOrThread() {
        let generic = NotificationContent(
            chatId: nil, chatTitle: nil, senderUserId: nil, senderDisplayName: nil, body: "New message",
            messageId: nil, collapseId: nil, kind: .generic, shouldDisplay: true, timestamp: 0)
        XCTAssertEqual(NotificationPresentation(generic), .generic)
    }

    func testShouldDisplayFalseIsNotDisplayed() {
        let presentation = NotificationPresentation(content(kind: .membership, shouldDisplay: false))
        XCTAssertFalse(presentation.isDisplayed)
    }

    func testCollapseIdIsPassedThrough() {
        XCTAssertEqual(NotificationPresentation(content(kind: .message, collapseId: "c0ffee")).collapseId, "c0ffee")
        XCTAssertNil(NotificationPresentation(content(kind: .message, collapseId: nil)).collapseId)
    }

    func testPayloadIsTheGimEntryAsJSON() throws {
        let userInfo: [AnyHashable: Any] = [
            "aps": ["alert": ["title": "gim", "body": "New message"], "mutable-content": 1],
            "gim": ["v": 1, "type": "message", "seq": 42, "collapse_id": "abc"],
        ]
        let payload = try XCTUnwrap(PushNotificationHandler.payload(from: userInfo))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any])
        XCTAssertEqual(object["type"] as? String, "message")
        XCTAssertEqual(object["seq"] as? Int, 42)
        XCTAssertEqual(object["collapse_id"] as? String, "abc")
        XCTAssertEqual(PushNotificationHandler.payload(from: ["gim": #"{"v":1}"#]), #"{"v":1}"#)
        XCTAssertNil(PushNotificationHandler.payload(from: ["aps": ["badge": 1]]))
    }

    func testProcessesThePushWithAnExtensionClient() async throws {
        let directory = makeTemporaryDirectory()
        let (handler, factory) = makeHandler { config in
            FakeGimClient.demo(
                scheduler: ManualFakeScheduler(), dataDirectory: directory, now: { fixedNow }, autoReply: false,
                mode: config.mode)
        }
        let payload = #"{"type":"message","chat_id":"\#(FakeGimClient.demoGroupChatId)","body":"Anchored in Hydra"}"#
        let presentation = await handler.presentation(payload: payload)
        XCTAssertEqual(
            presentation,
            NotificationPresentation(
                isDisplayed: true, title: "Aegean Crew", body: "Anchored in Hydra",
                threadIdentifier: FakeGimClient.demoGroupChatId, collapseId: nil, kind: .message))
        XCTAssertEqual(factory.configs, [ClientConfig(serverUrl: "https://gim.example.eu", mode: .extension)])
    }

    func testAFailingClientGivesGenericContent() async {
        let (handler, _) = makeHandler { _ in
            throw GimError.Storage(reason: "store is locked by another process")
        }
        let presentation = await handler.presentation(payload: #"{"v":1,"type":"message"}"#)
        XCTAssertEqual(presentation, .generic)
    }

    func testARejectedPayloadGivesGenericContent() async {
        let directory = makeTemporaryDirectory()
        let (handler, _) = makeHandler { config in
            FakeGimClient.demo(scheduler: ManualFakeScheduler(), dataDirectory: directory, mode: config.mode)
        }
        let presentation = await handler.presentation(payload: "[1]")
        XCTAssertEqual(presentation, .generic)
    }

    func testNoPayloadOrServerGivesGenericContentWithoutAClient() async {
        let (withoutServer, factory) = makeHandler(serverUrl: nil) { _ in FakeGimClient() }
        let noServer = await withoutServer.presentation(payload: "{}")
        XCTAssertEqual(noServer, .generic)
        let (withServer, _) = makeHandler { _ in FakeGimClient() }
        let noPayload = await withServer.presentation(payload: nil)
        XCTAssertEqual(noPayload, .generic)
        XCTAssertEqual(factory.configs, [])
    }
}
