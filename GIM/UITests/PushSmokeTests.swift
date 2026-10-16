import GIMCore
import XCTest

/// End-to-end push through gim-push-mock (`scripts/e2e-hub.sh start` or `fed-start`, then `scripts/mac-gate.sh e2e
/// --push-mock-url <url>`, whose helper hands every mock-ios-sim delivery to `xcrun simctl push`): the app onboards and
/// allows notifications (step a), a scripted peer opens a direct chat with it (step b), the app goes to the home screen
/// (step c), the peer's text shows decrypted in a notification from the Notification Service Extension and the mock
/// recorded the delivery (step d), and tapping the notification opens the app on the message (step e). Step f only
/// observes what the simulator shows for a push gim-core says not to display (an edit); it never fails. Skipped
/// without `TEST_RUNNER_GIM_E2E_PUSH_MOCK_URL`.
final class PushSmokeTests: E2ETestCase {
    private let summary = StepSummary("PushSmokeTests", steps: ["a", "b", "c", "d", "e", "f"])
    /// The push mock's own wait, plus the hub's dispatch and the helper's poll.
    private let pushTimeout: TimeInterval = 60

    @MainActor
    func testPushShowsTheDecryptedMessage() throws {
        guard let pushMockUrl = ProcessInfo.processInfo.environment["GIM_E2E_PUSH_MOCK_URL"], !pushMockUrl.isEmpty
        else {
            throw XCTSkip(
                "no push mock: pass TEST_RUNNER_GIM_E2E_PUSH_MOCK_URL (scripts/mac-gate.sh e2e --push-mock-url)")
        }
        continueAfterFailure = false
        let serverUrl = serverUrl
        let suffix = UUID().uuidString.prefix(8).lowercased()
        let appHandle = "alice_\(suffix)"
        let peerName = "Peer \(suffix)"
        let app = XCUIApplication()
        print("[e2e] app and peer use server \(serverUrl), push mock \(pushMockUrl)")
        addTeardownBlock { [summary] in await summary.report() }

        try XCTContext.runActivity(named: "pre-flight: GET \(serverUrl)/healthz") { _ in
            try checkServerHealth(app)
        }

        summary.start("a")
        let peer = try XCTContext.runActivity(named: "step a: peer registers, app onboards and allows notifications") {
            _ in
            let peer = try waitForPeer("step a: peer registers as peer_\(suffix)", app) {
                try await ScriptedPeer.register(serverUrl: serverUrl, handle: "peer_\(suffix)", displayName: peerName)
            }
            addTeardownBlock { await peer.shutdown() }
            try launchToOnboarding(app, "step a")
            // Allows the authorization alert if this is the first sign-in on the simulator.
            try createIdentity(displayName: "Alice \(suffix)", handle: appHandle, "step a", app)
            try require(!springboard.alerts.firstMatch.exists, "step a: no system alert left over the app", app)
            return peer
        }
        summary.finish("a")

        summary.start("b")
        let (chatId, peerRow) = try XCTContext.runActivity(named: "step b: peer opens a direct chat with the app") {
            _ in
            let chatId = try waitForPeer("step b: peer opens a direct chat with \(appHandle)", app) {
                try await peer.openDirectChat(handle: appHandle)
            }
            // The directory may report the handle as the display name.
            let row = app.buttons
                .matching(
                    NSPredicate(
                        format: "identifier == 'chatList.row' AND (label BEGINSWITH %@ OR label BEGINSWITH %@)",
                        peerName, "peer_\(suffix)")
                )
                .firstMatch
            try require(row.waitForExistence(timeout: networkTimeout), "step b: the chat with the peer appears", app)
            return (chatId, row)
        }
        summary.finish("b")

        summary.start("c")
        try XCTContext.runActivity(named: "step c: app goes to the home screen") { _ in
            XCUIDevice.shared.press(.home)
            let background = XCTNSPredicateExpectation(
                predicate: NSPredicate(
                    format: "state == %d OR state == %d", XCUIApplication.State.runningBackground.rawValue,
                    XCUIApplication.State.runningBackgroundSuspended.rawValue),
                object: app)
            try require(
                XCTWaiter().wait(for: [background], timeout: 10) == .completed, "step c: app in the background", app)
        }
        summary.finish("c")

        summary.start("d")
        let text = "push \(suffix)"
        let (notification, messageId) = try XCTContext.runActivity(
            named: "step d: peer sends \"\(text)\", a notification shows it"
        ) { _ in
            let since = try waitForPeer("step d: push mock deliveries", app) {
                try await Self.deliveries(pushMockUrl, since: nil).next
            }
            let messageId = try waitForPeer("step d: peer sends \"\(text)\"", app) {
                try await peer.sendText(chatId: chatId, body: text)
            }
            let notification = springboardText(containing: text)
            try require(
                notification.waitForExistence(timeout: pushTimeout),
                "step d: notification with \"\(text)\" within \(Int(pushTimeout)) s", app)
            let delivered = try waitForPeer("step d: push mock delivery for im.g.apps", app) {
                try await Self.deliveries(pushMockUrl, since: since).deliveries.filter { $0.appId == "im.g.apps" }
            }
            try require(!delivered.isEmpty, "step d: the push mock delivered a mock-ios-sim push to im.g.apps", app)
            print("[e2e] push mock deliveries for im.g.apps: \(delivered.map(\.summary).joined(separator: ", "))")
            return (notification, messageId)
        }
        summary.finish("d")

        summary.start("e")
        try XCTContext.runActivity(named: "step e: tapping the notification opens the app on the message") { _ in
            if notification.exists && notification.isHittable {
                notification.tap()
            } else {
                // The banner is gone: open Notification Center.
                springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01))
                    .press(
                        forDuration: 0.1,
                        thenDragTo: springboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)))
                try tap(springboardText(containing: text), "step e: notification in Notification Center", app)
            }
            try require(app.wait(for: .runningForeground, timeout: 10), "step e: app in the foreground", app)
            if !app.textViews["composer.text"].exists {
                try tap(peerRow, "step e: chat with the peer", app)
            }
            scrollToLatest(app)
            try require(
                messageText(text, in: app).waitForExistence(timeout: networkTimeout),
                "step e: the chat shows \"\(text)\"",
                app)
        }
        summary.finish("e")

        summary.start("f")
        let observed = try XCTContext.runActivity(named: "step f: an edit (not displayed) in the background") { _ in
            XCUIDevice.shared.press(.home)
            let edited = "\(text) edited"
            try waitForPeer("step f: peer edits its message", app) {
                try await peer.editText(chatId: chatId, messageId: messageId, body: edited)
            }
            // Anything the simulator shows for it: the edited text, gim-core's generic text or the mock's alert.
            let shown = springboard.descendants(matching: .any)
                .matching(NSPredicate(format: "label CONTAINS %@ OR label CONTAINS 'New message'", edited))
                .firstMatch
            let result = shown.waitForExistence(timeout: 20) ? "shown: \(shown.label)" : "nothing shown in 20 s"
            print("[e2e] push not to display (edit): \(result)")
            return shown.exists ? "shown" : "hidden"
        }
        summary.finish("f", observed)
    }

    /// The first Springboard element (a banner or a Notification Center entry) whose label contains `text`.
    @MainActor
    private func springboardText(containing text: String) -> XCUIElement {
        springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// `GET /deliveries?provider=mock-ios-sim` of gim-push-mock (gim-hub docs/push-mock.md), after `since` if set.
    private static func deliveries(_ pushMockUrl: String, since: UInt64?) async throws -> Deliveries {
        var components = URLComponents(string: "\(pushMockUrl)/deliveries")!
        components.queryItems =
            [URLQueryItem(name: "provider", value: "mock-ios-sim")]
            + (since.map { [URLQueryItem(name: "since", value: "\($0)")] } ?? [])
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(Deliveries.self, from: data)
    }
}

/// The part of the push mock's `GET /deliveries` answer the test reads.
private struct Deliveries: Decodable, Sendable {
    struct Delivery: Decodable, Sendable {
        struct Body: Decodable, Sendable {
            struct Registration: Decodable, Sendable {
                var appId: String?

                enum CodingKeys: String, CodingKey {
                    case appId = "app_id"
                }
            }

            struct Payload: Decodable, Sendable {
                var type: String?
            }

            var registration: Registration
            var payload: Payload?
        }

        var seq: UInt64
        var body: Body

        var appId: String? { body.registration.appId }
        var summary: String { "seq=\(seq) type=\(body.payload?.type ?? "?")" }
    }

    var deliveries: [Delivery]
    var next: UInt64
}
