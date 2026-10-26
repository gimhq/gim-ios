import XCTest

/// Settings → Keep server against the demo client (`-GIMUseFakeCore YES`), no hub or keep server needed. UI tests
/// launch with `-GIMDefaultKeepServerURL off` (`E2ETestCase.launchToOnboarding`), so the default is no keep server.
/// Covers turning it on (the built-in address), the http check, a custom address with the restart notice and going
/// back to the default.
final class KeepServerFakeTests: E2ETestCase {
    private let summary = StepSummary("KeepServerFakeTests", steps: ["a", "b", "c", "d"])

    @MainActor
    func testKeepServerSettingWithDemoClient() throws {
        continueAfterFailure = false
        let suffix = UUID().uuidString.prefix(8).lowercased()
        let app = XCUIApplication()
        let toggle = app.switches["keepServer.toggle"]
        let address = app.textFields["keepServer.address"]
        let restart = app.staticTexts["keepServer.restart"]
        addTeardownBlock { [summary] in await summary.report() }

        summary.start("a")
        try XCTContext.runActivity(named: "step a: demo client onboarding, open Keep server, it is off") { _ in
            app.launchArguments += ["-GIMUseFakeCore", "YES"]
            try launchToOnboarding(app, "step a")
            try createIdentity(displayName: "Alex \(suffix)", handle: "alex_\(suffix)", "step a", app)
            try tap(app.buttons["chatList.settings"], "step a: Settings button", app)
            try revealAndTap(app.buttons["settings.keepServer"], "step a: Keep server row", app)
            try require(
                toggle.waitForExistence(timeout: networkTimeout) && toggle.value as? String == "0",
                "step a: keep server off by default, found \(String(describing: toggle.value))", app)
            try require(!address.exists, "step a: no address while off", app)
        }
        summary.finish("a")

        summary.start("b")
        try XCTContext.runActivity(named: "step b: turning it on uses the built-in address and asks to reopen") { _ in
            try flip(toggle, "step b", app)
            try require(
                address.waitForExistence(timeout: networkTimeout) && address.value as? String == "https://keep.g.im",
                "step b: built-in address, found \(String(describing: address.value))", app)
            try require(restart.waitForExistence(timeout: networkTimeout), "step b: restart notice", app)
        }
        summary.finish("b")

        summary.start("c")
        try XCTContext.runActivity(named: "step c: http outside the local network is refused, https is saved") { _ in
            try replaceText(of: address, with: "http://keep-\(suffix).example.eu", "step c: address", app)
            try tap(app.buttons["keepServer.save"], "step c: Save button", app)
            try require(
                app.staticTexts["Use an https:// address. http:// only works on your local network."]
                    .waitForExistence(timeout: networkTimeout), "step c: http error shown", app)
            let custom = "https://keep-\(suffix).example.eu"
            try replaceText(of: address, with: custom, "step c: address", app)
            try tap(app.buttons["keepServer.save"], "step c: Save button", app)
            try require(
                app.buttons["keepServer.reset"].waitForExistence(timeout: networkTimeout),
                "step c: custom address saved, reset offered", app)
            try require(
                address.value as? String == custom, "step c: saved address, found \(String(describing: address.value))",
                app)
        }
        summary.finish("c")

        summary.start("d")
        try XCTContext.runActivity(named: "step d: the default turns it off again, no restart needed") { _ in
            try tap(app.buttons["keepServer.reset"], "step d: Use the default keep server", app)
            let off = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '0'"), object: toggle)
            try require(
                XCTWaiter().wait(for: [off], timeout: networkTimeout) == .completed,
                "step d: off again (the default is off in UI tests)", app)
            try require(!restart.exists, "step d: no restart notice", app)
            try tap(backButton(app, to: "Settings"), "step d: back to Settings", app)
            try tap(app.navigationBars.buttons["Done"], "step d: Settings Done button", app)
            try signOut(app)
        }
        summary.finish("d")
    }

    /// Taps the switch itself: a tap on the middle of a Form toggle row lands on its label.
    @MainActor
    private func flip(_ toggle: XCUIElement, _ step: String, _ app: XCUIApplication) throws {
        try require(toggle.waitForExistence(timeout: networkTimeout), "\(step): keep server switch", app)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    }

    /// Clears `field` and types `text`.
    @MainActor
    private func replaceText(
        of field: XCUIElement, with text: String, _ check: @autoclosure () -> String, _ app: XCUIApplication
    ) throws {
        try tap(field, check(), app)
        let current = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 5))
        field.typeText(text)
    }
}
