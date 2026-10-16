import Foundation
import GIMClientKit

/// The app's push registration. There is no APNs or FCM yet: only builds whose Info.plist `providerKey` is
/// `mockSimulatorProvider` (Debug) register, with a random token kept in the shared defaults, for the push mock that
/// hands deliveries to `xcrun simctl push`. Release builds leave the key empty and register nothing.
public struct PushRegistrar {
    /// Info.plist key of the push provider.
    public static let providerKey = "GIMPushProvider"
    public static let mockSimulatorProvider = "mock-ios-sim"
    /// The defaults key of the mock token.
    public static let tokenKey = "gim.push.mockToken"

    private let provider: String?
    private let appId: String?
    private let defaults: UserDefaults

    /// - Parameters:
    ///   - provider: the Info.plist `providerKey` value.
    ///   - appId: the bundle id, which the push mock hands to `simctl push`.
    public init(provider: String?, appId: String?, defaults: UserDefaults) {
        self.provider = provider
        self.appId = appId
        self.defaults = defaults
    }

    /// The registration to pass to `GimClientAPI.registerPush(registration:)`, or `nil` when this build registers
    /// nothing. The token (`sim-<uuid>`) is created once and then reused.
    public func registration() -> PushRegistration? {
        guard let provider, provider == Self.mockSimulatorProvider else { return nil }
        let token: String
        if let stored = defaults.string(forKey: Self.tokenKey) {
            token = stored
        } else {
            token = "sim-\(UUID().uuidString.lowercased())"
            defaults.set(token, forKey: Self.tokenKey)
        }
        return PushRegistration(provider: provider, token: token, appId: appId, sandbox: nil, p256dh: nil, auth: nil)
    }
}
