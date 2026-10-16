import GIMCore
import XCTest

/// The plumbing shared by the E2E smoke tests: the hub URL, onboarding and sign-out, and checks that name their step
/// and attach a screenshot and the app's accessibility tree on failure.
///
/// The hub defaults to `http://127.0.0.1:8080`, which the simulator shares with the host; override it with
/// `TEST_RUNNER_GIM_E2E_SERVER_URL=<url> xcodebuild test …`.
///
/// The tests are synchronous so that `continueAfterFailure = false` stops them at the first failed check; the peer's
/// async calls run in detached tasks that the test waits for (`waitForPeer`).
class E2ETestCase: XCTestCase {
    let serverUrl = ProcessInfo.processInfo.environment["GIM_E2E_SERVER_URL"] ?? "http://127.0.0.1:8080"
    /// For every step that waits on the hub or the other client.
    let networkTimeout: TimeInterval = 30

    /// Launches the app with `serverUrl` as the default server and signs out a leftover session, so onboarding is
    /// in front.
    @MainActor
    func launchToOnboarding(_ app: XCUIApplication, _ step: String) throws {
        app.launchArguments += ["-GIMDefaultServerURL", serverUrl]
        app.launch()
        try signOutIfNeeded(app)
        let serverField = app.textFields["onboarding.serverUrl"]
        try require(
            serverField.waitForExistence(timeout: networkTimeout), "\(step): onboarding server field visible", app)
        try require(
            serverField.value as? String == serverUrl,
            "\(step): server field pre-filled with \(serverUrl), found \(String(describing: serverField.value))", app)
    }

    /// Creates an identity from onboarding (display name, recovery code, the requested recovery group, handle) and
    /// waits for the chat list. Returns the recovery code as shown, groups separated by `-`.
    @MainActor
    @discardableResult
    func createIdentity(displayName: String, handle: String, _ step: String, _ app: XCUIApplication) throws -> String {
        try tap(app.buttons["onboarding.create"], "\(step): Create New Identity button", app)
        // Return submits the form, like the Create Identity button that the keyboard may cover.
        try type("\(displayName)\n", into: app.textFields["identity.displayName"], "\(step): display name", app)
        let code = app.descendants(matching: .any)["recovery.code"]
        try require(
            code.waitForExistence(timeout: networkTimeout),
            "\(step): recovery code shown (onboarding errors: \(onboardingErrors(app)))", app)
        let recoveryCode = code.label
        let groups = recoveryCode.split(separator: "-").map(String.init)
        try tap(app.buttons["recovery.continue"], "\(step): I Wrote It Down button", app)
        // The field's placeholder names the requested group: "Group 3".
        let groupField = app.textFields["recovery.confirmField"]
        try require(groupField.waitForExistence(timeout: networkTimeout), "\(step): group field visible", app)
        let groupNumber = (groupField.placeholderValue ?? "").split(separator: " ").last.flatMap { Int($0) }
        guard let groupNumber, groups.indices.contains(groupNumber - 1) else {
            try require(
                false, "\(step): group \(String(describing: groupNumber)) of \(groups.count) recovery groups", app)
            fatalError("unreachable")
        }
        try type(groups[groupNumber - 1], into: groupField, "\(step): group field", app)
        try tap(app.buttons["recovery.confirm"], "\(step): Confirm button", app)
        try type(handle, into: app.textFields["handle.field"], "\(step): handle field", app)
        try tap(app.buttons["handle.claim"], "\(step): Claim Handle button", app)
        let signedIn = app.buttons["chatList.newChat"].waitForExistence(timeout: networkTimeout)
        try require(
            signedIn,
            signedIn
                ? ""
                : "\(step): chat list visible after claiming the handle (onboarding errors: \(onboardingErrors(app)))",
            app)
        return recoveryCode
    }

    /// Creates a group from the chat list with `members` (added by handle) and waits for its conversation.
    @MainActor
    func createGroup(_ name: String, members: [Session], _ step: String, _ app: XCUIApplication) throws {
        try tap(app.buttons["chatList.newChat"], "\(step): New Chat button", app)
        try tap(app.buttons["newChat.newGroup"], "\(step): New Group row", app)
        try type(name, into: app.textFields["newGroup.name"], "\(step): group name field", app)
        for member in members {
            try type(member.handle, into: app.textFields["newGroup.memberHandle"], "\(step): member handle field", app)
            try tap(app.buttons["newGroup.addMember"], "\(step): Add button for \(member.handle)", app)
            // The chip shows the display name (the hub directory may report the handle as the display name), or
            // @handle when the directory has no display name.
            let chip = app.buttons
                .matching(
                    NSPredicate(
                        format: "label IN %@",
                        ["Remove \(member.displayName)", "Remove \(member.handle)", "Remove @\(member.handle)"])
                )
                .firstMatch
            try require(
                chip.waitForExistence(timeout: networkTimeout),
                "\(step): \(member.handle) added as member chip (footer: \(footerTexts(app)))", app)
        }
        try tap(app.buttons["newGroup.create"], "\(step): Create button (footer: \(footerTexts(app)))", app)
        try require(
            app.textViews["composer.text"].waitForExistence(timeout: networkTimeout),
            "\(step): conversation with composer opened", app)
    }

    /// Types `text` into the composer and taps Send.
    @MainActor
    func send(_ text: String, _ step: String, _ app: XCUIApplication) throws {
        try type(text, into: app.textViews["composer.text"], "\(step): composer text view", app)
        try tap(app.buttons["composer.send"], "\(step): Send button", app)
    }

    /// Taps the timeline's jump button when the newest messages are scrolled out of view.
    @MainActor
    func scrollToLatest(_ app: XCUIApplication) {
        let jump = app.buttons["timeline.jumpToLatest"]
        if jump.exists && jump.isHittable { jump.tap() }
    }

    /// Long-presses a message bubble and waits for its context menu (identified by `firstItem`).
    @MainActor
    func openMenu(
        on message: XCUIElement, firstItem: String = "Reply", _ step: String, _ app: XCUIApplication
    ) throws {
        scrollToLatest(app)
        try require(message.waitForExistence(timeout: networkTimeout), "\(step): message bubble visible", app)
        message.press(forDuration: 1.2)
        try require(menuItem(firstItem, in: app).waitForExistence(timeout: 5), "\(step): context menu open", app)
    }

    /// A context-menu or pull-down-menu item by its title; UIKit exposes these as buttons, menu items or cells
    /// depending on the OS version and element size.
    @MainActor
    func menuItem(_ title: String, in app: XCUIApplication) -> XCUIElement {
        let types = [XCUIElement.ElementType.button, .menuItem, .cell, .staticText].map { NSNumber(value: $0.rawValue) }
        return app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ AND elementType IN %@", title, types as NSArray))
            .firstMatch
    }

    /// The body label of the timeline bubble showing `text`.
    @MainActor
    func messageText(_ text: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "identifier == 'timeline.message.text' AND label == %@", text))
            .firstMatch
    }

    /// The composer's banner of a leaving or left chat.
    @MainActor
    func readOnlyBanner(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["composer.readOnly"]
    }

    /// Waits until `element` exists with a label containing `text`, ignoring case.
    @MainActor
    func waitForLabel(
        _ element: XCUIElement, containing text: String, timeout: TimeInterval? = nil, _ check: String,
        _ app: XCUIApplication
    ) throws {
        let matches = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND label CONTAINS[c] %@", text), object: element)
        let found = XCTWaiter().wait(for: [matches], timeout: timeout ?? networkTimeout) == .completed
        try require(
            found, found ? "" : "\(check) (found \(element.exists ? "'\(element.label)'" : "no element"))", app)
    }

    /// The chat list row of the chat named `title`; its label also holds the subtitle.
    @MainActor
    func chatRow(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier == 'chatList.row' AND label BEGINSWITH %@", title))
            .firstMatch
    }

    /// The form footers' texts (validation and error messages), for failure messages.
    @MainActor
    func footerTexts(_ app: XCUIApplication) -> String {
        let labels = app.cells.staticTexts.allElementsBoundByIndex.map(\.label)
        let footers = labels.filter {
            $0.hasPrefix("Add ") || $0.hasPrefix("No ") || $0.hasPrefix("You ") || $0.hasPrefix("Couldn't")
        }
        return footers.isEmpty ? "none" : footers.joined(separator: " | ")
    }

    /// Fails fast when the hub is not reachable from the test runner. An App Transport Security rejection is only
    /// logged: the runner has no ATS exception, and the peer's registration checks the hub anyway.
    @MainActor
    func checkServerHealth(_ app: XCUIApplication) throws {
        let url = URL(string: "\(serverUrl)/healthz")!
        let status = try waitForPeer("pre-flight: GET \(url)", app) { () async throws -> Int in
            do {
                let (_, response) = try await URLSession.shared.data(from: url)
                return (response as? HTTPURLResponse)?.statusCode ?? -1
            } catch let error as URLError where error.code == .appTransportSecurityRequiresSecureConnection {
                return 0
            }
        }
        if status == 0 {
            print("[e2e] pre-flight: ATS blocked \(url) in the test runner; relying on the peer registration")
            return
        }
        try require(
            status == 200, "pre-flight: \(url) answered \(status); start the hub with `scripts/e2e-hub.sh start`", app)
    }

    /// The navigation bar's back button; iOS 26 identifies it as "BackButton" and may show no title.
    @MainActor
    func backButton(_ app: XCUIApplication, to title: String = "Chats") -> XCUIElement {
        app.navigationBars.buttons
            .matching(NSPredicate(format: "identifier == 'BackButton' OR label == %@", title))
            .firstMatch
    }

    /// Signs out a session left over from an earlier, interrupted run.
    @MainActor
    func signOutIfNeeded(_ app: XCUIApplication) throws {
        let createButton = app.buttons["onboarding.create"]
        let settings = app.buttons["chatList.settings"]
        for _ in 0..<Int(networkTimeout) {
            if createButton.exists { return }
            if settings.exists {
                print("[e2e] signing out a leftover session")
                try signOut(app)
                return
            }
            _ = createButton.waitForExistence(timeout: 1)
        }
    }

    /// Signs out from the chat list, or from Settings when it is already open.
    @MainActor
    func signOut(_ app: XCUIApplication) throws {
        if !app.navigationBars["Settings"].exists {
            try tap(app.buttons["chatList.settings"], "sign-out: Settings button", app)
        }
        // The button is the form's last row, which may be below the fold.
        let signOut = app.buttons["settings.signOut"]
        for _ in 0..<5 where !(signOut.waitForExistence(timeout: 1) && signOut.isHittable) {
            scrollUpFrontmost(app)
        }
        try tap(signOut, "sign-out: Sign Out button", app)
        // The confirmation dialog's button has the same title.
        let confirm = app.buttons
            .matching(NSPredicate(format: "label == 'Sign Out' AND identifier != 'settings.signOut'"))
            .firstMatch
        try tap(confirm, "sign-out: confirmation button", app)
    }

    /// Scrolls the frontmost screen (also a sheet, unlike `collectionViews.firstMatch`) by one swipe up.
    @MainActor
    func scrollUpFrontmost(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)))
    }

    @MainActor
    func type(
        _ text: String, into element: XCUIElement, _ check: @autoclosure () -> String, _ app: XCUIApplication
    ) throws {
        try tap(element, check(), app)
        element.typeText(text)
    }

    @MainActor
    func tap(_ element: XCUIElement, _ check: @autoclosure () -> String, _ app: XCUIApplication) throws {
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND enabled == true"), object: element)
        try require(XCTWaiter().wait(for: [ready], timeout: networkTimeout) == .completed, "\(check()) ready", app)
        element.tap()
    }

    /// Records a failure named after the step, with a screenshot and the accessibility tree, and stops the test.
    @MainActor
    func require(_ condition: Bool, _ check: @autoclosure () -> String, _ app: XCUIApplication) throws {
        guard !condition else { return }
        let check = check()
        attachDiagnostics("Failed: \(check)", app)
        XCTFail("Failed: \(check)")
        throw SmokeTestError.failed(check)
    }

    @MainActor
    func attachDiagnostics(_ name: String, _ app: XCUIApplication) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "\(name) (screenshot)"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "\(name) (accessibility tree)"
        tree.lifetime = .keepAlways
        add(tree)
    }

    /// The red error texts of the onboarding form, if any.
    @MainActor
    func onboardingErrors(_ app: XCUIApplication) -> String {
        let labels = app.staticTexts.allElementsBoundByIndex.map(\.label)
        let errors = labels.filter { $0.hasPrefix("Couldn't") || $0.hasPrefix("Can't") || $0.contains("error") }
        return errors.isEmpty ? "none" : errors.joined(separator: " | ")
    }

    /// Polls `probe` every 250 ms until it returns a value, for state of the scripted peer that has no UI to wait on.
    @MainActor
    func eventually<T: Sendable>(
        _ check: String, _ app: XCUIApplication, _ probe: @escaping @Sendable () async throws -> T?
    ) throws -> T {
        let timeout = networkTimeout
        let value = try waitForPeer(check, app, timeout: timeout + 5) { () async throws -> T? in
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if let value = try await probe() { return value }
                try await Task.sleep(for: .milliseconds(250))
            }
            return nil
        }
        guard let value else {
            try require(false, "\(check) within \(Int(timeout)) s", app)
            fatalError("unreachable")
        }
        return value
    }

    /// Runs one async peer operation and waits for it on the main thread, failing the step when it throws or
    /// doesn't finish in time.
    @MainActor
    func waitForPeer<T: Sendable>(
        _ check: String, _ app: XCUIApplication, timeout: TimeInterval? = nil,
        _ operation: @escaping @Sendable () async throws -> T
    ) throws -> T {
        let outcome = OutcomeBox<T>()
        let done = XCTestExpectation(description: check)
        Task.detached {
            do {
                outcome.set(.success(try await operation()))
            } catch {
                outcome.set(.failure(error))
            }
            done.fulfill()
        }
        let waited = XCTWaiter().wait(for: [done], timeout: timeout ?? networkTimeout)
        switch (waited, outcome.value) {
        case (.completed, .success(let value)?):
            return value
        case (.completed, .failure(let error)?):
            try require(false, "\(check): \(error)", app)
        default:
            try require(false, "\(check): no result within \(Int(timeout ?? networkTimeout)) s", app)
        }
        fatalError("unreachable")
    }
}

/// Each step's outcome for the summary line that CI and scripts/mac-gate.sh grep from the xcodebuild log.
@MainActor
final class StepSummary {
    private let name: String
    /// The steps in the order they run.
    private let steps: [String]
    private var results: [String: String] = [:]
    private var running: String?

    nonisolated init(_ name: String, steps: [String]) {
        self.name = name
        self.steps = steps
    }

    func start(_ step: String) { running = step }

    func finish(_ step: String, _ result: String = "pass") {
        results[step] = result
        running = nil
    }

    /// Prints one line, e.g. `[e2e-summary] MessagingSmokeTests a=pass b=pass …`: a finished step is `pass` (or the
    /// result it finished with, spaces replaced by `_`), the step that was running when the test stopped is `fail`,
    /// and steps never reached are `n/a`.
    func report() {
        let fields = steps.map { step in
            let result = results[step] ?? (step == running ? "fail" : "n/a")
            return "\(step)=\(result.replacingOccurrences(of: " ", with: "_"))"
        }
        print("[e2e-summary] \(name) \(fields.joined(separator: " "))")
    }
}

/// The result of a detached peer operation, handed back to the waiting test.
private final class OutcomeBox<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var outcome: Result<T, any Error>?

    var value: Result<T, any Error>? { lock.withLock { outcome } }

    func set(_ outcome: Result<T, any Error>) {
        lock.withLock { self.outcome = outcome }
    }
}

private enum SmokeTestError: Error, CustomStringConvertible {
    case failed(String)

    var description: String {
        switch self {
        case .failed(let check): "Failed: \(check)"
        }
    }
}
