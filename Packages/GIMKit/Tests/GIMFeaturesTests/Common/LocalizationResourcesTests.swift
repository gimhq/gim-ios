import GIMFeatures
import XCTest

final class LocalizationResourcesTests: XCTestCase {
    // On Linux the catalog is not compiled, so the lookup falls back to the key, which is the English text.
    func testFeaturesCommonKeyLoadsTheEnglishText() {
        XCTAssertEqual(
            String(
                localized: "Something went wrong. Please try again.",
                table: "FeaturesCommon",
                bundle: FeaturesLocalization.bundle
            ),
            "Something went wrong. Please try again."
        )
    }
}
