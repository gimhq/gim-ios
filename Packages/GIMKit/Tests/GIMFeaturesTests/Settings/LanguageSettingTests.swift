import Foundation
import GIMFeatures
import XCTest

final class LanguageSettingTests: XCTestCase {
    func testEnglishIsNamedInEnglish() {
        XCTAssertEqual(LanguageSetting.name(forLanguage: "en"), "English")
    }

    func testUnknownLanguageFallsBackToTheIdentifier() {
        XCTAssertFalse(LanguageSetting.name(forLanguage: "zz-ZZ-unknown").isEmpty)
    }

    func testCurrentLanguageNameIsNotEmpty() {
        XCTAssertFalse(LanguageSetting.currentLanguageIdentifier().isEmpty)
        XCTAssertFalse(LanguageSetting.currentLanguageName().isEmpty)
    }
}
