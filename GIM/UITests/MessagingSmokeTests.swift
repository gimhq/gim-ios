import GIMCore
import XCTest

/// End-to-end smoke test against a running gim-server (`scripts/start-gim-server.sh start`): the app and a
/// `ScriptedPeer` register, create a group and exchange text, images, a reply, a reaction and a read marker; then
/// the app signs out.
///
/// The server defaults to `http://127.0.0.1:8080`, which the simulator shares with the host; override it with
/// `TEST_RUNNER_GIM_E2E_SERVER_URL=<url> xcodebuild test …`.
final class MessagingSmokeTests: XCTestCase {
    private let serverUrl = ProcessInfo.processInfo.environment["GIM_E2E_SERVER_URL"] ?? "http://127.0.0.1:8080"
    /// For every step that waits on the server or the other client.
    private let networkTimeout: TimeInterval = 30

    @MainActor
    func testMessagingWithScriptedPeer() async throws {
        continueAfterFailure = false
        let suffix = UUID().uuidString.prefix(8).lowercased()
        let appHandle = "alice_\(suffix)"
        let groupName = "Smoke \(suffix)"

        // a. The peer registers first, then the app completes onboarding.
        let peer: ScriptedPeer
        do {
            peer = try await ScriptedPeer.register(
                serverUrl: serverUrl, handle: "peer_\(suffix)", displayName: "Peer \(suffix)")
        } catch {
            XCTFail("The peer can't register on \(serverUrl); is `scripts/start-gim-server.sh start` running? \(error)")
            return
        }
        addTeardownBlock { await peer.shutdown() }

        let app = XCUIApplication()
        app.launchArguments += ["-GIMDefaultServerURL", serverUrl]
        app.launch()
        signOutIfNeeded(app)

        let serverField = app.textFields["onboarding.serverUrl"]
        XCTAssertTrue(serverField.waitForExistence(timeout: networkTimeout))
        XCTAssertEqual(serverField.value as? String, serverUrl)
        type(appHandle, into: app.textFields["onboarding.handle"])
        // Return submits the form, like the Create Account button that the keyboard may cover.
        type("Alice \(suffix)\n", into: app.textFields["onboarding.displayName"])

        // b. The app creates a group with the peer.
        let newChat = app.buttons["chatList.newChat"]
        XCTAssertTrue(newChat.waitForExistence(timeout: networkTimeout))
        newChat.tap()
        tapWhenReady(app.buttons["newChat.newGroup"])
        type(groupName, into: app.textFields["newGroup.name"])
        type(peer.session.handle, into: app.textFields["newGroup.memberHandle"])
        app.buttons["newGroup.addMember"].tap()
        XCTAssertTrue(app.buttons["Remove \(peer.session.displayName)"].waitForExistence(timeout: networkTimeout))
        tapWhenReady(app.buttons["newGroup.create"])
        XCTAssertTrue(app.textViews["composer.text"].waitForExistence(timeout: networkTimeout))
        let chatId = try await eventually("the peer joins the group") { peer.chatId(named: groupName) }

        // c. The app sends text; the peer receives it.
        let appText = "Hello from the app \(suffix)"
        send(appText, in: app)
        let appMessage = try await eventually("the peer receives the app's text") {
            try await peer.messages(in: chatId).first { $0.text == appText }
        }

        // d. The peer sends an image and a text reply; the app shows both. The text comes last so that it is the
        //    newest bubble, right above the composer, for the long press below.
        _ = try await peer.sendImage(chatId: chatId)
        let peerText = "Hello from the peer \(suffix)"
        let peerTextId = try await peer.sendText(chatId: chatId, body: peerText, replyTo: appMessage.messageId)
        let peerImage = app.descendants(matching: .any)["timeline.message.image"]
        XCTAssertTrue(peerImage.waitForExistence(timeout: networkTimeout))
        XCTAssertTrue(messageText(peerText, in: app).waitForExistence(timeout: networkTimeout))

        // f. The app replies to the peer's text and reacts to it; the peer sees both.
        let replyText = "Reply from the app \(suffix)"
        openMenu(on: messageText(peerText, in: app), in: app)
        app.buttons["Reply"].tap()
        send(replyText, in: app)
        _ = try await eventually("the peer receives the app's reply") {
            try await peer.messages(in: chatId).first { $0.text == replyText && $0.replyTo?.messageId == peerTextId }
        }
        let reaction = "👍"
        openMenu(on: messageText(peerText, in: app), in: app)
        app.buttons[reaction].tap()
        _ = try await eventually("the peer sees the app's reaction") {
            try await peer.messages(in: chatId).first {
                $0.messageId == peerTextId && $0.reactions.contains { $0.emoji == reaction }
            }
        }

        // e. The app sends a photo from the library (seeded with `xcrun simctl addmedia` in CI).
        try await sendPhotoIfPickerIsAutomatable(app: app, peer: peer, chatId: chatId)

        // g. The peer marks everything read; the app's reply shows the read ticks.
        let lastFromApp = try await eventually("the peer has the app's messages") {
            try await peer.messages(in: chatId).last { $0.sender.userId != peer.session.userId }
        }
        try await peer.markRead(chatId: chatId, upToMessageId: lastFromApp.messageId)
        let replyStatus = app.cells
            .containing(Self.messageTextPredicate(replyText))
            .descendants(matching: .any)
            .matching(identifier: "timeline.message.status")
            .firstMatch
        let read = expectation(for: NSPredicate(format: "label == 'Read'"), evaluatedWith: replyStatus)
        await fulfillment(of: [read], timeout: networkTimeout)

        // h. Signing out returns to onboarding with the server pre-filled.
        app.navigationBars.buttons["Chats"].tap()
        signOut(app)
        XCTAssertTrue(app.textFields["onboarding.handle"].waitForExistence(timeout: networkTimeout))
        XCTAssertEqual(app.textFields["onboarding.serverUrl"].value as? String, serverUrl)
    }

    /// Attaches a photo through the system photo picker and checks that the peer receives it. The picker runs out
    /// of process; when its grid can't be reached the step is recorded and skipped, and the image path stays
    /// covered by the peer-to-app direction.
    @MainActor
    private func sendPhotoIfPickerIsAutomatable(app: XCUIApplication, peer: ScriptedPeer, chatId: String) async throws {
        app.buttons["composer.attach"].tap()
        tapWhenReady(app.buttons["Photo Library"])
        let photo = app.images
            .matching(NSPredicate(format: "label BEGINSWITH 'Photo' AND identifier != 'timeline.message.image'"))
            .firstMatch
        guard photo.waitForExistence(timeout: networkTimeout) else {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Photo picker grid not reachable; app-to-peer image skipped"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            let cancel = app.buttons["Cancel"]
            if cancel.exists { cancel.tap() } else { app.swipeDown(velocity: .fast) }
            return
        }
        photo.tap()
        _ = try await eventually("the peer receives the app's photo") {
            try await peer.messages(in: chatId).first {
                guard case .image = $0.content else { return false }
                return $0.sender.userId != peer.session.userId
            }
        }
    }

    /// Signs out a session left over from an earlier, interrupted run.
    @MainActor
    private func signOutIfNeeded(_ app: XCUIApplication) {
        let handleField = app.textFields["onboarding.handle"]
        let settings = app.buttons["chatList.settings"]
        for _ in 0..<Int(networkTimeout) {
            if handleField.exists { return }
            if settings.exists {
                signOut(app)
                return
            }
            _ = handleField.waitForExistence(timeout: 1)
        }
    }

    @MainActor
    private func signOut(_ app: XCUIApplication) {
        tapWhenReady(app.buttons["chatList.settings"])
        tapWhenReady(app.buttons["settings.signOut"])
        // The confirmation dialog's button has the same title.
        tapWhenReady(
            app.buttons.matching(NSPredicate(format: "label == 'Sign Out' AND identifier != 'settings.signOut'"))
                .firstMatch)
    }

    @MainActor
    private func send(_ text: String, in app: XCUIApplication) {
        type(text, into: app.textViews["composer.text"])
        tapWhenReady(app.buttons["composer.send"])
    }

    @MainActor
    private func openMenu(on message: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(message.waitForExistence(timeout: networkTimeout))
        message.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["Reply"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func type(_ text: String, into element: XCUIElement) {
        tapWhenReady(element)
        element.typeText(text)
    }

    @MainActor
    private func tapWhenReady(_ element: XCUIElement) {
        let ready = expectation(for: NSPredicate(format: "exists == true AND enabled == true"), evaluatedWith: element)
        wait(for: [ready], timeout: networkTimeout)
        element.tap()
    }

    /// The body label of the timeline bubble showing `text`.
    @MainActor
    private func messageText(_ text: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(Self.messageTextPredicate(text)).firstMatch
    }

    private static func messageTextPredicate(_ text: String) -> NSPredicate {
        NSPredicate(format: "identifier == 'timeline.message.text' AND label == %@", text)
    }

    /// Polls `probe` until it returns a value, for state of the scripted peer that has no UI to wait on.
    @MainActor
    private func eventually<T>(
        _ description: String, _ probe: () async throws -> T?
    ) async throws -> T {
        let deadline = Date().addingTimeInterval(networkTimeout)
        while true {
            if let value = try await probe() { return value }
            guard Date() < deadline else {
                throw SmokeTestError.timedOut("Timed out after \(Int(networkTimeout)) s waiting until \(description)")
            }
            try await Task.sleep(for: .milliseconds(250))
        }
    }
}

private enum SmokeTestError: Error, CustomStringConvertible {
    case timedOut(String)

    var description: String {
        switch self {
        case .timedOut(let message): message
        }
    }
}

extension MessageItem {
    fileprivate var text: String? {
        if case .text(let body) = content { return body }
        return nil
    }
}
