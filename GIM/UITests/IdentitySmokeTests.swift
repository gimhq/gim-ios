import GIMCore
import XCTest

/// End-to-end identity test against a running gim-hub (`scripts/e2e-hub.sh start`): the app creates an identity,
/// shows its recovery key in Settings, links a `ScriptedLinkingDevice` as a second device by its pasted link code and
/// compares the SAS, writes to the note to self that both devices share, revokes the linked device, then signs out and
/// restores the identity from the recovery code with the other devices revoked. See `E2ETestCase` for the hub URL.
final class IdentitySmokeTests: E2ETestCase {
    private let summary = StepSummary(
        "IdentitySmokeTests", steps: ["create", "settings", "recovery", "link", "note", "devices", "revoke", "restore"])

    @MainActor
    func testCreateLinkRevokeRestore() throws {
        continueAfterFailure = false
        let serverUrl = serverUrl
        let suffix = UUID().uuidString.prefix(8).lowercased()
        let app = XCUIApplication()
        print("[e2e] app and linking device use server \(serverUrl)")
        // Teardown blocks also run after a failure has stopped the test, so the summary line is always printed.
        addTeardownBlock { [summary] in await summary.report() }

        try XCTContext.runActivity(named: "pre-flight: GET \(serverUrl)/healthz") { _ in
            try checkServerHealth(app)
        }

        summary.start("create")
        let recoveryCode = try XCTContext.runActivity(named: "create: app creates an identity") { _ in
            try launchToOnboarding(app, "create")
            return try createIdentity(displayName: "Ida \(suffix)", "create", app).recoveryCode
        }
        summary.finish("create")

        summary.start("settings")
        let (userId, appDeviceId) = try XCTContext.runActivity(named: "settings: user id and this device") { _ in
            try tap(app.buttons["chatList.settings"], "settings: Settings button", app)
            let userId = try shownUserId(app.buttons["settings.userId"], "settings: Settings user id", app)
            try tap(app.buttons["settings.devices"], "settings: Devices row", app)
            let ids = try waitForDeviceIds(count: 1, "settings: Devices lists this device", app)
            try require(
                app.descendants(matching: .any)["devices.current"].exists, "settings: the device is This device", app)
            try require(
                try shownUserId(app.buttons["devices.userId"], "settings: Devices user id", app) == userId,
                "settings: Devices shows the Settings user id", app)
            try tap(backButton(app, to: "Settings"), "settings: back to Settings", app)
            return (userId, ids[0])
        }
        print("[e2e] settings: user \(userId), app device \(appDeviceId)")
        summary.finish("settings")

        summary.start("recovery")
        try XCTContext.runActivity(named: "recovery: Settings shows the recovery key after authentication") { _ in
            // Device authentication is skipped by `-GIMSkipDeviceAuth` (simulators have no passcode).
            try tap(app.buttons["settings.recoveryKey"], "recovery: Recovery key row", app)
            let code = app.descendants(matching: .any)["recoveryKey.code"]
            try require(!code.exists, "recovery: nothing is shown before Show recovery key", app)
            try tap(app.buttons["recoveryKey.show"], "recovery: Show recovery key button", app)
            try require(
                code.waitForExistence(timeout: networkTimeout),
                "recovery: key shown (error: \(app.staticTexts["recoveryKey.error"].label))", app)
            try require(
                code.label == recoveryCode, "recovery: key \"\(code.label)\" is the onboarding key \"\(recoveryCode)\"",
                app)
            try tap(app.buttons["recoveryKey.hide"], "recovery: Hide button", app)
            try require(
                app.buttons["recoveryKey.show"].waitForExistence(timeout: 5) && !code.exists, "recovery: key hidden",
                app)
            try tap(backButton(app, to: "Settings"), "recovery: back to Settings", app)
        }
        summary.finish("recovery")

        summary.start("link")
        let (linked, linkedDeviceId) = try XCTContext.runActivity(named: "link: a new device links by its link code") {
            _ in
            let device = try waitForPeer("link: new device starts a link", app) {
                try await ScriptedLinkingDevice.startLink(serverUrl: serverUrl)
            }
            addTeardownBlock { await device.shutdown() }
            try tap(app.buttons["settings.linkDevice"], "link: Link a New Device row", app)
            try type(device.qrString, into: app.textFields["approve.paste"], "link: link code field", app)
            try tap(app.buttons["approve.submit"], "link: Link Device button", app)
            let sas = app.staticTexts["approve.sas"]
            try require(
                sas.waitForExistence(timeout: networkTimeout),
                "link: app shows the SAS (errors: \(onboardingErrors(app)))", app)
            // gim-core's call order: the new device must have finished waitLink before the old one confirms.
            let deviceSas = try waitForPeer("link: new device waits for the approval", app) {
                try await device.waitLink()
            }
            try require(
                sas.label == deviceSas,
                "link: SAS on the app \"\(sas.label)\" equals the new device's \"\(deviceSas)\"",
                app)
            let session = try waitForPeer("link: new device reads its session", app) { try await device.session() }
            try require(
                session?.userId == userId,
                "link: new device signed in as \(userId), found \(String(describing: session?.userId))", app)
            try waitForPeer("link: new device confirms the SAS", app) { try await device.confirmLink(accepted: true) }
            try tap(app.buttons["approve.match"], "link: Codes Match button", app)
            try tap(app.buttons["approve.done"], "link: Done button (errors: \(onboardingErrors(app)))", app)
            let devices = try eventually("link: new device sees 2 active devices", app) {
                let devices = try await device.devices()
                return devices.filter { !$0.revoked }.count == 2 ? devices : nil
            }
            try require(
                Set(devices.map(\.deviceId)).isSuperset(of: [appDeviceId, session!.deviceId]),
                "link: new device lists \(appDeviceId) and itself, found \(devices.map(\.deviceId))", app)
            return (device, session!.deviceId)
        }
        print("[e2e] link: linked device \(linkedDeviceId)")
        summary.finish("link")

        summary.start("note")
        try XCTContext.runActivity(named: "note: both devices write to the note to self") { _ in
            let linkedCode = try waitForPeer("note: linked device's recovery key", app) { try linked.recoveryCode() }
            try require(linkedCode == nil, "note: a device linked by QR keeps no recovery key", app)
            try waitForPeer("note: linked device starts syncing", app) { try await linked.startSync() }
            try tap(app.buttons["settings.noteToSelf"], "note: Note to self row", app)
            try require(
                app.navigationBars["Note to self"].waitForExistence(timeout: networkTimeout),
                "note: the note to self opens", app)
            let fromApp = "Note from the app \(suffix)"
            try send(fromApp, "note", app)
            let chatId = try eventually("note: linked device lists the note to self", app) {
                linked.noteToSelfChatId()
            }
            _ = try eventually("note: linked device has the app's note", app) { () async -> Bool? in
                let messages = (try? await linked.messages(in: chatId)) ?? []
                return messages.contains {
                    if case .text(let body) = $0.content { body == fromApp } else { false }
                } ? true : nil
            }
            let fromLinked = "Note from the linked device \(suffix)"
            _ = try waitForPeer("note: linked device writes a note", app) {
                try await linked.sendText(chatId: chatId, body: fromLinked)
            }
            try require(
                messageText(fromLinked, in: app).waitForExistence(timeout: networkTimeout),
                "note: the app shows the linked device's note", app)
            try tap(backButton(app), "note: back to the chat list", app)
            let first = app.buttons.matching(identifier: "chatList.row").firstMatch
            try require(
                first.waitForExistence(timeout: networkTimeout) && first.label.hasPrefix("Note to self"),
                "note: the note to self is the first chat, found \"\(first.label)\"", app)
            try tap(app.buttons["chatList.settings"], "note: Settings button", app)
        }
        summary.finish("note")

        summary.start("devices")
        try XCTContext.runActivity(named: "devices: the app lists both devices") { _ in
            try tap(app.buttons["settings.devices"], "devices: Devices row", app)
            let ids = try waitForDeviceIds(count: 2, "devices: Devices lists 2 devices", app)
            try require(
                Set(ids) == [appDeviceId, linkedDeviceId],
                "devices: Devices lists \(appDeviceId) and \(linkedDeviceId), found \(ids)", app)
            try require(
                deviceRow(linkedDeviceId, app).staticTexts["Active"].exists, "devices: the linked device is Active", app
            )
        }
        summary.finish("devices")

        summary.start("revoke")
        try XCTContext.runActivity(named: "revoke: the app revokes the linked device") { _ in
            try tap(app.buttons["devices.revoke.\(linkedDeviceId)"], "revoke: Remove button", app)
            // The confirmation dialog's button has the same title.
            let confirm = app.buttons
                .matching(NSPredicate(format: "label == 'Remove' AND NOT (identifier BEGINSWITH 'devices.revoke.')"))
                .firstMatch
            try tap(confirm, "revoke: confirmation button", app)
            try require(
                deviceRow(linkedDeviceId, app).staticTexts["Removed"].waitForExistence(timeout: networkTimeout),
                "revoke: the linked device shows Removed", app)
            // Only logged: whether the hub still answers a revoked device is gim-core's and gim-hub's business.
            let view = try waitForPeer("revoke: linked device lists devices", app) { () async -> String in
                do {
                    return try await linked.devices().map { "\($0.deviceId)\($0.revoked ? "(revoked)" : "")" }
                        .joined(separator: ",")
                } catch {
                    return "error \(error)"
                }
            }
            print("[e2e] revoke: linked device's devices() after the revocation: \(view)")
        }
        summary.finish("revoke")

        summary.start("restore")
        try XCTContext.runActivity(named: "restore: sign out and restore from the recovery code") { _ in
            try tap(backButton(app, to: "Settings"), "restore: back to Settings", app)
            try signOut(app)
            try tap(app.buttons["onboarding.restore"], "restore: Restore account button", app)
            // The kit field is multi-line, so it may be a text view.
            let kitField = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier == 'restore.kit' AND elementType IN %@", textInputTypes))
                .firstMatch
            try type(
                "Account ID: \(userId)\nRecovery key: \(recoveryCode)\n", into: kitField, "restore: kit field", app)
            let parsedUserId = app.descendants(matching: .any)["restore.userId"]
            try require(
                parsedUserId.waitForExistence(timeout: networkTimeout) && parsedUserId.value as? String == userId,
                "restore: Account ID parsed from the kit, found \(String(describing: parsedUserId.value))", app)
            try require(
                app.descendants(matching: .any)["restore.code"].exists, "restore: recovery key parsed from the kit",
                app)
            let revokeOthers = app.switches["restore.revokeOthers"]
            try require(
                revokeOthers.waitForExistence(timeout: networkTimeout) && revokeOthers.value as? String == "1",
                "restore: Sign out my other devices is on, found \(String(describing: revokeOthers.value))", app)
            try tap(app.buttons["restore.submit"], "restore: Restore button", app)
            let restored = app.alerts["Account restored"]
            try require(
                restored.waitForExistence(timeout: networkTimeout),
                "restore: Account restored alert (errors: \(onboardingErrors(app)))", app)
            try tap(restored.buttons["Continue"], "restore: Continue button", app)
            try tap(app.buttons["chatList.settings"], "restore: Settings button", app)
            let restoredUserId = try shownUserId(app.buttons["settings.userId"], "restore: Settings user id", app)
            try require(
                restoredUserId == userId, "restore: signed in as \(userId), found \(restoredUserId)", app)
            try tap(app.buttons["settings.devices"], "restore: Devices row", app)
            let ids = try waitForDeviceIds(count: 3, "restore: Devices lists 3 devices", app)
            let current = ids.filter { deviceRow($0, app).descendants(matching: .any)["devices.current"].exists }
            try require(
                current.count == 1 && ![appDeviceId, linkedDeviceId].contains(current[0]),
                "restore: one new device is This device, found \(current) of \(ids)", app)
            for earlier in [appDeviceId, linkedDeviceId] {
                try require(
                    deviceRow(earlier, app).staticTexts["Removed"].exists, "restore: \(earlier) shows Removed", app)
            }
            print("[e2e] restore: restored device \(current[0])")
        }
        summary.finish("restore")
    }

    private var textInputTypes: NSArray {
        [XCUIElement.ElementType.textField, .textView].map { NSNumber(value: $0.rawValue) } as NSArray
    }

    /// The user id on a "User ID" (Settings) or "Account ID" (Devices) row, whose label reads "<title>, <id>".
    @MainActor
    private func shownUserId(_ row: XCUIElement, _ check: String, _ app: XCUIApplication) throws -> String {
        try require(row.waitForExistence(timeout: networkTimeout), "\(check) visible", app)
        let parts = row.label.components(separatedBy: ", ")
            .filter { !$0.isEmpty && $0 != "User ID" && $0 != "Account ID" }
        try require(
            parts.count == 1 && !parts[0].contains(" "), "\(check): one user id in the label \"\(row.label)\"", app)
        return parts[0]
    }

    /// The Devices row of `deviceId`.
    @MainActor
    private func deviceRow(_ deviceId: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["devices.row.\(deviceId)"].firstMatch
    }

    /// Waits until the Devices screen lists `count` devices and returns their ids, top to bottom.
    @MainActor
    private func waitForDeviceIds(count: Int, _ check: String, _ app: XCUIApplication) throws -> [String] {
        let prefix = "devices.row."
        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix))
        var ids: [String] = []
        let deadline = Date().addingTimeInterval(networkTimeout)
        repeat {
            ids = []
            for identifier in rows.allElementsBoundByIndex.map(\.identifier) {
                let id = String(identifier.dropFirst(prefix.count))
                if !ids.contains(id) { ids.append(id) }
            }
            if ids.count == count { return ids }
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        } while Date() < deadline
        try require(false, "\(check), found \(ids)", app)
        fatalError("unreachable")
    }
}
