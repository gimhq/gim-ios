import GIMFeatures
import XCTest

final class GIMKitVersionTests: XCTestCase {
    func testCurrentVersion() {
        XCTAssertFalse(GIMKitVersion.current.isEmpty)
        XCTAssertEqual(GIMKitVersion.current, "0.1.0")
    }
}
