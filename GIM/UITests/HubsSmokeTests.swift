import GIMCore
import XCTest

/// End-to-end hub management on two federated hubs (`scripts/e2e-hub.sh fed-start`): the app onboards on hub A (the
/// `E2ETestCase` server URL) and creates a group with scripted peers on A, adds hub B
/// (`TEST_RUNNER_GIM_E2E_SERVER_URL_B`), makes it primary, exchanges messages with the peers, then removes B again.
/// Skipped without a hub B URL.
///
/// The group is created while A is primary: with B primary, inviting users of A failed with NotFound (KeyPackages
/// claimed through B) against gim-hub 50b3401.
final class HubsSmokeTests: E2ETestCase {
    private let summary = StepSummary("HubsSmokeTests", steps: ["a", "b", "c", "d", "e", "f"])
    /// How step e's removal went, for the summary line: "removed", or "owned-groups" after the HubOwnsGroups
    /// confirmation.
    private var removalOutcome = "removed"

    @MainActor
    func testTwoHubsWithScriptedPeer() throws {
        guard let serverUrlB = ProcessInfo.processInfo.environment["GIM_E2E_SERVER_URL_B"], !serverUrlB.isEmpty else {
            throw XCTSkip("no hub B: pass TEST_RUNNER_GIM_E2E_SERVER_URL_B (scripts/mac-gate.sh e2e --hub-b-url)")
        }
        continueAfterFailure = false
        let serverUrl = serverUrl
        let suffix = UUID().uuidString.prefix(8).lowercased()
        let groupName = "Hubs \(suffix)"
        let hubA = hubKey(serverUrl)
        let hubB = hubKey(serverUrlB)
        let app = XCUIApplication()
        print("[e2e] app onboards on hub A \(serverUrl), adds hub B \(serverUrlB)")
        addTeardownBlock { [summary] in await summary.report() }

        try XCTContext.runActivity(named: "pre-flight: GET \(serverUrl)/healthz") { _ in
            try checkServerHealth(app)
        }

        summary.start("a")
        let (peer, chatId) = try XCTContext.runActivity(
            named: "step a: peers register on A, app onboarding, app creates \(groupName)"
        ) { _ in
            let peer = try waitForPeer("step a: peer registers as peer_\(suffix)", app) {
                try await ScriptedPeer.register(
                    serverUrl: serverUrl, handle: "peer_\(suffix)", displayName: "Peer \(suffix)")
            }
            addTeardownBlock { await peer.shutdown() }
            // New groups need at least two members besides the creator.
            let bystander = try waitForPeer("step a: bystander registers as bystander_\(suffix)", app) {
                try await ScriptedPeer.register(
                    serverUrl: serverUrl, handle: "bystander_\(suffix)", displayName: "Bystander \(suffix)")
            }
            addTeardownBlock { await bystander.shutdown() }
            try launchToOnboarding(app, "step a")
            try createIdentity(displayName: "Alice \(suffix)", handle: "alice_\(suffix)", "step a", app)
            // TODO(M2c core C4-T5): restore the original order (create the group while hub B is primary) once
            // gim-core fixes the cross-hub KeyPackage claim returning NotFound.
            try createGroup(groupName, members: [peer.session, bystander.session], "step a", app)
            let chatId = try eventually("step a: peer joins \(groupName)", app) { peer.chatId(named: groupName) }
            try tap(backButton(app), "step a: back to Chats", app)
            return (peer, chatId)
        }
        summary.finish("a")

        summary.start("b")
        try XCTContext.runActivity(named: "step b: app adds hub B, it becomes verified and signed in") { _ in
            try openHubs("step b", app)
            try requireHub(hubA, state: "Verified", signedIn: true, "step b", app)
            try requireBadge("home", on: hubA, "step b", app)
            try requireBadge("primary", on: hubA, "step b", app)
            try addHub(serverUrlB, "step b", app)
            try requireHub(hubB, state: "Verified", signedIn: true, timeout: 60, "step b", app)
        }
        summary.finish("b")

        summary.start("c")
        try XCTContext.runActivity(named: "step c: hub B becomes primary") { _ in
            try tap(app.buttons["hubs.setPrimary.\(hubB)"], "step c: Make Primary button of B", app)
            try requireBadge("primary", on: hubB, "step c", app)
            try requireBadge("home", on: hubA, "step c", app)
            try closeHubs("step c", app)
        }
        summary.finish("c")

        summary.start("d")
        try XCTContext.runActivity(named: "step d: messaging with the peer on A keeps working") { _ in
            try tap(chatRow(groupName, in: app), "step d: \(groupName) row", app)
            let appText = "Through B \(suffix)"
            try send(appText, "step d", app)
            _ = try eventually("step d: peer receives \"\(appText)\"", app) {
                try await peer.messages(in: chatId).first { $0.isText(appText) }
            }
            let peerText = "Back from A \(suffix)"
            _ = try waitForPeer("step d: peer sends a text", app) {
                try await peer.sendText(chatId: chatId, body: peerText)
            }
            scrollToLatest(app)
            try require(
                messageText(peerText, in: app).waitForExistence(timeout: networkTimeout),
                "step d: app shows the peer's text", app)
            try tap(backButton(app), "step d: back to Chats", app)
        }
        summary.finish("d")

        summary.start("e")
        try XCTContext.runActivity(named: "step e: app removes hub B, A is primary again") { _ in
            try openHubs("step e", app)
            try removeHubRetryingUntilDrained(hubB, "step e", app)
            try requireHub(hubB, state: "Removed", signedIn: false, timeout: 60, "step e", app)
            try requireBadge("primary", on: hubA, "step e", app)
            try requireHub(hubA, state: "Verified", signedIn: true, "step e", app)
        }
        summary.finish("e", removalOutcome)

        summary.start("f")
        try XCTContext.runActivity(named: "step f: messaging still works, then sign out") { _ in
            try closeHubs("step f", app)
            try tap(chatRow(groupName, in: app), "step f: \(groupName) row", app)
            let appText = "Through A \(suffix)"
            try send(appText, "step f", app)
            _ = try eventually("step f: peer receives \"\(appText)\"", app) {
                try await peer.messages(in: chatId).first { $0.isText(appText) }
            }
            try tap(backButton(app), "step f: back to Chats", app)
            try signOut(app)
            try require(
                app.buttons["onboarding.create"].waitForExistence(timeout: networkTimeout),
                "step f: onboarding visible after sign-out", app)
        }
        summary.finish("f")
    }

    /// Removes the hub, confirming the owned groups warning if the hub owns chats, and retries while gim-core reports
    /// it not drained yet (messages sent through it still unsettled).
    @MainActor
    private func removeHubRetryingUntilDrained(_ key: String, _ step: String, _ app: XCUIApplication) throws {
        for attempt in 1...6 {
            try requestHubRemoval(key, "\(step) (attempt \(attempt))", app)
            let ownedGroups = app.alerts["Remove Hub?"]
            let notDrained = app.alerts["Try Again Later"]
            let removed = app.staticTexts.matching(
                NSPredicate(format: "identifier == %@ AND label == 'Removed'", "hubs.state.\(key)")
            ).firstMatch
            let deadline = Date().addingTimeInterval(networkTimeout)
            while Date() < deadline && !(ownedGroups.exists || notDrained.exists || removed.exists) {
                Thread.sleep(forTimeInterval: 0.5)
            }
            if ownedGroups.exists {
                print("[e2e] \(step): \(ownedGroups.staticTexts.allElementsBoundByIndex.map(\.label))")
                removalOutcome = "owned-groups"
                try tap(ownedGroups.buttons["Remove Anyway"], "\(step): Remove Anyway button", app)
                return
            }
            guard notDrained.exists else { return }
            print("[e2e] \(step): hub not drained yet (attempt \(attempt)), retrying in 5 s")
            try tap(notDrained.buttons["OK"], "\(step): OK button", app)
            Thread.sleep(forTimeInterval: 5)
        }
        try require(false, "\(step): \(key) still not drained after 6 attempts", app)
    }
}

extension MessageItem {
    fileprivate func isText(_ text: String) -> Bool {
        if case .text(let body) = content { return body == text }
        return false
    }
}
