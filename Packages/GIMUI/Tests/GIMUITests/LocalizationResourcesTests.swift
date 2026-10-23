import XCTest

@testable import GIMUI

final class LocalizationResourcesTests: XCTestCase {
    private static let seededTables = ["Common", "Chat", "Contacts", "Hubs", "Devices"]

    func testExplainerTableUsesAndroidResourceNames() {
        XCTAssertEqual(String(localized: "explainer_title", table: "Explainer", bundle: .module), "How gim works")
        XCTAssertEqual(
            String(localized: "explainer_recovery_key_body", table: "Explainer", bundle: .module),
            "Lost all your devices? Your recovery key and Account ID bring your account back. Old chats don't come "
                + "back. Keep the key secret and safe. Never show it to anyone."
        )
    }

    func testEveryAreaTableIsCompiledForEnglish() {
        for table in Self.seededTables {
            XCTAssertNotNil(
                Bundle.module.path(forResource: table, ofType: "strings", inDirectory: nil, forLocalization: "en"),
                "missing en.lproj/\(table).strings"
            )
        }
    }

    func testSeededKeysLoadTheEnglishText() {
        XCTAssertEqual(String(localized: "Try again", table: "Common", bundle: .module), "Try again")
        XCTAssertEqual(String(localized: "Chats", table: "Chat", bundle: .module), "Chats")
        XCTAssertEqual(String(localized: "New chat", table: "Contacts", bundle: .module), "New chat")
        XCTAssertEqual(String(localized: "Servers", table: "Hubs", bundle: .module), "Servers")
        XCTAssertEqual(String(localized: "Devices", table: "Devices", bundle: .module), "Devices")
    }
}
