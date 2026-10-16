#if DEBUG
    import Foundation
    import GIMClientKit
    import GIMFeatures
    import GIMPlatform
    import Observation
    import SwiftUI
    import UserNotifications

    /// Debug builds with `GIMPushProvider` `mock-ios-sim` only: runs the Notification Service Extension's
    /// `PushNotificationHandler` in-app for a `DebugPushURL`, with an extension-mode client on the App Group's data
    /// directory next to the app's own client (gim-core's `gim.lock` serializes them like two processes). Shows the
    /// result in `DebugPushSheet` and posts it as a local notification after `notificationDelay`, so Springboard shows
    /// the decrypted body once the app is in the background. `simctl push` does not launch service extensions on the
    /// iOS 27 simulator; the UI tests use this instead. `DebugPushURL.holdSyncURL` holds the app's sync
    /// (`AppModel.holdSync`) until the next push has been processed, so the extension-mode client sees the push as the
    /// extension would while the app is not running (e.g. it joins an invited chat itself and shows the invitation).
    @MainActor
    @Observable
    final class DebugPushProcessor {
        /// Long enough for a UI test to read the sheet and go to the home screen.
        static let notificationDelay: TimeInterval = 5

        var presentation: NotificationPresentation?

        static var isEnabled: Bool {
            Bundle.main.object(forInfoDictionaryKey: PushRegistrar.providerKey) as? String
                == PushRegistrar.mockSimulatorProvider
        }

        func handle(_ url: URL, model: AppModel) async {
            guard Self.isEnabled else { return }
            if DebugPushURL.isHoldSync(url) {
                await model.holdSync(true)
                print("[debug-push] sync held")
                return
            }
            guard let payload = DebugPushURL.payload(from: url) else { return }
            let handler = PushNotificationHandler(
                factory: AppModel.defaultFactory(),
                makeHooks: { AppPlatformHooks(dataDirectory: try AppDirectories.dataDirectory.path) },
                serverUrl: AppGroup.defaults.string(forKey: AppGroup.serverUrlKey),
                onFailure: { print("[debug-push] generic content: \($0)") })
            let result = await handler.presentation(payload: payload)
            print("[debug-push] kind=\(result.kind) displayed=\(result.isDisplayed)")
            presentation = result
            if model.isSyncHeld {
                await model.holdSync(false)
                print("[debug-push] sync released")
            }
            guard result.isDisplayed else { return }
            let content = UNMutableNotificationContent()
            content.title = result.title
            content.body = result.body
            content.threadIdentifier = result.threadIdentifier
            if let collapseId = result.collapseId {
                content.userInfo = [PushNotificationHandler.collapseIdKey: collapseId]
            }
            let request = UNNotificationRequest(
                identifier: result.collapseId ?? UUID().uuidString, content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: Self.notificationDelay, repeats: false))
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    /// The mapped push, with accessibility identifiers `debug.push.*` for the UI tests.
    struct DebugPushSheet: View {
        let presentation: NotificationPresentation
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            NavigationStack {
                VStack(alignment: .leading, spacing: 12) {
                    field("Title", presentation.title, id: "debug.push.title")
                    field("Body", presentation.body, id: "debug.push.body")
                    field("Thread", presentation.threadIdentifier, id: "debug.push.threadIdentifier")
                    field("Collapse ID", presentation.collapseId ?? "none", id: "debug.push.collapseId")
                    field("Display", presentation.isDisplayed ? "true" : "false", id: "debug.push.shouldDisplay")
                    field("Kind", String(describing: presentation.kind), id: "debug.push.kind")
                    Spacer()
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .navigationTitle("Processed Push")
                .toolbar {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("debug.push.done")
                }
            }
        }

        private func field(_ name: String, _ value: String, id: String) -> some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.caption).foregroundStyle(.secondary)
                Text(value).accessibilityIdentifier(id)
            }
        }
    }
#endif
