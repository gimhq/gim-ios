import Foundation

/// The colour scheme the user picked in Settings; `.system` follows the device.
public enum AppearanceSetting: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    public static let defaultsKey = "GIMAppearance"

    /// `.system` for a missing or unknown value.
    public static func load(from defaults: UserDefaults) -> AppearanceSetting {
        defaults.string(forKey: defaultsKey).flatMap(AppearanceSetting.init(rawValue:)) ?? .system
    }

    /// `.system` removes the key; the others store their raw value.
    public func save(to defaults: UserDefaults) {
        if self == .system {
            defaults.removeObject(forKey: Self.defaultsKey)
        } else {
            defaults.set(rawValue, forKey: Self.defaultsKey)
        }
    }
}
