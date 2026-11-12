import GIMCore
import XCTest

/// End-to-end push through gim-push-mock (`scripts/e2e-hub.sh start` or `fed-start`, then `scripts/mac-gate.sh e2e
/// --push-mock-url <url>`, whose helper hands every mock-ios-sim delivery to `xcrun simctl push`): the app onboards and
/// allows notifications (step a), a scripted peer opens a direct chat with it (step b), the app goes to the home screen
/// (step c), the peer's text reaches the mock as a mock-ios-sim delivery for this app (step d), the Notification
/// Service Extension's handler decrypts that delivery's payload in-app and Springboard shows the result (step e), and
/// the chat shows the message (step f). Then (step g) the app holds its sync and goes to the home screen, the peer
/// creates a new group with the app's user and a bystander, and the invitation's delivery goes through the same in-app
/// path: an `invite` named after the group whose body names the inviter, shown by Springboard. Finally (step h) the app
/// signs out from Settings in the foreground, and step d's payload goes through the in-app path again: the handler finds
/// no local store (gim-core deleted it, and a new extension-mode client fails with `InvalidInput`) and shows the
/// generic content, or nothing, without crashing the app. Skipped without `TEST_RUNNER_GIM_E2E_PUSH_MOCK_URL`.
///
/// `simctl push` does not launch Notification Service Extensions on the iOS 27 simulator: it injects the notification
/// through `UNUserNotificationCenter`, so Springboard shows the mock's own alert ("New message"), which the test
/// ignores. Step e therefore hands the delivery's `simctl.payload.gim` (what the extension would read from `userInfo`)
/// to the Debug app's `gim-debug://process-push` entry point, which runs the extension's `PushNotificationHandler`
/// with an extension-mode client on the App Group's data directory and posts the result as a local notification. The
/// extension process itself and its memory footprint need a device with APNs.
///
/// Opening the URL activates the app, whose own sync would join the new group of step g as soon as it resumes, and
/// gim-core shows the invitation only for a chat the processing client joins. Step g therefore first opens
/// `gim-debug://hold-sync` (`DebugPushURL.holdSyncURL`, waiting for `debug.sync.held`): the app stops sync and keeps
/// it stopped until the next push has been processed, so the extension-mode client joins the group as the extension
/// would while the app is suspended. gim-core's store lock is not involved: the app's client simply does not sync.
/// The hold is persisted, so it survives when opening the push URL relaunches the app; the step compares `debug.pid`
/// before and after and reports such a relaunch as `g=pass_relaunched`.
final class PushSmokeTests: E2ETestCase {
    private let summary = StepSummary("PushSmokeTests", steps: ["a", "b", "c", "d", "e", "f", "g", "h"])
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
        let peerName = "Peer \(suffix)"
        let app = XCUIApplication()
        print("[e2e] app and peer use server \(serverUrl), push mock \(pushMockUrl)")
        addTeardownBlock { [summary] in await summary.report() }

        try XCTContext.runActivity(named: "pre-flight: GET \(serverUrl)/healthz") { _ in
            try checkServerHealth(app)
        }

        summary.start("a")
        let (peer, appUserId) = try XCTContext.runActivity(
            named: "step a: peer registers, app onboards and allows notifications"
        ) {
            _ in
            let peer = try waitForPeer("step a: peer registers as peer_\(suffix)", app) {
                try await ScriptedPeer.register(serverUrl: serverUrl, displayName: peerName)
            }
            addTeardownBlock { await peer.shutdown() }
            try launchToOnboarding(app, "step a")
            // Allows the authorization alert if this is the first sign-in on the simulator.
            let account = try createIdentity(displayName: "Alice \(suffix)", "step a", app)
            try require(!springboard.alerts.firstMatch.exists, "step a: no system alert left over the app", app)
            return (peer, account.userId)
        }
        summary.finish("a")

        summary.start("b")
        let (chatId, peerRow) = try XCTContext.runActivity(named: "step b: peer opens a direct chat with the app") {
            _ in
            let chatId = try waitForPeer("step b: peer opens a direct chat with \(appUserId)", app) {
                try await peer.openDirectChat(userId: appUserId)
            }
            // The chat is named by the short Account ID until the peer's profile is known.
            let row = app.buttons
                .matching(
                    NSPredicate(
                        format: "identifier == 'chatList.row' AND (label BEGINSWITH %@ OR label BEGINSWITH %@)",
                        peerName, String(peer.session.userId.dropFirst().prefix(8)))
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
        let delivery = try XCTContext.runActivity(named: "step d: peer sends \"\(text)\", the mock delivers it") { _ in
            let since = try waitForPeer("step d: push mock deliveries", app) {
                try await Self.deliveries(pushMockUrl, since: nil).next
            }
            _ = try waitForPeer("step d: peer sends \"\(text)\"", app) {
                try await peer.sendText(chatId: chatId, body: text)
            }
            // The simulator then shows the mock's own alert ("New message"): `simctl push` runs no service extension.
            let delivery = try eventually("step d: mock-ios-sim delivery of a message to im.g.apps", app) {
                try await Self.deliveries(pushMockUrl, since: since).deliveries.last {
                    $0.appId == "im.g.apps" && $0.token.hasPrefix("sim-") && $0.type == "message" && $0.gim != nil
                }
            }
            print("[e2e] push mock delivery seq=\(delivery.seq) token=\(delivery.token) type=\(delivery.type)")
            return delivery
        }
        summary.finish("d")

        summary.start("e")
        try XCTContext.runActivity(named: "step e: the extension's handler decrypts the delivered payload in-app") {
            _ in
            let payload = String(decoding: delivery.gim ?? Data(), as: UTF8.self)
            app.open(Self.debugPushURL(payload: payload))
            try waitForLabel(
                app.staticTexts["debug.push.body"], containing: text, "step e: debug.push.body is \"\(text)\"", app)
            try require(
                app.staticTexts["debug.push.body"].label == text,
                "step e: debug.push.body exactly \"\(text)\" (found \"\(app.staticTexts["debug.push.body"].label)\")",
                app)
            try require(
                app.staticTexts["debug.push.shouldDisplay"].label == "true", "step e: debug.push.shouldDisplay true",
                app)
            try require(app.staticTexts["debug.push.kind"].label == "message", "step e: debug.push.kind message", app)
            print("[e2e] in-app extension path: title=\(app.staticTexts["debug.push.title"].label) body=\(text)")
            // The app posts the result as a local notification a few seconds later; Springboard shows it in the
            // background.
            XCUIDevice.shared.press(.home)
            try require(
                springboardText(containing: text).waitForExistence(timeout: 20),
                "step e: Springboard shows the decrypted \"\(text)\"", app)
        }
        summary.finish("e")

        summary.start("f")
        try XCTContext.runActivity(named: "step f: the chat shows the message") { _ in
            let banner = springboardText(containing: text)
            if banner.exists && banner.isHittable {
                banner.tap()
            } else {
                app.activate()
            }
            try require(app.wait(for: .runningForeground, timeout: 10), "step f: app in the foreground", app)
            let done = app.buttons["debug.push.done"]
            if done.waitForExistence(timeout: 3) { done.tap() }
            if !app.textViews["composer.text"].exists {
                try tap(peerRow, "step f: chat with the peer", app)
            }
            scrollToLatest(app)
            try require(
                messageText(text, in: app).waitForExistence(timeout: networkTimeout),
                "step f: the chat shows \"\(text)\"", app)
        }
        summary.finish("f")

        summary.start("g")
        let groupName = "Invite \(suffix)"
        var relaunched = false
        try XCTContext.runActivity(named: "step g: peer adds the app to \(groupName), the push shows the invitation") {
            _ in
            let bystander = try waitForPeer("step g: bystander registers as bystander_\(suffix)", app) {
                try await ScriptedPeer.register(serverUrl: serverUrl, displayName: "Bystander \(suffix)")
            }
            addTeardownBlock { await bystander.shutdown() }
            let done = app.buttons["debug.push.done"]
            if done.exists { done.tap() }
            app.open(URL(string: "gim-debug://hold-sync")!)
            try require(
                app.staticTexts["debug.sync.held"].waitForExistence(timeout: 10), "step g: the app holds its sync", app)
            let heldPid = app.staticTexts.matching(identifier: "debug.pid").firstMatch.label
            XCUIDevice.shared.press(.home)
            let since = try waitForPeer("step g: push mock deliveries", app) {
                try await Self.deliveries(pushMockUrl, since: nil).next
            }
            _ = try waitForPeer("step g: peer creates \(groupName) with the app and the bystander", app) {
                try await peer.createGroup(name: groupName, userIds: [appUserId, bystander.session.userId])
            }
            let delivery = try eventually("step g: mock-ios-sim delivery to im.g.apps after the group", app) {
                try await Self.deliveries(pushMockUrl, since: since).deliveries.first {
                    $0.appId == "im.g.apps" && $0.token.hasPrefix("sim-") && $0.gim != nil
                }
            }
            print("[e2e] push mock delivery seq=\(delivery.seq) token=\(delivery.token) type=\(delivery.type)")

            app.open(Self.debugPushURL(payload: String(decoding: delivery.gim ?? Data(), as: UTF8.self)))
            let kind = app.staticTexts["debug.push.kind"]
            try require(kind.waitForExistence(timeout: networkTimeout), "step g: the processed push is shown", app)
            // The persisted hold covers a relaunch; record it so a regression shows up in the summary.
            let pushPid = app.staticTexts.matching(identifier: "debug.pid").firstMatch.label
            if pushPid != heldPid {
                relaunched = true
                print("[e2e] app relaunched pid \(heldPid) -> \(pushPid)")
            }
            try require(kind.label == "invite", "step g: debug.push.kind invite (found \"\(kind.label)\")", app)
            try require(
                app.staticTexts["debug.push.shouldDisplay"].label == "true", "step g: debug.push.shouldDisplay true",
                app)
            let title = app.staticTexts["debug.push.title"].label
            try require(title == groupName, "step g: debug.push.title \"\(groupName)\" (found \"\(title)\")", app)
            // The inviter is named by Account ID until the peer's profile announcement is known.
            let body = app.staticTexts["debug.push.body"].label
            let peerId = peer.session.userId
            try require(
                [peerName, peerId, "\(peerId.dropFirst().prefix(8))…"].map { "\($0) added you" }.contains(body),
                "step g: debug.push.body names the inviter (found \"\(body)\")", app)
            let released = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"), object: app.staticTexts["debug.sync.held"])
            try require(
                XCTWaiter().wait(for: [released], timeout: 10) == .completed, "step g: the app resumes its sync", app)
            print("[e2e] in-app extension path: kind=invite title=\(title) body=\(body)")
            XCUIDevice.shared.press(.home)
            try require(
                springboardText(containing: body).waitForExistence(timeout: 20),
                "step g: Springboard shows \"\(body)\"", app)
        }
        summary.finish("g", relaunched ? "pass relaunched" : "pass")

        summary.start("h")
        try XCTContext.runActivity(named: "step h: app signs out, a later push gets the generic content") { _ in
            app.activate()
            try require(app.wait(for: .runningForeground, timeout: 10), "step h: app in the foreground", app)
            let done = app.buttons["debug.push.done"]
            if done.waitForExistence(timeout: 3) { done.tap() }
            // Step f left the chat with the peer open.
            if !app.buttons["chatList.settings"].waitForExistence(timeout: 3) {
                try tap(backButton(app), "step h: back to the chat list", app)
            }
            try signOut(app)
            try require(
                app.buttons["onboarding.create"].waitForExistence(timeout: networkTimeout),
                "step h: onboarding is shown after sign-out", app)

            app.open(Self.debugPushURL(payload: String(decoding: delivery.gim ?? Data(), as: UTF8.self)))
            let kind = app.staticTexts["debug.push.kind"]
            try require(kind.waitForExistence(timeout: networkTimeout), "step h: the processed push is shown", app)
            let body = app.staticTexts["debug.push.body"].label
            let displayed = app.staticTexts["debug.push.shouldDisplay"].label
            try require(
                (kind.label == "generic" && body == "New message") || displayed == "false",
                "step h: generic \"New message\" or not displayed (found kind \(kind.label), body \"\(body)\", "
                    + "shouldDisplay \(displayed))", app)
            try require(app.state == .runningForeground, "step h: the app is still running", app)
            print("[e2e] in-app extension path after sign-out: kind=\(kind.label) displayed=\(displayed)")
        }
        summary.finish("h")
    }

    /// The first Springboard element (a banner or a Notification Center entry) whose label contains `text`.
    @MainActor
    private func springboardText(containing text: String) -> XCUIElement {
        springboard.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// The app's debug entry point (GIMFeatures `DebugPushURL`): `gim-debug://process-push?payload=<base64url>`.
    private static func debugPushURL(payload: String) -> URL {
        let encoded = Data(payload.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return URL(string: "gim-debug://process-push?payload=\(encoded)")!
    }

    /// `GET /deliveries?provider=mock-ios-sim` of gim-push-mock (gim-hub docs/push-mock.md), after `since` if set.
    private static func deliveries(_ pushMockUrl: String, since: UInt64?) async throws -> Deliveries {
        var components = URLComponents(string: "\(pushMockUrl)/deliveries")!
        components.queryItems =
            [URLQueryItem(name: "provider", value: "mock-ios-sim")]
            + (since.map { [URLQueryItem(name: "since", value: "\($0)")] } ?? [])
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let next = (object["next"] as? NSNumber)?.uint64Value
        else { throw URLError(.badServerResponse) }
        let deliveries = (object["deliveries"] as? [[String: Any]] ?? []).map(Deliveries.Delivery.init)
        return Deliveries(deliveries: deliveries, next: next)
    }
}

/// The part of the push mock's `GET /deliveries` answer the test reads.
private struct Deliveries: Sendable {
    struct Delivery: Sendable {
        var seq: UInt64
        var appId: String
        var token: String
        var type: String
        /// `simctl.payload.gim` as JSON: the object `simctl push` hands to the app, the hub's payload.
        var gim: Data?

        init(_ object: [String: Any]) {
            let body = object["body"] as? [String: Any] ?? [:]
            let registration = body["registration"] as? [String: Any] ?? [:]
            let gim = ((object["simctl"] as? [String: Any])?["payload"] as? [String: Any])?["gim"]
            seq = (object["seq"] as? NSNumber)?.uint64Value ?? 0
            appId = registration["app_id"] as? String ?? ""
            token = registration["token"] as? String ?? ""
            type = (gim as? [String: Any])?["type"] as? String ?? ""
            self.gim = gim.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        }
    }

    var deliveries: [Delivery]
    var next: UInt64
}
