import Foundation
import GIMFeatures
import XCTest

final class LocalizationResourcesTests: XCTestCase {
    // `String(localized:table:bundle:)` does not exist in swift-corelibs-foundation, so GIMFeatures texts go through
    // `NSLocalizedString`. On Linux the catalog is not compiled and the lookup falls back to the key, which is the
    // English text.
    func testFeaturesCommonKeyLoadsTheEnglishText() {
        XCTAssertEqual(
            NSLocalizedString(
                "Something went wrong. Try again.",
                tableName: "FeaturesCommon",
                bundle: FeaturesLocalization.bundle,
                value: "",
                comment: ""
            ),
            "Something went wrong. Try again."
        )
    }
}
