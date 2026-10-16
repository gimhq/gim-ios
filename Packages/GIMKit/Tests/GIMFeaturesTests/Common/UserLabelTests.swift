import GIMClientKit
import XCTest

@testable import GIMFeatures

final class UserLabelTests: XCTestCase {
    /// A gim-core user id: "u" and 55 base32 characters.
    private let coreId = "u" + "abcdefgh" + String(repeating: "2", count: 47)

    func testNamePrefersDisplayNameThenHandleThenShortId() {
        XCTAssertEqual(UserLabel.name(for: UserProfile(userId: coreId, handle: "sofia", displayName: "Sofia")), "Sofia")
        XCTAssertEqual(UserLabel.name(for: UserProfile(userId: coreId, handle: "sofia", displayName: "")), "@sofia")
        XCTAssertEqual(UserLabel.name(for: UserProfile(userId: coreId, handle: "", displayName: "")), "abcdefgh…")
        // gim-core shows the user id as the name until the profile lookup succeeds.
        XCTAssertEqual(UserLabel.name(for: UserProfile(userId: coreId, handle: "", displayName: coreId)), "abcdefgh…")
    }

    func testDetailIsHandleElseShortId() {
        XCTAssertEqual(
            UserLabel.detail(for: UserProfile(userId: coreId, handle: "sofia", displayName: "Sofia")), "@sofia")
        XCTAssertEqual(
            UserLabel.detail(for: UserProfile(userId: coreId, handle: "", displayName: "Marta")), "abcdefgh…")
    }

    func testRenderedNamesShortenOnlyUserIds() {
        XCTAssertEqual(UserLabel.name(coreId), "abcdefgh…")
        XCTAssertEqual(UserLabel.name("Marta"), "Marta")
        XCTAssertEqual(UserLabel.name("u" + String(repeating: "a", count: 54)), "u" + String(repeating: "a", count: 54))
        XCTAssertEqual(UserLabel.name("u" + String(repeating: "-", count: 55)), "u" + String(repeating: "-", count: 55))
    }

    func testShortIdOfOtherIds() {
        XCTAssertEqual(UserLabel.shortUserId("user-marta-k"), "user-mar…")
        XCTAssertEqual(UserLabel.shortUserId("user-kai"), "user-kai")
    }
}
