import Foundation
import GIMClientKit
import GIMFeatures
import GIMPlatform
import UserNotifications

/// Notifications of the signed-in app. Pushes are shown by the Notification Service Extension; in the foreground the
/// app shows none (without a `UNUserNotificationCenter` delegate iOS doesn't present them), its sync updates the UI.
public enum AppNotifications {
    /// `AppModel`'s `signedIn` hook: asks for authorization to show alerts, sounds and badges (the system asks only
    /// once), then registers this build's push token (`PushRegistrar`, from the Info.plist `GIMPushProvider`).
    @MainActor
    public static func signedIn(_ client: any GimClientAPI) async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        let registrar = PushRegistrar(
            provider: Bundle.main.object(forInfoDictionaryKey: PushRegistrar.providerKey) as? String,
            appId: Bundle.main.bundleIdentifier, defaults: AppGroup.defaults)
        guard let registration = registrar.registration() else { return }
        // Best effort: gim-core sends it to hubs that are unreachable now on their next connect, and the next sign-in
        // or launch registers again.
        try? await client.registerPush(registration: registration)
    }
}
