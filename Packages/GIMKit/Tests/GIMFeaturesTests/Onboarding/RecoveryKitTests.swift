import Foundation
import GIMFeatures
import XCTest

/// The display helpers of the recovery kit; formatting and parsing are gim-core's (see FakeRecoveryKitFunctionsTests).
final class RecoveryKitTests: XCTestCase {
    private let userId = "u" + String(repeating: "abcdefghijklmnopqrstuvwxyz234567", count: 2).prefix(54) + "q"
    private let code = "7BQ2-K9MX-4TVA-0HZR-PC63-W8NE-1SJD-5GFY-QK2M-V7R"

    func testGroupedCodeHasBlocksOfFour() {
        XCTAssertEqual(RecoveryKit.groupedRecoveryCode(""), "")
        XCTAssertEqual(RecoveryKit.groupedRecoveryCode("7BQ"), "7BQ")
        XCTAssertEqual(RecoveryKit.groupedRecoveryCode("7BQ2"), "7BQ2")
        XCTAssertEqual(RecoveryKit.groupedRecoveryCode("7BQ2K"), "7BQ2-K")
        XCTAssertEqual(RecoveryKit.groupedRecoveryCode(RecoveryKit.normalizedRecoveryCode(code.lowercased())), code)
    }

    func testNormalizeDropsSeparatorsAndMapsAmbiguousLetters() {
        XCTAssertEqual(RecoveryKit.normalizedRecoveryCode(" 7bq2-k9mx\tlo\n"), "7BQ2K9MX10")
        XCTAssertEqual(RecoveryKit.normalizedRecoveryCode("i"), "1")
    }

    func testNormalizedUserIdIsTrimmedAndLowercased() {
        XCTAssertEqual(RecoveryKit.normalizedUserId(" \(userId.uppercased())\n"), userId)
    }
}
