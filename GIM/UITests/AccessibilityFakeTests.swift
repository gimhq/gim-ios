import XCTest

/// Dynamic Type and VoiceOver checks of the chat list, conversation and composer against the demo client
/// (`-GIMUseFakeCore YES`), no hub needed: at the largest accessibility text size the touch targets stay at least
/// 44 pt and the composer buttons stay put while the text grows; at the default size the composer reads attach, text,
/// send from leading to trailing and the message menu still offers Reply first.
final class AccessibilityFakeTests: E2ETestCase {
    private let summary = StepSummary("AccessibilityFakeTests", steps: ["a", "b", "c"])
    /// The demo client's group (`FakeGimClient.demoGroupChatId`).
    private let groupName = "Aegean Crew"

    @MainActor
    func testDynamicTypeAndVoiceOverWithDemoClient() throws {
        continueAfterFailure = false
        let suffix = UUID().uuidString.prefix(8).lowercased()
        let app = XCUIApplication()
        addTeardownBlock { [summary] in await summary.report() }

        summary.start("a")
        try XCTContext.runActivity(named: "step a: chat list at accessibility XXXL") { _ in
            app.launchArguments += [
                "-GIMUseFakeCore", "YES",
                "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            ]
            try launchToOnboarding(app, "step a")
            try createIdentity(displayName: "Alex \(suffix)", "step a", app)
            let newChat = app.buttons["chatList.newChat"]
            try require(newChat.exists && newChat.isHittable, "step a: New Chat button hittable", app)
            let firstRow = app.buttons.matching(identifier: "chatList.row").firstMatch
            try require(firstRow.waitForExistence(timeout: networkTimeout), "step a: first chat row visible", app)
            try require(
                firstRow.frame.height >= 44, "step a: first row at least 44 pt tall, found \(firstRow.frame.height)",
                app)
            let row = chatRow(groupName, in: app)
            for _ in 0..<5 where !(row.exists && row.isHittable) {
                scrollUpFrontmost(app)
            }
            try require(row.exists, "step a: \(groupName) row visible", app)
            try require(
                row.label.hasPrefix(groupName), "step a: row label starts with the title, found '\(row.label)'", app)
            try require(
                row.frame.height >= 44, "step a: \(groupName) row at least 44 pt tall, found \(row.frame.height)", app)
            attachScreenshot("chat list AX XXXL")
        }
        summary.finish("a")

        summary.start("b")
        try XCTContext.runActivity(named: "step b: composer at accessibility XXXL") { _ in
            try revealAndTap(chatRow(groupName, in: app), "step b: \(groupName) row", app)
            let text = app.textViews["composer.text"]
            let send = app.buttons["composer.send"]
            let attach = app.buttons["composer.attach"]
            try require(text.waitForExistence(timeout: networkTimeout), "step b: composer text view visible", app)
            for (element, name) in [(text, "text view"), (send, "Send button"), (attach, "Attach button")] {
                try require(element.exists && element.isHittable, "step b: composer \(name) hittable", app)
            }
            for (element, name) in [(send, "Send button"), (attach, "Attach button")] {
                let size = element.frame.size
                try require(
                    size.width >= 44 && size.height >= 44, "step b: \(name) at least 44 x 44 pt, found \(size)", app)
            }
            // Measured with the keyboard up, as while typing.
            try tap(text, "step b: composer text view", app)
            let sendMaxY = send.frame.maxY
            let message = (1...6).map { "Line \($0) \(suffix)" }.joined(separator: "\n")
            text.typeText(message)
            try require(
                abs(send.frame.maxY - sendMaxY) <= 2,
                "step b: Send button stays put while the text grows, maxY \(sendMaxY) -> \(send.frame.maxY)", app)
            try require(attach.isHittable, "step b: Attach button hittable with 6 lines", app)
            try tap(send, "step b: Send button", app)
            attachScreenshot("conversation AX XXXL")
        }
        summary.finish("b")

        summary.start("c")
        try XCTContext.runActivity(named: "step c: composer order and message menu at the default size") { _ in
            app.terminate()
            // The demo client keeps no state across launches, so onboarding comes again.
            app.launchArguments = ["-GIMUseFakeCore", "YES"]
            try launchToOnboarding(app, "step c")
            try createIdentity(displayName: "Alex \(suffix)", "step c", app)
            try revealAndTap(chatRow(groupName, in: app), "step c: \(groupName) row", app)
            let text = app.textViews["composer.text"]
            try require(text.waitForExistence(timeout: networkTimeout), "step c: composer text view visible", app)
            let attach = app.buttons["composer.attach"].frame
            let field = text.frame
            let send = app.buttons["composer.send"].frame
            try require(
                attach.minX < field.minX && field.minX < send.minX,
                "step c: attach, text, send from leading to trailing, minX \(attach.minX), \(field.minX), "
                    + "\(send.minX)", app)
            try require(
                [attach.midY, send.midY].allSatisfy { $0 >= field.minY && $0 <= field.maxY },
                "step c: attach and send on the text view's row, \(attach), \(field), \(send)", app)
            let message = "Menu \(suffix)"
            try self.send(message, "step c", app)
            try openMenu(on: messageText(message, in: app), firstItem: "Reply", "step c: message menu", app)
        }
        summary.finish("c")
    }

    @MainActor
    private func attachScreenshot(_ name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
