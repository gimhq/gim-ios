import Foundation
import XCTest

@testable import GIMFeatures

final class AboutInfoTests: XCTestCase {
    func testAppVersionJoinsShortVersionAndBuild() {
        XCTAssertEqual(AboutInfo.appVersion(shortVersion: "0.1.0", build: "1"), "0.1.0 (1)")
    }

    func testAppVersionWithoutBuildIsTheShortVersion() {
        XCTAssertEqual(AboutInfo.appVersion(shortVersion: "0.1.0", build: nil), "0.1.0")
    }

    func testAppVersionWithoutAnyValueIsEmpty() {
        XCTAssertEqual(AboutInfo.appVersion(shortVersion: nil, build: nil), "")
    }

    func testCoreVersionTrimsTheFileContents() {
        XCTAssertEqual(AboutInfo.coreVersion(fromFileContents: "0.1.0+c1b7503\n"), "0.1.0+c1b7503")
    }

    func testBlankCoreVersionIsNil() {
        XCTAssertNil(AboutInfo.coreVersion(fromFileContents: "  \n"))
    }

    func testReadFromTheTestRunnerBundle() {
        let info = AboutInfo.read(from: Bundle.main)
        XCTAssertNil(info.coreVersion)
        XCTAssertEqual(info, AboutInfo(appVersion: info.appVersion, coreVersion: nil))
    }
}
