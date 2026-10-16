import GIMCore
import XCTest

/// End-to-end chat state against a running gim-hub (`scripts/e2e-hub.sh start`): the app leaves a group (Leaving…
/// until a scripted peer's sync commits the removal, then left), and a peer removes the app's user while the app is
/// in the background (sync stopped). See `E2ETestCase` for the hub URL.
final class ChatStateSmokeTests: E2ETestCase {
    private let summary = StepSummary("ChatStateSmokeTests", steps: ["a", "b", "c", "d", "e", "f"])
    /// How step e's send went, for the summary line: "rejected" (the hub rejected it and it shows Not sent), "refused"
    /// (sync applied the removal first, so the app refused the send) or "no-composer" (read-only before typing).
    private var removalSendOutcome = "n/a"
    /// gim-core members commit a pending leave Proposal during sync, the chosen one at once and the others after
    /// 5–15 s; give it more than the usual network timeout.
    private let commitTimeout: TimeInterval = 60

    @MainActor
    func testLeaveAndRemovalWithScriptedPeers() throws {
        continueAfterFailure = false
        let serverUrl = serverUrl
        let suffix = UUID().uuidString.prefix(8).lowercased()
        let leaveGroupName = "Leave \(suffix)"
        let removalGroupName = "Removal \(suffix)"
        let app = XCUIApplication()
        print("[e2e] app and peers use server \(serverUrl)")
        addTeardownBlock { [summary] in await summary.report() }

        try XCTContext.runActivity(named: "pre-flight: GET \(serverUrl)/healthz") { _ in
            try checkServerHealth(app)
        }

        summary.start("a")
        let (peer, bystander) = try XCTContext.runActivity(named: "step a: peers register, app onboarding") { _ in
            let peer = try waitForPeer("step a: peer registers as peer_\(suffix)", app) {
                try await ScriptedPeer.register(
                    serverUrl: serverUrl, handle: "peer_\(suffix)", displayName: "Peer \(suffix)")
            }
            addTeardownBlock { await peer.shutdown() }
            let bystander = try waitForPeer("step a: bystander registers as bystander_\(suffix)", app) {
                try await ScriptedPeer.register(
                    serverUrl: serverUrl, handle: "bystander_\(suffix)", displayName: "Bystander \(suffix)")
            }
            addTeardownBlock { await bystander.shutdown() }
            try launchToOnboarding(app, "step a")
            try createIdentity(displayName: "Alice \(suffix)", handle: "alice_\(suffix)", "step a", app)
            return (peer, bystander)
        }
        summary.finish("a")

        summary.start("b")
        try XCTContext.runActivity(named: "step b: app creates group \(leaveGroupName)") { _ in
            try createGroup(leaveGroupName, members: [peer.session, bystander.session], "step b", app)
            _ = try eventually("step b: peer joins \(leaveGroupName)", app) { peer.chatId(named: leaveGroupName) }
            _ = try eventually("step b: bystander joins \(leaveGroupName)", app) {
                bystander.chatId(named: leaveGroupName)
            }
        }
        summary.finish("b")

        summary.start("c")
        try XCTContext.runActivity(named: "step c: app leaves, conversation shows Leaving…") { _ in
            try leaveGroup("step c", app)
            // The peers commit quickly, so Leaving… may already have turned into the left banner.
            let banner = readOnlyBanner(app)
            try require(banner.waitForExistence(timeout: networkTimeout), "step c: read-only banner", app)
            print("[e2e] step c: banner after leaving: '\(banner.label)'")
            try require(
                banner.label.contains("Leaving…") || banner.label.contains("You can no longer send"),
                "step c: banner says Leaving…, found '\(banner.label)'", app)
            try require(!app.textViews["composer.text"].exists, "step c: composer hidden while leaving", app)
        }
        summary.finish("c")

        summary.start("d")
        try XCTContext.runActivity(named: "step d: a peer commits the removal, the chat is left") { _ in
            try waitForLabel(
                readOnlyBanner(app), containing: "You can no longer send messages in this chat.",
                timeout: commitTimeout, "step d: left banner after a peer committed the leave", app)
            try require(!app.textViews["composer.text"].exists, "step d: composer still hidden", app)
            try require(
                app.staticTexts["You left"].waitForExistence(timeout: networkTimeout), "step d: You left in timeline",
                app)
            try tap(backButton(app), "step d: back to Chats", app)
            try waitForLabel(
                chatRow(leaveGroupName, in: app), containing: "Left", "step d: chat list row of the left chat", app)
        }
        summary.finish("d")

        summary.start("e")
        try XCTContext.runActivity(named: "step e: peer removes the app's user while the app is in the background") {
            _ in
            try createGroup(removalGroupName, members: [peer.session, bystander.session], "step e", app)
            let chatId = try eventually("step e: peer joins \(removalGroupName)", app) {
                peer.chatId(named: removalGroupName)
            }
            let excluded = [peer.session.userId, bystander.session.userId]
            let appUserId = try eventually("step e: peer sees the app's user as member", app) {
                try await peer.chatMembers(chatId: chatId).first { !excluded.contains($0.userId) }?.userId
            }
            // The app stops sync in the background, so it learns of the removal only after coming back.
            XCUIDevice.shared.press(.home)
            _ = app.wait(for: .runningBackgroundSuspended, timeout: 5)
            try waitForPeer("step e: peer removes the app's user", app) {
                try await peer.removeMember(chatId: chatId, userId: appUserId)
            }
            app.activate()
            let text = "After removal \(suffix)"
            if app.textViews["composer.text"].waitForExistence(timeout: 5), app.buttons["composer.send"].exists {
                try send(text, "step e", app)
            } else {
                removalSendOutcome = "no-composer"
            }
            try waitForLabel(
                readOnlyBanner(app), containing: "You can no longer send messages in this chat.",
                timeout: commitTimeout, "step e: left banner after the removal", app)
            try require(
                app.staticTexts
                    .matching(NSPredicate(format: "label BEGINSWITH 'You were removed'")).firstMatch
                    .waitForExistence(timeout: networkTimeout),
                "step e: You were removed … in timeline", app)
            guard removalSendOutcome == "n/a" else { return }
            scrollToLatest(app)
            guard messageText(text, in: app).waitForExistence(timeout: 2) else {
                // Sync applied the removal first and the app refused the send (ChatNotActive): no message.
                removalSendOutcome = "refused"
                return
            }
            // Sent before the removal was known: a definite rejection, never an endless Sending.
            let notSent = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier == 'timeline.message.status' AND label == 'Not sent'"))
                .firstMatch
            try require(
                notSent.waitForExistence(timeout: networkTimeout), "step e: the rejected message shows Not sent", app)
            removalSendOutcome = "rejected"
        }
        summary.finish("e", removalSendOutcome)

        summary.start("f")
        try XCTContext.runActivity(named: "step f: chat list shows the removal, sign out") { _ in
            try tap(backButton(app), "step f: back to Chats", app)
            try waitForLabel(
                chatRow(removalGroupName, in: app), containing: "You were removed", "step f: chat list subtitle", app)
            try signOut(app)
            try require(
                app.buttons["onboarding.create"].waitForExistence(timeout: networkTimeout),
                "step f: onboarding visible after sign-out", app)
        }
        summary.finish("f")
    }
}
