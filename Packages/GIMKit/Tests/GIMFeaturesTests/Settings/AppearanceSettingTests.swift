import Foundation
import GIMFeatures
import XCTest

final class AppearanceSettingTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test-\(UUID())"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    func testFreshDefaultsLoadSystem() {
        XCTAssertEqual(AppearanceSetting.load(from: defaults), .system)
    }

    func testSaveAndLoadRoundTrip() {
        AppearanceSetting.light.save(to: defaults)
        XCTAssertEqual(AppearanceSetting.load(from: defaults), .light)
        AppearanceSetting.dark.save(to: defaults)
        XCTAssertEqual(AppearanceSetting.load(from: defaults), .dark)
    }

    func testUnknownStoredValueLoadsSystem() {
        defaults.set("sepia", forKey: AppearanceSetting.defaultsKey)
        XCTAssertEqual(AppearanceSetting.load(from: defaults), .system)
    }

    func testSavingSystemRemovesTheKey() {
        AppearanceSetting.dark.save(to: defaults)
        AppearanceSetting.system.save(to: defaults)
        XCTAssertNil(defaults.object(forKey: AppearanceSetting.defaultsKey))
        XCTAssertEqual(AppearanceSetting.load(from: defaults), .system)
    }

    func testAllCasesOrder() {
        XCTAssertEqual(AppearanceSetting.allCases, [.system, .light, .dark])
    }
}
