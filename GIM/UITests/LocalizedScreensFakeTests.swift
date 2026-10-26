import XCTest

/// Screenshots of the main screens in every shipped language against the demo client (`-GIMUseFakeCore YES`), for a
/// visual check of the translations: onboarding, the chat list, the demo group's conversation and Settings. Navigates
/// by accessibility identifiers only, so it runs in any language. Skipped unless `GIM_SCREENSHOTS` is `1`
/// (`TEST_RUNNER_GIM_SCREENSHOTS=1 xcodebuild test -only-testing:GIMUITests/LocalizedScreensFakeTests …`); the
/// screenshots are kept as attachments named `<language>-<nn>-<screen>`.
final class LocalizedScreensFakeTests: E2ETestCase {
    /// The app's languages and the locale each one runs with.
    private let languages = [("en", "en_US"), ("zh-Hans", "zh_CN"), ("zh-Hant", "zh_TW"), ("es", "es_ES")]
    /// The demo client's group (`FakeGimClient.demoGroupChatId`).
    private let groupName = "Aegean Crew"

    @MainActor
    func testScreenshotsInEveryLanguage() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["GIM_SCREENSHOTS"] == "1", "set TEST_RUNNER_GIM_SCREENSHOTS=1")
        continueAfterFailure = false
        for (language, locale) in languages {
            try XCTContext.runActivity(named: "\(language): screenshots") { _ in
                try captureScreens(language: language, locale: locale)
            }
        }
    }

    @MainActor
    private func captureScreens(language: String, locale: String) throws {
        let suffix = UUID().uuidString.prefix(8).lowercased()
        let app = XCUIApplication()
        // The host simulator's language is not English, so every launch names its language.
        app.launchArguments = [
            "-GIMUseFakeCore", "YES", "-GIMDefaultServerURL", serverUrl, "-GIMDefaultKeepServerURL", "off",
            "-AppleLanguages", "(\(language))", "-AppleLocale", locale,
        ]
        app.launch()
        try signOutIfSignedIn(language, app)
        try require(
            app.buttons["onboarding.create"].waitForExistence(timeout: networkTimeout), "\(language): onboarding", app)
        attachScreenshot("\(language)-01-onboarding", app)

        try createIdentity(displayName: "Alex \(suffix)", handle: "alex_\(suffix)", language, app)
        allowNotificationsInAnyLanguage()
        try require(
            app.buttons["chatList.newChat"].waitForExistence(timeout: networkTimeout), "\(language): chat list", app)
        attachScreenshot("\(language)-02-chatList", app)

        try tap(chatRow(groupName, in: app), "\(language): \(groupName) row", app)
        try require(
            app.textViews["composer.text"].waitForExistence(timeout: networkTimeout), "\(language): conversation", app)
        _ = messageTexts(app).waitForExistence(timeout: networkTimeout)
        attachScreenshot("\(language)-03-chat", app)

        try tap(backButton(app), "\(language): back to the chat list", app)
        try tap(app.buttons["chatList.settings"], "\(language): avatar button", app)
        _ = app.buttons["settings.signOut"].waitForExistence(timeout: 5)
        attachScreenshot("\(language)-04-settings", app)

        try signOutFromSettings(language, app)
    }

    @MainActor
    private func messageTexts(_ app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(identifier: "timeline.message.text").firstMatch
    }

    /// Like `allowNotificationsIfAsked`, without matching the springboard's localized "Allow": the alert's buttons
    /// are Don't Allow, then Allow.
    @MainActor
    private func allowNotificationsInAnyLanguage() {
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: 5), alert.buttons.count > 1 else { return }
        alert.buttons.element(boundBy: 1).tap()
    }

    /// Signs out a session left by the previous language.
    @MainActor
    private func signOutIfSignedIn(_ language: String, _ app: XCUIApplication) throws {
        let create = app.buttons["onboarding.create"]
        let settings = app.buttons["chatList.settings"]
        for _ in 0..<Int(networkTimeout) {
            if create.exists { return }
            if settings.exists {
                allowNotificationsInAnyLanguage()
                try tap(settings, "\(language): avatar button", app)
                try signOutFromSettings(language, app)
                return
            }
            _ = create.waitForExistence(timeout: 1)
        }
    }

    /// Like `signOut`, matching the confirmation by the localized title of the Sign out row.
    @MainActor
    private func signOutFromSettings(_ language: String, _ app: XCUIApplication) throws {
        let signOut = app.buttons["settings.signOut"]
        for _ in 0..<5 where !(signOut.waitForExistence(timeout: 1) && signOut.isHittable) {
            scrollUpFrontmost(app)
        }
        let title = signOut.label
        try tap(signOut, "\(language): Sign out button", app)
        let confirm = app.buttons
            .matching(NSPredicate(format: "label == %@ AND identifier != 'settings.signOut'", title))
            .firstMatch
        try tap(confirm, "\(language): sign-out confirmation", app)
        try require(
            app.buttons["onboarding.create"].waitForExistence(timeout: networkTimeout),
            "\(language): onboarding after sign-out", app)
    }

    @MainActor
    private func attachScreenshot(_ name: String, _ app: XCUIApplication) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
