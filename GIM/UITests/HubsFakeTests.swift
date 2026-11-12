import XCTest

/// Settings → Hubs against the demo client (`-GIMUseFakeCore YES`), no hub needed. The demo client's home hub is the
/// onboarding server URL; it verifies an added hub after 1 s and reacts to words in the URL: "unverified" fails with
/// HubNotVerified, "owner" makes the hub own 2 groups. Covers the list, adding (with an inline error), making a hub
/// primary, the home hub alert and removal with the owned groups confirmation.
final class HubsFakeTests: E2ETestCase {
    private let summary = StepSummary("HubsFakeTests", steps: ["a", "b", "c", "d", "e", "f", "g"])

    @MainActor
    func testHubsWithDemoClient() throws {
        continueAfterFailure = false
        let suffix = UUID().uuidString.prefix(8).lowercased()
        let app = XCUIApplication()
        let home = hubKey(serverUrl)
        let secondUrl = "https://hub-b-\(suffix).example.eu"
        let second = hubKey(secondUrl)
        let ownerUrl = "https://owner-\(suffix).example.eu"
        let owner = hubKey(ownerUrl)
        addTeardownBlock { [summary] in await summary.report() }

        summary.start("a")
        try XCTContext.runActivity(named: "step a: demo client onboarding, open Hubs") { _ in
            app.launchArguments += ["-GIMUseFakeCore", "YES"]
            try launchToOnboarding(app, "step a")
            try createIdentity(displayName: "Alex \(suffix)", "step a", app)
            try openHubs("step a", app)
        }
        summary.finish("a")

        summary.start("b")
        try XCTContext.runActivity(named: "step b: the home hub is listed as primary, verified and signed in") { _ in
            try requireHub(home, state: "Connected", signedIn: true, "step b", app)
            try requireBadge("primary", on: home, "step b", app)
            try requireBadge("home", on: home, "step b", app)
        }
        summary.finish("b")

        summary.start("c")
        try XCTContext.runActivity(named: "step c: an unverified hub shows the error inline, another one is added") {
            _ in
            try tap(app.buttons["hubs.add"], "step c: Add Hub button", app)
            try type(
                "https://unverified-\(suffix).example.eu", into: app.textFields["addHub.url"], "step c: URL field", app)
            try tap(app.buttons["addHub.submit"], "step c: Add Hub submit", app)
            try waitForLabel(
                app.staticTexts["addHub.error"], containing: "Couldn't reach a server at this address",
                "step c: HubNotVerified shown inline", app)
            try tap(backButton(app, to: "Servers"), "step c: back to Servers", app)
            try addHub(secondUrl, "step c", app)
            try requireHub(second, state: "Connected", signedIn: true, "step c", app)
        }
        summary.finish("c")

        summary.start("d")
        try XCTContext.runActivity(named: "step d: the added hub becomes primary") { _ in
            try tap(app.buttons["hubs.setPrimary.\(second)"], "step d: Make Primary button", app)
            try requireBadge("primary", on: second, "step d", app)
            try requireBadge("home", on: home, "step d", app)
        }
        summary.finish("d")

        summary.start("e")
        try XCTContext.runActivity(named: "step e: removing the home hub explains why it stays") { _ in
            try requestHubRemoval(home, "step e", app)
            let alert = app.alerts["Can't remove your main server"]
            try require(alert.waitForExistence(timeout: networkTimeout), "step e: home hub alert", app)
            try tap(alert.buttons["OK"], "step e: OK button", app)
            try requireHub(home, state: "Connected", signedIn: true, "step e", app)
        }
        summary.finish("e")

        summary.start("f")
        try XCTContext.runActivity(named: "step f: a hub owning groups is removed after the warning") { _ in
            try addHub(ownerUrl, "step f", app)
            try requireHub(owner, state: "Connected", signedIn: true, "step f", app)
            try requestHubRemoval(owner, "step f", app)
            let alert = app.alerts["Remove server?"]
            try require(alert.waitForExistence(timeout: networkTimeout), "step f: owned groups warning", app)
            try require(
                alert.staticTexts.matching(
                    NSPredicate(format: "label BEGINSWITH 'This server hosts 2 groups you own.'")
                ).firstMatch.exists,
                "step f: warning names the 2 owned groups", app)
            try tap(alert.buttons["Remove anyway"], "step f: Remove Anyway button", app)
            try requireHub(owner, state: "Removed", signedIn: false, "step f", app)
        }
        summary.finish("f")

        summary.start("g")
        try XCTContext.runActivity(named: "step g: removing the primary hub makes the home hub primary again") { _ in
            try requestHubRemoval(second, "step g", app)
            try requireHub(second, state: "Removed", signedIn: false, "step g", app)
            try requireBadge("primary", on: home, "step g", app)
            try closeHubs("step g", app)
            try signOut(app)
        }
        summary.finish("g")
    }
}

extension E2ETestCase {
    /// The row key of the hub at `url` (`HubsViewModel.address(of:)`): its host and port.
    func hubKey(_ url: String) -> String {
        let components = URLComponents(string: url)
        let host = components?.host?.lowercased() ?? url
        return host + (components?.port.map { ":\($0)" } ?? "")
    }

    /// Opens Settings → Hubs from the chat list.
    @MainActor
    func openHubs(_ step: String, _ app: XCUIApplication) throws {
        try tap(app.buttons["chatList.settings"], "\(step): Settings button", app)
        let hubs = app.buttons["settings.hubs"]
        for _ in 0..<3 where !(hubs.waitForExistence(timeout: 2) && hubs.isHittable) {
            scrollUpFrontmost(app)
        }
        try tap(hubs, "\(step): Hubs row", app)
        try require(
            app.descendants(matching: .any)["hubs.list"].waitForExistence(timeout: networkTimeout),
            "\(step): hub list visible", app)
    }

    /// Goes back from Hubs to Settings and closes it.
    @MainActor
    func closeHubs(_ step: String, _ app: XCUIApplication) throws {
        try tap(backButton(app, to: "Settings"), "\(step): back to Settings", app)
        try tap(app.navigationBars.buttons["Done"], "\(step): Settings Done button", app)
    }

    /// Adds the hub at `url` from Hubs and waits for its row.
    @MainActor
    func addHub(_ url: String, _ step: String, _ app: XCUIApplication) throws {
        try tap(app.buttons["hubs.add"], "\(step): Add Hub button", app)
        try type(url, into: app.textFields["addHub.url"], "\(step): URL field", app)
        try tap(app.buttons["addHub.submit"], "\(step): Add Hub submit", app)
        let row = hubRow(hubKey(url), app)
        let found = row.waitForExistence(timeout: networkTimeout)
        let error = app.staticTexts["addHub.error"]
        try require(
            found, "\(step): row of \(url) listed (add error: \(error.exists ? error.label : "none"))", app)
    }

    /// Taps a hub's Remove button and confirms the dialog.
    @MainActor
    func requestHubRemoval(_ key: String, _ step: String, _ app: XCUIApplication) throws {
        try tap(app.buttons["hubs.remove.\(key)"], "\(step): Remove button of \(key)", app)
        // The confirmation dialog's button has the same title.
        let confirm = app.buttons
            .matching(NSPredicate(format: "label == 'Remove' AND NOT (identifier BEGINSWITH 'hubs.remove.')"))
            .firstMatch
        try tap(confirm, "\(step): Remove confirmation", app)
    }

    @MainActor
    func hubRow(_ key: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["hubs.row.\(key)"]
    }

    /// Waits until the hub's row shows `state` and the Signed in indicator (or its absence).
    @MainActor
    func requireHub(
        _ key: String, state: String, signedIn: Bool, timeout: TimeInterval? = nil, _ step: String,
        _ app: XCUIApplication
    ) throws {
        try waitForLabel(
            app.staticTexts["hubs.state.\(key)"], containing: state, timeout: timeout, "\(step): \(key) is \(state)",
            app)
        let indicator = app.descendants(matching: .any)["hubs.signedIn.\(key)"]
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == %@", NSNumber(value: signedIn)), object: indicator)
        try require(
            XCTWaiter().wait(for: [expectation], timeout: timeout ?? networkTimeout) == .completed,
            "\(step): \(key) \(signedIn ? "shows" : "doesn't show") Signed in", app)
    }

    /// Waits until the hub's row carries the `primary` or `home` badge. Compares frames, so it doesn't depend on how
    /// SwiftUI nests the badge in the row's accessibility tree.
    @MainActor
    func requireBadge(_ badge: String, on key: String, _ step: String, _ app: XCUIApplication) throws {
        let row = hubRow(key, app)
        let badges = app.descendants(matching: .any).matching(identifier: "hubs.badge.\(badge)")
        let deadline = Date().addingTimeInterval(networkTimeout)
        repeat {
            if row.exists,
                badges.allElementsBoundByIndex.contains(where: {
                    row.frame.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY))
                })
            {
                return
            }
            Thread.sleep(forTimeInterval: 0.5)
        } while Date() < deadline
        try require(false, "\(step): \(key) has the \(badge) badge", app)
    }
}
