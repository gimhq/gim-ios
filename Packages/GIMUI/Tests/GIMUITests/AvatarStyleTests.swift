import XCTest

@testable import GIMUI

final class AvatarStyleTests: XCTestCase {
    func testInitialsUseFirstAndLastWords() {
        XCTAssertEqual(AvatarStyle.initials(for: "Sofia Marin"), "SM")
        XCTAssertEqual(AvatarStyle.initials(for: "anna maria di stefano"), "AS")
        XCTAssertEqual(AvatarStyle.initials(for: " nikos "), "N")
        XCTAssertEqual(AvatarStyle.initials(for: ""), "?")
    }

    func testColorIndexIsStableAndInRange() {
        let index = AvatarStyle.colorIndex(for: "user-sofia")
        XCTAssertEqual(index, AvatarStyle.colorIndex(for: "user-sofia"))
        XCTAssertTrue(AvatarStyle.palette.indices.contains(index))
    }
}
