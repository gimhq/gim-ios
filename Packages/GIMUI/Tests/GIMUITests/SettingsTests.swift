import GIMFeatures
import SwiftUI
import XCTest

@testable import GIMUI

final class SettingsTests: XCTestCase {
    func testSettingsTableIsCompiledForEnglish() {
        XCTAssertNotNil(
            Bundle.module.path(forResource: "Settings", ofType: "strings", inDirectory: nil, forLocalization: "en"),
            "missing en.lproj/Settings.strings"
        )
    }

    func testSettingsKeysLoadTheEnglishText() {
        for key in ["Settings", "Sign out", "My QR code", "Account ID", "Linked devices", "Theme"] {
            XCTAssertEqual(String(localized: String.LocalizationValue(key), table: "Settings", bundle: .module), key)
        }
        XCTAssertEqual(String(localized: "explainer_title", table: "Explainer", bundle: .module), "How gim works")
    }

    func testAppearanceMapsToColorScheme() {
        XCTAssertNil(AppearanceSetting.system.colorScheme)
        XCTAssertEqual(AppearanceSetting.light.colorScheme, .light)
        XCTAssertEqual(AppearanceSetting.dark.colorScheme, .dark)
    }

    func testAppearanceTitlesAreLocalized() {
        XCTAssertEqual(AppearanceSetting.allCases.map(\.title), ["System", "Light", "Dark"])
    }
}
