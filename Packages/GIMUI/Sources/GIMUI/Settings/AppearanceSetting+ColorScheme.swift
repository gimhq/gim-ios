import GIMFeatures
import SwiftUI

extension AppearanceSetting {
    /// `nil` follows the device.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var title: String {
        switch self {
        case .system: String(localized: "System", table: "Settings", bundle: .module)
        case .light: String(localized: "Light", table: "Settings", bundle: .module)
        case .dark: String(localized: "Dark", table: "Settings", bundle: .module)
        }
    }
}
