import GIMFeatures
import XCTest

final class UserIDTests: XCTestCase {
    /// "u" + 54 base32 symbols + a last symbol with 3 zero bits.
    private let sample = "u" + String(repeating: "a", count: 54) + "a"

    func testSampleIsValid() {
        XCTAssertTrue(UserID.isValid(sample))
    }

    func testNormalizationAcceptsUppercaseAndSurroundingWhitespace() {
        XCTAssertTrue(UserID.isValid("  \n" + sample.uppercased() + " \t"))
        XCTAssertEqual(UserID.normalized("  " + sample.uppercased() + "\n"), sample)
    }

    func testWrongLengthIsInvalid() {
        XCTAssertFalse(UserID.isValid(String(sample.dropLast())))
        XCTAssertFalse(UserID.isValid(sample + "a"))
    }

    func testCharactersOutsideBase32AreInvalid() {
        for bad in ["1", "8", "-"] {
            var characters = Array(sample)
            characters[10] = Character(bad)
            XCTAssertFalse(UserID.isValid(String(characters)), bad)
        }
    }

    func testLastSymbolMustCarryThreeZeroBits() {
        let body = "u" + String(repeating: "a", count: 54)
        XCTAssertFalse(UserID.isValid(body + "b"))
        for last in ["a", "i", "q", "y"] {
            XCTAssertTrue(UserID.isValid(body + last), last)
        }
    }

    func testFirstValidFindsTheIdInsideText() {
        XCTAssertEqual(UserID.firstValid(in: "Account ID: " + sample), sample)
        XCTAssertEqual(UserID.firstValid(in: "gim://" + sample + "/x"), sample)
        XCTAssertEqual(UserID.firstValid(in: sample), sample)
        XCTAssertEqual(UserID.firstValid(in: sample.uppercased()), sample)
    }

    func testFirstValidReturnsNilWithoutAnId() {
        XCTAssertNil(UserID.firstValid(in: "user-alex"))
        XCTAssertNil(UserID.firstValid(in: ""))
        XCTAssertNil(UserID.firstValid(in: "u123 " + String(sample.dropLast())))
    }
}
