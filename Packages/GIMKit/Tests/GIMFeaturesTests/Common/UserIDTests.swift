import Foundation
import GIMFeatures
import XCTest

final class UserIDTests: XCTestCase {
    private let userId = "u" + String(repeating: "abcdefghijklmnopqrstuvwxyz234567", count: 2).prefix(54) + "q"

    func testNormalizedTrimsAndLowercases() {
        XCTAssertEqual(UserID.normalized(" \(userId.uppercased())\n"), userId)
        XCTAssertEqual(UserID.normalized(""), "")
    }

    func testIsValid() {
        XCTAssertTrue(UserID.isValid(userId))
        XCTAssertTrue(UserID.isValid(" \(userId.uppercased()) "))
        XCTAssertFalse(UserID.isValid(String(userId.dropLast())))
        XCTAssertFalse(UserID.isValid(userId + "a"))
        XCTAssertFalse(UserID.isValid(String(userId.dropLast()) + "b"))
        XCTAssertFalse(UserID.isValid("x" + userId.dropFirst()))
        XCTAssertFalse(UserID.isValid("u" + String(repeating: "1", count: 54) + "q"))
        XCTAssertFalse(UserID.isValid(""))
    }

    func testFirstValidInText() {
        XCTAssertEqual(UserID.firstValid(in: "Account ID: \(userId.uppercased())\r\nthanks"), userId)
        XCTAssertEqual(UserID.firstValid(in: "账户 ID：\(userId)"), userId)
        XCTAssertNil(UserID.firstValid(in: "hello, no id here"))
        XCTAssertNil(UserID.firstValid(in: ""))
        // A user ID glued to other letters or digits is not a whole token.
        XCTAssertNil(UserID.firstValid(in: "x\(userId)"))
        XCTAssertNil(UserID.firstValid(in: "\(userId)7"))
        XCTAssertEqual(UserID.firstValid(in: "x\(userId) \(userId)-0000"), userId)
    }
}
