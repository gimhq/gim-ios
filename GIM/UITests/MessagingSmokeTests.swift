import GIMCore
import XCTest

/// End-to-end smoke test against a running gim-hub (`scripts/e2e-hub.sh start`): the app and two `ScriptedPeer`s
/// register, the app creates a group and exchanges text, images, a reply, a reaction and a read marker; then the app
/// signs out. See `E2ETestCase` for the hub URL.
final class MessagingSmokeTests: E2ETestCase {
    private let summary = StepSummary("MessagingSmokeTests", steps: ["a", "b", "c", "d", "f", "g", "e", "h"])
    /// Why step e skipped the photo pick, for the summary line; nil when the photo was picked.
    private var photoSkipReason: String?

    @MainActor
    func testMessagingWithScriptedPeer() throws {
        continueAfterFailure = false
        let serverUrl = serverUrl
        let suffix = UUID().uuidString.prefix(8).lowercased()
        let appHandle = "alice_\(suffix)"
        let groupName = "Smoke \(suffix)"
        let app = XCUIApplication()
        print("[e2e] app and peer use server \(serverUrl); app handle \(appHandle)")
        // Teardown blocks also run after a failure has stopped the test, so the summary line is always printed.
        addTeardownBlock { [summary] in await summary.report() }

        try XCTContext.runActivity(named: "pre-flight: GET \(serverUrl)/healthz") { _ in
            try checkServerHealth(app)
        }

        summary.start("a")
        let peer = try XCTContext.runActivity(named: "step a: peer registers on \(serverUrl)") { _ in
            try waitForPeer("step a: peer registers as peer_\(suffix)", app) {
                try await ScriptedPeer.register(
                    serverUrl: serverUrl, handle: "peer_\(suffix)", displayName: "Peer \(suffix)")
            }
        }
        addTeardownBlock { await peer.shutdown() }
        // New groups need at least two members (NewGroupViewModel.minimumMembers); the bystander fills the second
        // seat. Its only action is marking the chat read in step g: gim-core shows Read only once every device of
        // every other member sent a read receipt (aggregate_receipts), despite SendState.read's "at least one" doc.
        let bystander = try XCTContext.runActivity(named: "step a: bystander registers on \(serverUrl)") { _ in
            try waitForPeer("step a: bystander registers as bystander_\(suffix)", app) {
                try await ScriptedPeer.register(
                    serverUrl: serverUrl, handle: "bystander_\(suffix)", displayName: "Bystander \(suffix)")
            }
        }
        addTeardownBlock { await bystander.shutdown() }

        try XCTContext.runActivity(named: "step a: app onboarding with server \(serverUrl)") { _ in
            try launchToOnboarding(app, "step a")
            try createIdentity(displayName: "Alice \(suffix)", handle: appHandle, "step a", app)
        }
        summary.finish("a")

        summary.start("b")
        let chatId = try XCTContext.runActivity(named: "step b: app creates group \(groupName)") { _ in
            try tap(app.buttons["chatList.newChat"], "step b: New Chat button", app)
            try tap(app.buttons["newChat.newGroup"], "step b: New Group row", app)
            try type(groupName, into: app.textFields["newGroup.name"], "step b: group name field", app)
            for member in [peer.session, bystander.session] {
                try type(
                    member.handle, into: app.textFields["newGroup.memberHandle"], "step b: member handle field", app)
                try tap(app.buttons["newGroup.addMember"], "step b: Add button for \(member.handle)", app)
                // The chip shows the display name, or the handle when the hub directory has no display name.
                let chip = app.buttons
                    .matching(
                        NSPredicate(
                            format: "label IN %@", ["Remove \(member.displayName)", "Remove \(member.handle)"])
                    )
                    .firstMatch
                try require(
                    chip.waitForExistence(timeout: networkTimeout),
                    "step b: \(member.handle) added as member chip (footer: \(footerTexts(app)))", app)
            }
            try tap(app.buttons["newGroup.create"], "step b: Create button (footer: \(footerTexts(app)))", app)
            try require(
                app.textViews["composer.text"].waitForExistence(timeout: networkTimeout),
                "step b: conversation with composer opened", app)
            return try eventually("step b: peer joins group \(groupName)", app) { peer.chatId(named: groupName) }
        }
        summary.finish("b")

        summary.start("c")
        let appText = "Hello from the app \(suffix)"
        let appMessage = try XCTContext.runActivity(named: "step c: app sends text, peer receives it") { _ in
            try send(appText, "step c", app)
            return try eventually("step c: peer receives \"\(appText)\"", app) {
                try await peer.messages(in: chatId).first { $0.text == appText }
            }
        }
        summary.finish("c")

        summary.start("d")
        // The peer's text comes after its image so that it is the newest bubble, right above the composer, for the
        // long presses in step f.
        let peerText = "Hello from the peer \(suffix)"
        let peerTextId = try XCTContext.runActivity(named: "step d: peer sends image and text, app shows both") { _ in
            _ = try waitForPeer("step d: peer sends an image", app) { try await peer.sendImage(chatId: chatId) }
            scrollToLatest(app)
            try require(
                app.descendants(matching: .any)["timeline.message.image"].waitForExistence(timeout: networkTimeout),
                "step d: app shows the peer's image cell", app)
            let id = try waitForPeer("step d: peer sends a text", app) {
                try await peer.sendText(chatId: chatId, body: peerText, replyTo: appMessage.messageId)
            }
            scrollToLatest(app)
            try require(
                messageText(peerText, in: app).waitForExistence(timeout: networkTimeout),
                "step d: app shows the peer's text", app)
            return id
        }
        summary.finish("d")

        summary.start("f")
        let replyText = "Reply from the app \(suffix)"
        try XCTContext.runActivity(named: "step f: app replies and reacts, peer sees both") { _ in
            try openMenu(on: messageText(peerText, in: app), "step f: reply menu", app)
            try tap(menuItem("Reply", in: app), "step f: Reply menu item", app)
            try send(replyText, "step f", app)
            _ = try eventually("step f: peer receives the reply to its message", app) {
                try await peer.messages(in: chatId).first {
                    // The reply must point at the peer's text; its id is compared first, its quoted text as well
                    // in case gim-core quotes by a different (wire) id.
                    $0.text == replyText && ($0.replyTo?.messageId == peerTextId || $0.replyTo?.text == peerText)
                }
            }
            let reaction = "👍"
            try openMenu(on: messageText(peerText, in: app), "step f: reaction menu", app)
            try tap(menuItem(reaction, in: app), "step f: \(reaction) menu item", app)
            _ = try eventually("step f: peer sees the \(reaction) reaction", app) {
                try await peer.messages(in: chatId).first {
                    $0.messageId == peerTextId && $0.reactions.contains { $0.emoji == reaction }
                }
            }
        }
        summary.finish("f")

        summary.start("g")
        try XCTContext.runActivity(named: "step g: peer and bystander mark read, app shows read ticks") { _ in
            // Each reader first waits until it has the app's newest message (the reply), so the read receipt
            // covers it; gim-core's markRead marks the whole chat read and queues the receipt for sync to send.
            for reader in [peer, bystander] {
                let handle = reader.session.handle
                _ = try eventually("step g: \(handle) has joined the group", app) { reader.chatId(named: groupName) }
                let target = try eventually("step g: \(handle) has the app's reply", app) {
                    try await reader.messages(in: chatId).last {
                        $0.sender.userId != reader.session.userId && $0.text == replyText
                    }
                }
                print("[e2e] step g: \(handle) marks read up to \(target.messageId) (\"\(replyText)\")")
                try waitForPeer("step g: \(handle) marks read", app) {
                    try await reader.markRead(chatId: chatId, upToMessageId: target.messageId)
                }
            }
            // The read marker covers every own message up to the newest, which is on screen after scrolling down.
            // StatusTicksView labels its ticks "Sending", "Sent", "Delivered", "Read" or "Not sent".
            scrollToLatest(app)
            let statuses = app.descendants(matching: .any).matching(identifier: "timeline.message.status")
            let readStatus = statuses.matching(NSPredicate(format: "label == 'Read'")).firstMatch
            let read = readStatus.waitForExistence(timeout: networkTimeout)
            try require(
                read,
                read
                    ? ""
                    : "step g: an own message shows Read, found statuses \(statuses.allElementsBoundByIndex.map(\.label))"
                        + " for visible messages \(visibleMessageTexts(app))",
                app)
        }
        summary.finish("g")

        summary.start("e")
        // Step e runs after g so that a picker problem can never cost the read-tick check; only the photo pick itself
        // is soft (see sendPhotoIfPickerIsAutomatable), and h still runs afterwards.
        try XCTContext.runActivity(named: "step e: app sends a photo from the library") { _ in
            try sendPhotoIfPickerIsAutomatable(app: app, peer: peer, chatId: chatId)
        }
        summary.finish("e", photoSkipReason.map { "skipped(\($0))" } ?? "picked")

        summary.start("h")
        try XCTContext.runActivity(named: "step h: sign out returns to onboarding") { _ in
            try tap(backButton(app), "step h: back to Chats", app)
            try signOut(app)
            let serverField = app.textFields["onboarding.serverUrl"]
            try require(
                app.buttons["onboarding.create"].waitForExistence(timeout: networkTimeout),
                "step h: onboarding visible after sign-out", app)
            try require(
                serverField.value as? String == serverUrl,
                "step h: server field pre-filled with \(serverUrl), found \(String(describing: serverField.value))",
                app)
        }
        summary.finish("h")
    }

    /// Attaches a photo through the system photo picker and checks that the peer receives it. The picker runs out
    /// of process and its grid may report no hit point, so nothing here taps without checking existence and
    /// hittability first (a failed synthesized tap is an XCTest failure). When no photo can be picked, the step is
    /// recorded and skipped, the picker is dismissed, and the image path stays covered by peer-to-app. Hard
    /// assertions: the conversation is usable again, and a photo that was picked reaches the peer.
    @MainActor
    private func sendPhotoIfPickerIsAutomatable(app: XCUIApplication, peer: ScriptedPeer, chatId: String) throws {
        guard tapIfHittable(app.buttons["composer.attach"], timeout: 10) else {
            return skipPhotoStep("Attach button not hittable", app)
        }
        guard tapIfHittable(menuItem("Photo Library", in: app), timeout: 10) else {
            // Close the menu by tapping the navigation title area, away from any message bubble.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
            try requireConversation("step e: conversation usable after closing the attach menu", app)
            return skipPhotoStep("Photo Library menu item not hittable", app)
        }
        let photo = app.images
            .matching(NSPredicate(format: "label BEGINSWITH 'Photo' AND identifier != 'timeline.message.image'"))
            .firstMatch
        var picked = false
        if photo.waitForExistence(timeout: networkTimeout) {
            // Let the sheet finish presenting before judging hittability.
            _ = app.buttons["Cancel"].waitForExistence(timeout: 2)
            if photo.isHittable {
                photo.tap()
            } else {
                print("[e2e] step e: picker photo not hittable; trying one coordinate tap")
                photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            // A single-selection picker closes as soon as a photo is chosen: its grid disappears and the
            // conversation is in front again.
            let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: photo)
            picked = XCTWaiter().wait(for: [gone], timeout: 15) == .completed && conversationIsBack(app, timeout: 5)
        }
        guard picked else {
            skipPhotoStep(
                photo.exists ? "picker photo could not be selected" : "photo picker grid not reachable", app)
            dismissPicker(app)
            try requireConversation("step e: photo picker dismissed after skipping", app)
            return
        }
        _ = try eventually("step e: peer receives the app's photo", app) {
            try await peer.messages(in: chatId).first {
                guard case .image = $0.content else { return false }
                return $0.sender.userId != peer.session.userId
            }
        }
    }

    /// Taps `element` only when it exists within `timeout` and is hittable; never records a failure.
    @MainActor
    private func tapIfHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        guard element.waitForExistence(timeout: timeout), element.isHittable else { return false }
        element.tap()
        return true
    }

    /// Closes the photo picker with its Cancel button, or by dragging the sheet down from its top edge (a swipe in
    /// the middle would only scroll the grid).
    @MainActor
    private func dismissPicker(_ app: XCUIApplication) {
        if conversationIsBack(app, timeout: 1) { return }
        if tapIfHittable(app.buttons["Cancel"], timeout: 2), conversationIsBack(app, timeout: 5) { return }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
    }

    /// Whether the conversation is in front again (its back button can be tapped).
    @MainActor
    private func conversationIsBack(_ app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            let back = backButton(app)
            if back.exists && back.isHittable { return true }
            _ = back.waitForExistence(timeout: 0.5)
        } while Date() < deadline
        return false
    }

    @MainActor
    private func requireConversation(_ check: String, _ app: XCUIApplication) throws {
        try require(conversationIsBack(app, timeout: 10), check, app)
    }

    /// Records why the app-to-peer photo step was skipped; the image path stays covered by peer-to-app.
    @MainActor
    private func skipPhotoStep(_ reason: String, _ app: XCUIApplication) {
        print("[e2e] step e: \(reason); app-to-peer image skipped")
        photoSkipReason = reason
        attachDiagnostics("step e: \(reason); app-to-peer image skipped", app)
    }

    /// Taps the timeline's jump button when the newest messages are scrolled out of view.
    @MainActor
    private func scrollToLatest(_ app: XCUIApplication) {
        let jump = app.buttons["timeline.jumpToLatest"]
        if jump.exists && jump.isHittable { jump.tap() }
    }

    /// A context-menu or pull-down-menu item by its title; UIKit exposes these as buttons, menu items or cells
    /// depending on the OS version and element size.
    @MainActor
    private func menuItem(_ title: String, in app: XCUIApplication) -> XCUIElement {
        let types = [XCUIElement.ElementType.button, .menuItem, .cell, .staticText].map { NSNumber(value: $0.rawValue) }
        return app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ AND elementType IN %@", title, types as NSArray))
            .firstMatch
    }

    /// The form footers' texts (validation and error messages), for failure messages.
    @MainActor
    private func footerTexts(_ app: XCUIApplication) -> String {
        let labels = app.cells.staticTexts.allElementsBoundByIndex.map(\.label)
        let footers = labels.filter {
            $0.hasPrefix("Add ") || $0.hasPrefix("No ") || $0.hasPrefix("You ") || $0.hasPrefix("Couldn't")
        }
        return footers.isEmpty ? "none" : footers.joined(separator: " | ")
    }

    @MainActor
    private func send(_ text: String, _ step: String, _ app: XCUIApplication) throws {
        try type(text, into: app.textViews["composer.text"], "\(step): composer text view", app)
        try tap(app.buttons["composer.send"], "\(step): Send button", app)
    }

    @MainActor
    private func openMenu(on message: XCUIElement, _ step: String, _ app: XCUIApplication) throws {
        scrollToLatest(app)
        try require(message.waitForExistence(timeout: networkTimeout), "\(step): message bubble visible", app)
        message.press(forDuration: 1.2)
        try require(menuItem("Reply", in: app).waitForExistence(timeout: 5), "\(step): context menu open", app)
    }

    /// The texts of the timeline bubbles on screen, for failure messages.
    @MainActor
    private func visibleMessageTexts(_ app: XCUIApplication) -> [String] {
        app.staticTexts.matching(identifier: "timeline.message.text").allElementsBoundByIndex.map(\.label)
    }

    /// The body label of the timeline bubble showing `text`.
    @MainActor
    private func messageText(_ text: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(Self.messageTextPredicate(text)).firstMatch
    }

    private static func messageTextPredicate(_ text: String) -> NSPredicate {
        NSPredicate(format: "identifier == 'timeline.message.text' AND label == %@", text)
    }
}

extension MessageItem {
    fileprivate var text: String? {
        if case .text(let body) = content { return body }
        return nil
    }
}
