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
    /// UI tests match visible English labels, so the app runs in English whatever the host simulator's language is.
    static let localeArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    /// Shows the notification authorization alert, the notifications and the home screen.
    @MainActor
    var springboard: XCUIApplication { XCUIApplication(bundleIdentifier: "com.apple.springboard") }

    /// Launches the app in English with `serverUrl` as the default server and no keep server (tests never reach
    /// keep.g.im), and signs out a leftover session, so onboarding is in front. Every UI test launches through here,
    /// after setting its own launch arguments.
    @MainActor
    func launchToOnboarding(_ app: XCUIApplication, _ step: String) throws {
        app.launchArguments +=
            ["-GIMDefaultServerURL", serverUrl, "-GIMDefaultKeepServerURL", "off"] + Self.localeArguments
        app.launch()
        try signOutIfNeeded(app)
        try expectOnboarding(app, step)
    }

    /// Requires the welcome screen and checks that the server field, revealed with "Use another server", is
    /// pre-filled with `serverUrl`, which proves that the launch argument reached the app. The other smoke tests may
    /// reuse it after a sign-out.
    @MainActor
    func expectOnboarding(_ app: XCUIApplication, _ step: String) throws {
        try require(
            app.buttons["onboarding.create"].waitForExistence(timeout: networkTimeout),
            "\(step): onboarding Create account button visible", app)
        // The field is hidden behind the button while a default server exists.
        let useAnotherServer = app.buttons["onboarding.useAnotherServer"]
        let serverField = app.textFields["onboarding.serverUrl"]
        // At accessibility text sizes the lazy list has not created the row below the fold yet.
        for _ in 0..<5 where !useAnotherServer.exists && !serverField.exists {
            scrollUpFrontmost(app)
        }
        if useAnotherServer.exists {
            try tap(useAnotherServer, "\(step): Use another server button", app)
        }
        for _ in 0..<5 where !serverField.waitForExistence(timeout: 1) {
            scrollUpFrontmost(app)
        }
        try require(
            serverField.waitForExistence(timeout: networkTimeout), "\(step): onboarding server field visible", app)
        try require(
            serverField.value as? String == serverUrl,
            "\(step): server field pre-filled with \(serverUrl), found \(String(describing: serverField.value))", app)
        // At accessibility text sizes the focused field's keyboard and the scrolled list cover the Create account
        // button: Return dismisses the keyboard, then the list scrolls back to the button. `isHittable` is not enough:
        // a button scrolled under the navigation bar is still "hittable" in the status bar strip, where a tap scrolls
        // the list to the top instead.
        let create = app.buttons["onboarding.create"]
        let createVisible = { () -> Bool in
            guard create.exists else { return false }
            let keyboard = app.keyboards.firstMatch
            let bottom = keyboard.exists ? keyboard.frame.minY : app.windows.firstMatch.frame.maxY
            return create.frame.minY >= app.navigationBars.firstMatch.frame.maxY && create.frame.maxY <= bottom
        }
        guard !createVisible() else { return }
        if app.keyboards.firstMatch.exists {
            serverField.typeText("\n")
        }
        for _ in 0..<5 where !createVisible() {
            scrollDownFrontmost(app)
        }
        try require(createVisible(), "\(step): Create account button fully visible", app)
    }

    /// An account created by `createIdentity`: the recovery code as shown, groups separated by `-`, and the user ID.
    struct CreatedAccount {
        let recoveryCode: String
        let userId: String
    }

    /// Creates an account from onboarding (display name, recovery key, its last 4 characters) and waits for the chat
    /// list.
    @MainActor
    @discardableResult
    func createIdentity(displayName: String, _ step: String, _ app: XCUIApplication) throws -> CreatedAccount {
        try revealAndTap(app.buttons["onboarding.create"], "\(step): Create account button", app)
        // Return submits the form, like the Create button that the keyboard may cover.
        try revealAndType(
            "\(displayName)\n", into: app.textFields["identity.displayName"], "\(step): display name", app)
        let code = app.descendants(matching: .any)["recovery.code"]
        try require(
            code.waitForExistence(timeout: networkTimeout),
            "\(step): recovery code shown (onboarding errors: \(onboardingErrors(app)))", app)
        let recoveryCode = code.label
        let userId = app.descendants(matching: .any)["recovery.userId"].value as? String ?? ""
        try require(userId.hasPrefix("u"), "\(step): account ID shown, found \(userId)", app)
        try revealAndTap(app.buttons["recovery.continue"], "\(step): I saved it button", app)
        let endingField = app.textFields["recovery.ending"]
        try require(
            endingField.waitForExistence(timeout: networkTimeout), "\(step): last 4 characters field visible", app)
        let ending = String(recoveryCode.replacingOccurrences(of: "-", with: "").suffix(4))
        try revealAndType(ending, into: endingField, "\(step): last 4 characters field", app)
        try revealAndTap(app.buttons["recovery.confirm"], "\(step): Confirm button", app)
        let signedIn = app.buttons["chatList.newChat"].waitForExistence(timeout: networkTimeout)
        try require(
            signedIn,
            signedIn
                ? ""
                : "\(step): chat list visible after the recovery kit (onboarding errors: \(onboardingErrors(app)))",
            app)
        allowNotificationsIfAsked()
        return CreatedAccount(recoveryCode: recoveryCode, userId: userId)
    }

    /// Taps Allow when the notification authorization alert, which the app shows after its first sign-in on a
    /// simulator, appears within `timeout`. Returns whether it appeared.
    @MainActor
    @discardableResult
    func allowNotificationsIfAsked(timeout: TimeInterval = 5) -> Bool {
        let allow = springboard.alerts.buttons["Allow"]
        guard allow.waitForExistence(timeout: timeout) else { return false }
        print("[e2e] allowing notifications")
        allow.tap()
        return true
    }

    /// Creates a group from the chat list with `members` (added by Account ID) and waits for its conversation.
    @MainActor
    func createGroup(_ name: String, members: [Session], _ step: String, _ app: XCUIApplication) throws {
        try tap(app.buttons["chatList.newChat"], "\(step): New Chat button", app)
        try tap(app.buttons["newChat.newGroup"], "\(step): New Group row", app)
        try type(name, into: app.textFields["newGroup.name"], "\(step): group name field", app)
        for member in members {
            try type(
                member.userId, into: app.textFields["newGroup.memberAccountId"], "\(step): member Account ID field", app
            )
            try tap(app.buttons["newGroup.addMember"], "\(step): Add button for \(member.displayName)", app)
            // The chip shows the short Account ID: members are not looked up before the group is created.
            let chip = app.buttons["Remove \(member.userId.dropFirst().prefix(8))…"]
            try require(
                chip.waitForExistence(timeout: networkTimeout),
                "\(step): \(member.displayName) added as member chip (footer: \(footerTexts(app)))", app)
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
        try tap(signOut, "sign-out: Sign out button", app)
        // The confirmation dialog's button has the same title.
        let confirm = app.buttons
            .matching(NSPredicate(format: "label == 'Sign out' AND identifier != 'settings.signOut'"))
            .firstMatch
        try tap(confirm, "sign-out: confirmation button", app)
    }

    /// Scrolls the frontmost screen (also a sheet, unlike `collectionViews.firstMatch`) by one swipe up.
    @MainActor
    func scrollUpFrontmost(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)))
    }

    /// Scrolls the frontmost screen by one swipe down, back towards its top.
    @MainActor
    func scrollDownFrontmost(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)))
    }

    /// `tap` after scrolling `element` fully into view: at accessibility text sizes a lazy list has not created the
    /// rows below the fold, and a row under the navigation bar or the keyboard takes no taps (`isHittable` may still
    /// say yes). The keyboard stays up, since Return submits some forms; the swipes stay above it instead.
    @MainActor
    func revealAndTap(_ element: XCUIElement, _ check: @autoclosure () -> String, _ app: XCUIApplication) throws {
        reveal(element, app)
        try tap(element, check(), app)
    }

    /// `type` after scrolling `element` fully into view, like `revealAndTap`.
    @MainActor
    func revealAndType(
        _ text: String, into element: XCUIElement, _ check: @autoclosure () -> String, _ app: XCUIApplication
    ) throws {
        reveal(element, app)
        try type(text, into: element, check(), app)
    }

    /// Waits briefly for `element`, then swipes the visible area (between the navigation bar and the keyboard or the
    /// window's bottom) at most 6 times: up while `element` is missing or below that area, down while it is above.
    @MainActor
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        _ = element.waitForExistence(timeout: 5)
        for _ in 0..<6 {
            let area = visibleArea(app)
            let swipeUp: Bool
            if !element.exists || element.frame.maxY > area.maxY {
                swipeUp = true
            } else if element.frame.minY < area.minY {
                swipeUp = false
            } else {
                return
            }
            let x = app.windows.firstMatch.frame.midX
            let lower = CGPoint(x: x, y: area.minY + area.height * 0.8)
            let upper = CGPoint(x: x, y: area.minY + area.height * 0.2)
            let (from, to) = swipeUp ? (lower, upper) : (upper, lower)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: from.x, dy: from.y))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: to.x, dy: to.y)))
        }
    }

    /// The part of the window where content takes taps: below the navigation bar, above the keyboard.
    @MainActor
    private func visibleArea(_ app: XCUIApplication) -> CGRect {
        let window = app.windows.firstMatch.frame
        let navigationBar = app.navigationBars.firstMatch
        let keyboard = app.keyboards.firstMatch
        let top = navigationBar.exists ? navigationBar.frame.maxY : window.minY
        let bottom = keyboard.exists ? keyboard.frame.minY : window.maxY
        return CGRect(x: window.minX, y: top, width: window.width, height: max(bottom - top, 0))
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
