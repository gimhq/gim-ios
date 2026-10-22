import GIMCore
import XCTest

/// End-to-end account refusals against hub A of `scripts/e2e-hub.sh fed-start` (or the standalone hub), driven through
/// its admin API (`scripts/mac-gate.sh e2e --admin-url <url> --admin-token-file <path>`, passed as
/// `TEST_RUNNER_GIM_E2E_ADMIN_URL` and `TEST_RUNNER_GIM_E2E_ADMIN_TOKEN`; skipped without them). The app onboards and a
/// scripted peer exchanges a message with it in a direct chat (steps a, b), whose member list gives the app's user id.
/// The admin suspends that user (step c): the app's next send fails with cause `userSuspended`, offers no Retry and
/// explains "Your account is suspended." (one hub: no hub named), and the app stays signed in with its chats readable
/// (step d). After the unsuspend (step e) a relaunched app delivers again. Then the admin lists the user and sets
/// `GIM_HUB_USER_POLICY=deny` (step f): the next send fails with cause `userNotAdmitted`, offers no Retry, explains "Your
/// account is not admitted on this hub." and the app stays signed in. The list entry and the mode are restored and a
/// relaunched app delivers again (step g). A teardown block restores the hub even when a step fails.
///
/// Recovery relaunches the app instead of waiting: after a refused sign-in gim-core does not sign in on that hub for 10
/// minutes (API.md, "Suspended users" and "User policy"), and its sync loop waits as long before it reconnects. That
/// block is in memory only, per client (gim-sdk `Client.suspended`, an empty map when a client is created; nothing is
/// persisted), so terminating the app and launching it again creates a new client without it: the restored session
/// signs in again at once, and the send goes through.
final class AccountPolicySmokeTests: E2ETestCase {
    private let summary = StepSummary("AccountPolicySmokeTests", steps: ["a", "b", "c", "d", "e", "f", "g"])

    @MainActor
    func testSuspensionAndDenyPolicy() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let adminUrl = environment["GIM_E2E_ADMIN_URL"], !adminUrl.isEmpty,
            let adminToken = environment["GIM_E2E_ADMIN_TOKEN"], !adminToken.isEmpty
        else {
            throw XCTSkip(
                "no admin API: pass TEST_RUNNER_GIM_E2E_ADMIN_URL and TEST_RUNNER_GIM_E2E_ADMIN_TOKEN "
                    + "(scripts/mac-gate.sh e2e --admin-url --admin-token-file)")
        }
        continueAfterFailure = false
        let serverUrl = serverUrl
        let suffix = UUID().uuidString.prefix(8).lowercased()
        let appHandle = "alice_\(suffix)"
        let peerName = "Peer \(suffix)"
        let app = XCUIApplication()
        print("[e2e] app and peer use server \(serverUrl), admin API \(adminUrl)")
        addTeardownBlock { [summary] in await summary.report() }

        try XCTContext.runActivity(named: "pre-flight: GET \(serverUrl)/healthz, admin login") { _ in
            try checkServerHealth(app)
        }
        let admin = try waitForPeer("pre-flight: admin login at \(adminUrl)", app) {
            try await HubAdmin.login(baseUrl: adminUrl, token: adminToken)
        }

        summary.start("a")
        let peer = try XCTContext.runActivity(named: "step a: peer registers, app onboards") { _ in
            let peer = try waitForPeer("step a: peer registers as peer_\(suffix)", app) {
                try await ScriptedPeer.register(serverUrl: serverUrl, handle: "peer_\(suffix)", displayName: peerName)
            }
            addTeardownBlock { await peer.shutdown() }
            try launchToOnboarding(app, "step a")
            try createIdentity(displayName: "Alice \(suffix)", handle: appHandle, "step a", app)
            return peer
        }
        summary.finish("a")

        summary.start("b")
        let (chatId, appUserId) = try XCTContext.runActivity(named: "step b: peer opens a chat, both exchange a text") {
            _ in
            let chatId = try waitForPeer("step b: peer opens a direct chat with \(appHandle)", app) {
                try await peer.openDirectChat(handle: appHandle)
            }
            let peerUserId = peer.session.userId
            let appUserId = try eventually("step b: peer sees the app's user as member", app) {
                try await peer.chatMembers(chatId: chatId).first { $0.userId != peerUserId }?.userId
            }
            print("[e2e] app user id \(appUserId)")
            let peerText = "Hello from the peer \(suffix)"
            _ = try waitForPeer("step b: peer sends \"\(peerText)\"", app) {
                try await peer.sendText(chatId: chatId, body: peerText)
            }
            try tap(peerRow(peerName, suffix, app), "step b: chat with the peer", app)
            scrollToLatest(app)
            try require(
                messageText(peerText, in: app).waitForExistence(timeout: networkTimeout),
                "step b: app shows the peer's text", app)
            try sendDelivered("Hello from the app \(suffix)", chatId: chatId, peer: peer, "step b", app)
            return (chatId, appUserId)
        }
        summary.finish("b")

        // Restores the hub after a failure; each call fails harmlessly when its state is already restored.
        addTeardownBlock {
            try? await admin.unsuspend(userId: appUserId)
            try? await admin.removePolicyEntry(userId: appUserId)
            try? await admin.unsetUserPolicy()
        }

        summary.start("c")
        try XCTContext.runActivity(named: "step c: admin suspends the app's user, the send is refused") { _ in
            try waitForPeer("step c: admin suspends \(appUserId)", app) { try await admin.suspend(userId: appUserId) }
            try requireRefusedSend(
                "While suspended \(suffix)", explanation: "Your account is suspended.", "step c", app)
            try require(
                !app.alerts.staticTexts.matching(NSPredicate(format: "label CONTAINS ' suspended on '")).firstMatch
                    .exists, "step c: the single-hub wording names no hub", app)
            try dismissAlert("step c", app)
        }
        summary.finish("c")

        summary.start("d")
        try XCTContext.runActivity(named: "step d: the app stays signed in, its chats stay readable") { _ in
            try requireSignedIn("step d", app)
            try tap(peerRow(peerName, suffix, app), "step d: chat with the peer again", app)
            scrollToLatest(app)
            try require(
                messageText("Hello from the peer \(suffix)", in: app).waitForExistence(timeout: networkTimeout),
                "step d: the peer's text is still readable", app)
        }
        summary.finish("d")

        summary.start("e")
        try XCTContext.runActivity(named: "step e: admin lifts the suspension, a relaunched app delivers") { _ in
            try waitForPeer("step e: admin unsuspends \(appUserId)", app) {
                try await admin.unsuspend(userId: appUserId)
            }
            try relaunch(peerName, suffix, "step e", app)
            try sendDelivered("After the suspension \(suffix)", chatId: chatId, peer: peer, "step e", app)
        }
        summary.finish("e")

        summary.start("f")
        try XCTContext.runActivity(named: "step f: admin denies the app's user, the send is refused") { _ in
            let policy = try waitForPeer("step f: admin lists \(appUserId) and sets the deny policy", app) {
                try await admin.addPolicyEntry(userId: appUserId)
                try await admin.setUserPolicy("deny")
                return try await admin.userPolicy()
            }
            try require(
                policy.mode == "deny" && policy.userIds.contains(appUserId),
                "step f: policy deny with the app's user listed (found \(policy.mode), \(policy.userIds))", app)
            try requireRefusedSend(
                "While denied \(suffix)", explanation: "Your account is not admitted on this hub.", "step f", app)
            try dismissAlert("step f", app)
            try requireSignedIn("step f", app)
        }
        summary.finish("f")

        summary.start("g")
        try XCTContext.runActivity(named: "step g: admin restores the open policy, a relaunched app delivers") { _ in
            let policy = try waitForPeer("step g: admin removes \(appUserId) and unsets the policy", app) {
                try await admin.removePolicyEntry(userId: appUserId)
                try await admin.unsetUserPolicy()
                return try await admin.userPolicy()
            }
            try require(
                policy.mode == "open" && !policy.userIds.contains(appUserId),
                "step g: policy open without the app's user (found \(policy.mode), \(policy.userIds))", app)
            try relaunch(peerName, suffix, "step g", app)
            try sendDelivered("After the deny policy \(suffix)", chatId: chatId, peer: peer, "step g", app)
        }
        summary.finish("g")
    }

    /// The chat list row of the direct chat with the peer; the directory may report the handle as the display name.
    @MainActor
    private func peerRow(_ peerName: String, _ suffix: Substring, _ app: XCUIApplication) -> XCUIElement {
        app.buttons
            .matching(
                NSPredicate(
                    format: "identifier == 'chatList.row' AND (label BEGINSWITH %@ OR label BEGINSWITH %@)",
                    peerName, "peer_\(suffix)")
            )
            .firstMatch
    }

    /// The send status of the bubble showing `text`.
    @MainActor
    private func status(of text: String, in app: XCUIApplication) -> XCUIElement {
        app.cells
            .containing(NSPredicate(format: "identifier == 'timeline.message.text' AND label == %@", text))
            .firstMatch
            .descendants(matching: .any)["timeline.message.status"]
    }

    /// Sends `text` from the open conversation and waits until the peer has it.
    @MainActor
    private func sendDelivered(
        _ text: String, chatId: String, peer: ScriptedPeer, _ step: String, _ app: XCUIApplication
    ) throws {
        try send(text, step, app)
        _ = try eventually("\(step): peer receives \"\(text)\"", app) {
            try await peer.messages(in: chatId).first { $0.text == text }
        }
        scrollToLatest(app)
        try require(
            status(of: text, in: app).waitForExistence(timeout: networkTimeout)
                && status(of: text, in: app).label != "Not sent",
            "\(step): \"\(text)\" not marked Not sent", app)
    }

    /// Sends `text` from the open conversation and checks the refusal: the bubble shows Not sent, its menu has no
    /// Retry, and tapping the status explains the cause with `explanation` (the alert is left open).
    @MainActor
    private func requireRefusedSend(
        _ text: String, explanation: String, _ step: String, _ app: XCUIApplication
    ) throws {
        try send(text, step, app)
        scrollToLatest(app)
        try waitForLabel(status(of: text, in: app), containing: "Not sent", "\(step): \"\(text)\" shows Not sent", app)
        try openMenu(on: messageText(text, in: app), "\(step): menu of the failed message", app)
        try require(!menuItem("Retry", in: app).exists, "\(step): the menu offers no Retry", app)
        // A tap outside the menu closes it.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
        let closed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: menuItem("Reply", in: app))
        try require(XCTWaiter().wait(for: [closed], timeout: 5) == .completed, "\(step): menu closed", app)
        try tap(status(of: text, in: app), "\(step): Not sent status", app)
        let alert = app.alerts["Something Went Wrong"]
        try require(alert.waitForExistence(timeout: networkTimeout), "\(step): explanation alert", app)
        let message = alert.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", explanation)).firstMatch
        let labels = alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " | ")
        try require(message.exists, "\(step): the alert says \"\(explanation)\" (found \(labels))", app)
        print("[e2e] \(step): refused send explained as \"\(message.label)\"")
    }

    @MainActor
    private func dismissAlert(_ step: String, _ app: XCUIApplication) throws {
        try tap(app.alerts["Something Went Wrong"].buttons["OK"], "\(step): OK button", app)
    }

    /// Goes back to the chat list and checks that the app is still signed in: no onboarding, the chats are listed.
    @MainActor
    private func requireSignedIn(_ step: String, _ app: XCUIApplication) throws {
        if !app.buttons["chatList.newChat"].exists {
            try tap(backButton(app), "\(step): back to Chats", app)
        }
        try require(
            app.buttons["chatList.newChat"].waitForExistence(timeout: networkTimeout), "\(step): chat list shown", app)
        try require(!app.buttons["onboarding.create"].exists, "\(step): no onboarding", app)
        try require(
            app.buttons.matching(identifier: "chatList.row").firstMatch.waitForExistence(timeout: networkTimeout),
            "\(step): the chat is still listed", app)
    }

    /// Terminates and launches the app, which creates a new gim-core client, and opens the chat with the peer.
    @MainActor
    private func relaunch(_ peerName: String, _ suffix: Substring, _ step: String, _ app: XCUIApplication) throws {
        app.terminate()
        app.launch()
        try require(
            app.buttons["chatList.newChat"].waitForExistence(timeout: networkTimeout),
            "\(step): relaunched app shows the chat list", app)
        try require(!app.buttons["onboarding.create"].exists, "\(step): relaunched app still signed in", app)
        try tap(peerRow(peerName, suffix, app), "\(step): chat with the peer", app)
    }
}

extension MessageItem {
    fileprivate var text: String? {
        if case .text(let body) = content { return body }
        return nil
    }
}
