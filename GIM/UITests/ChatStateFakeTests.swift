import XCTest

/// Chat state and failed sends against the demo client (`-GIMUseFakeCore YES`), no hub needed: a send the hub rejects
/// for good (403 `not_member`, armed with `-GIMFakeRejectFirstSend YES`) shows Not sent at once with Retry and Delete,
/// and leaving a group ends in the left banner. The demo client commits a leave after 2 s, often before the UI can be
/// checked, so Leaving… is checked against the hub (ChatStateSmokeTests step c).
///
/// The real hub has no deterministic way to make a send fail with a 4xx: the app learns a removal from sync as soon
/// as it runs, and only a send that races sync gets the rejection (ChatStateSmokeTests step e accepts both outcomes).
final class ChatStateFakeTests: E2ETestCase {
    private let summary = StepSummary("ChatStateFakeTests", steps: ["a", "b", "c", "d"])
    /// The demo client's group (`FakeGimClient.demoGroupChatId`).
    private let groupName = "Aegean Crew"

    @MainActor
    func testRejectedSendAndLeaveWithDemoClient() throws {
        continueAfterFailure = false
        let suffix = UUID().uuidString.prefix(8).lowercased()
        let app = XCUIApplication()
        addTeardownBlock { [summary] in await summary.report() }

        summary.start("a")
        try XCTContext.runActivity(named: "step a: demo client onboarding") { _ in
            app.launchArguments += ["-GIMUseFakeCore", "YES", "-GIMFakeRejectFirstSend", "YES"]
            try launchToOnboarding(app, "step a")
            try createIdentity(displayName: "Alex \(suffix)", handle: "alex_\(suffix)", "step a", app)
            try tap(chatRow(groupName, in: app), "step a: \(groupName) row", app)
        }
        summary.finish("a")

        summary.start("b")
        let text = "Rejected \(suffix)"
        try XCTContext.runActivity(named: "step b: a rejected send shows Not sent with Retry and Delete") { _ in
            try send(text, "step b", app)
            scrollToLatest(app)
            let notSent = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier == 'timeline.message.status' AND label == 'Not sent'"))
                .firstMatch
            // At once: the rejection is final, so there is no pending phase to wait out.
            try require(notSent.waitForExistence(timeout: 5), "step b: the message shows Not sent", app)
            try openMenu(on: messageText(text, in: app), "step b: message menu", app)
            try require(menuItem("Retry", in: app).exists, "step b: Retry menu item", app)
            try tap(menuItem("Delete", in: app), "step b: Delete menu item", app)
            try tap(app.buttons["Delete"], "step b: delete confirmation", app)
            let gone = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"), object: messageText(text, in: app))
            try require(
                XCTWaiter().wait(for: [gone], timeout: networkTimeout) == .completed,
                "step b: the deleted message leaves the timeline", app)
        }
        summary.finish("b")

        summary.start("c")
        try XCTContext.runActivity(named: "step c: leaving ends in the left banner") { _ in
            try leaveGroup("step c", app)
            try require(readOnlyBanner(app).waitForExistence(timeout: networkTimeout), "step c: read-only banner", app)
            try require(!app.textViews["composer.text"].exists, "step c: composer hidden", app)
            try waitForLabel(
                readOnlyBanner(app), containing: "You can no longer send messages in this chat.",
                "step c: left banner", app)
            try require(
                app.staticTexts["You left"].waitForExistence(timeout: networkTimeout), "step c: You left in timeline",
                app)
        }
        summary.finish("c")

        summary.start("d")
        try XCTContext.runActivity(named: "step d: chat list says You left, then sign out") { _ in
            try tap(backButton(app), "step d: back to Chats", app)
            try waitForLabel(chatRow(groupName, in: app), containing: "You left", "step d: chat list subtitle", app)
            try signOut(app)
            try require(
                app.buttons["onboarding.create"].waitForExistence(timeout: networkTimeout),
                "step d: onboarding visible after sign-out", app)
        }
        summary.finish("d")
    }
}

extension E2ETestCase {
    /// Leaves the open group through Group Info and waits until Group Info closed again.
    @MainActor
    func leaveGroup(_ step: String, _ app: XCUIApplication) throws {
        try tap(app.navigationBars.buttons["Group Info"], "\(step): Group Info button", app)
        // The button is the form's last row, below the member list.
        let leave = app.buttons["groupInfo.leave"]
        for _ in 0..<5 where !(leave.exists && leave.isHittable) {
            app.collectionViews.firstMatch.swipeUp()
        }
        try tap(leave, "\(step): Leave Group button", app)
        // The confirmation dialog's button has the same title.
        let confirm = app.buttons
            .matching(NSPredicate(format: "label == 'Leave group' AND identifier != 'groupInfo.leave'"))
            .firstMatch
        try tap(confirm, "\(step): Leave Group confirmation", app)
        let closed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: app.buttons["groupInfo.leave"])
        try require(
            XCTWaiter().wait(for: [closed], timeout: networkTimeout) == .completed,
            "\(step): Group Info closes after leaving", app)
    }
}
