import Foundation
import XCTest

@testable import GIMClientKit

final class FakeGimClientPushTests: XCTestCase {
    /// 2026-09-21 16:33:20 in Athens.
    private let base = Date(timeIntervalSince1970: 1_790_000_000)
    private let apns = PushRegistration(
        provider: "apns", token: "a1b2c3", appId: "im.g.apps", sandbox: true, p256dh: nil, auth: nil)

    private func makeDemo(mode: ClientMode? = nil) throws -> FakeGimClient {
        let base = base
        return FakeGimClient.demo(
            scheduler: ManualFakeScheduler(), dataDirectory: try makeTemporaryDirectory(), now: { base },
            autoReply: false, mode: mode)
    }

    func testRegisterPushKeepsTheRegistrationUntilUnregister() async throws {
        let client = try makeDemo()
        var stored = await client.pushRegistration
        XCTAssertNil(stored)

        try await client.registerPush(registration: apns)
        stored = await client.pushRegistration
        XCTAssertEqual(stored, apns)

        let renewed = PushRegistration(
            provider: "apns", token: "d4e5f6", appId: nil, sandbox: nil, p256dh: nil, auth: nil)
        try await client.registerPush(registration: renewed)
        stored = await client.pushRegistration
        XCTAssertEqual(stored, renewed)

        try await client.unregisterPush()
        stored = await client.pushRegistration
        XCTAssertNil(stored)
    }

    func testRegisterPushRejectsAnEmptyToken() async throws {
        let client = try makeDemo()
        await assertThrows(.InvalidInput(reason: "push registration: empty provider or token")) {
            try await client.registerPush(
                registration: PushRegistration(
                    provider: "apns", token: "", appId: nil, sandbox: nil, p256dh: nil, auth: nil))
        }
        let stored = await client.pushRegistration
        XCTAssertNil(stored)
    }

    func testSignOutDropsTheRegistration() async throws {
        let client = try makeDemo()
        try await client.registerPush(registration: apns)
        try await client.signOut()
        let stored = await client.pushRegistration
        XCTAssertNil(stored)
    }

    func testProcessPushDescribesAMessage() async throws {
        let client = try makeDemo()
        let payload = #"{"type":"message","chat_id":"\#(FakeGimClient.demoGroupChatId)","body":"Anchored in Hydra"}"#
        let content = try await client.processPush(payload: payload)
        XCTAssertEqual(
            content,
            NotificationContent(
                chatId: FakeGimClient.demoGroupChatId, chatTitle: "Aegean Crew", senderUserId: nil,
                senderDisplayName: nil, body: "Anchored in Hydra", messageId: nil, collapseId: nil, kind: .message,
                shouldDisplay: true, timestamp: 1_790_000_000_000))
    }

    func testProcessPushFallsBackToGenericContent() async throws {
        let client = try makeDemo()
        for payload in [#"{"type":"wake"}"#, #"{"type":"message","chat_id":"chat-unknown"}"#, "{}"] {
            let content = try await client.processPush(payload: payload)
            XCTAssertEqual(content.kind, .generic, payload)
            XCTAssertEqual(content.body, "New message", payload)
            XCTAssertTrue(content.shouldDisplay, payload)
            XCTAssertNil(content.chatTitle, payload)
        }
    }

    func testProcessPushRejectsANonObjectPayload() async throws {
        let client = try makeDemo()
        for payload in ["", "[1]", "not json"] {
            await assertThrows(.InvalidInput(reason: "push payload is not a JSON object")) {
                try await client.processPush(payload: payload)
            }
        }
    }

    func testExtensionModeHasNoSyncAndNoRegistration() async throws {
        let client = try makeDemo(mode: .extension)
        await assertThrows(.InvalidInput(reason: "no sync loop in extension mode")) {
            try await client.startSync()
        }
        try await client.registerPush(registration: apns)
        var stored = await client.pushRegistration
        XCTAssertNil(stored)
        try await client.unregisterPush()
        stored = await client.pushRegistration
        XCTAssertNil(stored)

        let content = try await client.processPush(payload: #"{"type":"message","chat_id":"chat-sofia","body":"Hi"}"#)
        XCTAssertEqual(content.kind, .message)
        XCTAssertEqual(content.chatTitle, "Sofia Marin")
    }

    func testSignOutDeletesTheStoreOfEarlierClients() async throws {
        let directory = try makeTemporaryDirectory()
        let app = FakeGimClient.demo(scheduler: ManualFakeScheduler(), dataDirectory: directory, autoReply: false)
        let earlier = FakeGimClient.demo(
            scheduler: ManualFakeScheduler(), dataDirectory: directory, autoReply: false, mode: .extension)
        let otherDirectory = try makeDemo(mode: .extension)
        let payload = #"{"type":"message","chat_id":"chat-sofia","body":"Hi"}"#

        try await app.signOut()

        await assertThrows(.Storage(reason: "the local store was deleted by sign-out")) {
            try await earlier.processPush(payload: payload)
        }
        let later = FakeGimClient.demo(
            scheduler: ManualFakeScheduler(), dataDirectory: directory, autoReply: false, mode: .extension)
        let content = try await later.processPush(payload: payload)
        XCTAssertEqual(content.kind, .message)
        let unaffected = try await otherDirectory.processPush(payload: payload)
        XCTAssertEqual(unaffected.kind, .message)
    }

    func testExtensionModeCannotSignOut() async throws {
        let client = try makeDemo(mode: .extension)
        await assertThrows(.InvalidInput(reason: "an app extension cannot sign out")) {
            try await client.signOut()
        }
        XCTAssertNotNil(client.userId())
        let content = try await client.processPush(payload: #"{"type":"message","chat_id":"chat-sofia","body":"Hi"}"#)
        XCTAssertEqual(content.kind, .message)
    }

    func testCreateClientPassesTheMode() async throws {
        let hooks = MemoryHooks(dataDir: try makeTemporaryDirectory())
        let client = try await createClient(
            config: ClientConfig(serverUrl: "https://gim.example.eu", mode: .extension), hooks: hooks)
        _ = try await client.createIdentity(displayName: "Kai")
        await assertThrows(.InvalidInput(reason: "no sync loop in extension mode")) {
            try await client.startSync()
        }

        let app = try await createClient(config: ClientConfig(serverUrl: "https://gim.example.eu"), hooks: hooks)
        _ = try await app.createIdentity(displayName: "Kai")
        try await app.startSync()
    }
}
