import Foundation
import GIMFeatures
import XCTest

/// Ports RecoveryKitTest and RecoveryInputTest from gim-android, so both apps read and write the same kit.
final class RecoveryKitTests: XCTestCase {
    private let userId = "u" + String(repeating: "abcdefghijklmnopqrstuvwxyz234567", count: 2).prefix(54) + "q"
    private let code = "7BQ2-K9MX-4TVA-0HZR-PC63-W8NE-1SJD-5GFY-QK2M-V7R"
    private var symbols: String { code.replacingOccurrences(of: "-", with: "") }
    private var full: RecoveryKit.Parsed { RecoveryKit.Parsed(userId: userId, recoveryCode: symbols) }
    private let labels = RecoveryKit.Labels(
        title: "Recovery kit", accountId: "Account ID", recoveryKey: "Recovery key", note: "Keep this safe.")

    func testFormatWritesTheKitLines() {
        let text = RecoveryKit.format(userId: " \(userId.uppercased()) ", recoveryCode: symbols.lowercased(), labels: labels)
        XCTAssertEqual(text, "Recovery kit\nAccount ID: \(userId)\nRecovery key: \(code)\n\nKeep this safe.\n")
    }

    func testFormatThenParseRoundTrips() {
        for code in [code, symbols] {
            XCTAssertEqual(RecoveryKit.parse(RecoveryKit.format(userId: userId, recoveryCode: code, labels: labels)), full)
        }
    }

    func testFormatWithCRLFEndingsRoundTrips() {
        let kit = RecoveryKit.format(userId: userId, recoveryCode: code, labels: labels)
            .replacingOccurrences(of: "\n", with: "\r\n")
        XCTAssertEqual(RecoveryKit.parse(kit), full)
    }

    func testParseIgnoresTheLabels() {
        let spanish = RecoveryKit.Labels(
            title: "Kit de recuperación", accountId: "ID de cuenta", recoveryKey: "Clave de recuperación",
            note: "Guárdalo.")
        let chinese = RecoveryKit.Labels(title: "恢复工具包", accountId: "账户 ID", recoveryKey: "恢复密钥", note: "请妥善保管。")
        for labels in [spanish, chinese] {
            XCTAssertEqual(RecoveryKit.parse(RecoveryKit.format(userId: userId, recoveryCode: code, labels: labels)), full)
        }
        XCTAssertEqual(RecoveryKit.parse("账户 ID：\(userId)\n恢复密钥：\(code)\n"), full)
    }

    func testParseAcceptsLowercaseAndSpacedKeys() {
        XCTAssertEqual(RecoveryKit.parse("Account ID: \(userId)\nRecovery key: \(code.lowercased())\n"), full)
        let spaced = code.replacingOccurrences(of: "-", with: " ")
        XCTAssertEqual(RecoveryKit.parse("Account ID: \(userId)\nRecovery key: \(spaced)\n"), full)
        XCTAssertEqual(RecoveryKit.parse("\(userId) \(symbols)"), full)
    }

    func testParseAcceptsHandCopiedAmbiguousLetters() {
        let copied = code
            .replacingOccurrences(of: "0HZR", with: "OHZR")
            .replacingOccurrences(of: "1SJD", with: "lSJD")
            .replacingOccurrences(of: "PC63", with: "pc63")
        XCTAssertEqual(RecoveryKit.parse("\(userId)\n\(copied)"), full)
        XCTAssertEqual(RecoveryKit.normalizedRecoveryCode(copied), symbols)
    }

    func testParseFindsTheKitInSurroundingText() {
        let kit = RecoveryKit.format(userId: userId, recoveryCode: code, labels: labels)
            .replacingOccurrences(of: "\n", with: "\r\n")
        let spaced = code.replacingOccurrences(of: "-", with: " ")
        let text = "Hi,\r\n\r\nhere is my kit:\r\n\r\n\(kit)\r\nmy key is \(spaced) again.\r\n"
        XCTAssertEqual(RecoveryKit.parse(text), full)
        XCTAssertEqual(RecoveryKit.parse("Account ID: \(userId.uppercased())\r\nRecovery key: \(code)\r\n"), full)
    }

    func testParseReturnsWhateverPartIsThere() {
        XCTAssertEqual(RecoveryKit.parse("my key is \(code)"), RecoveryKit.Parsed(userId: nil, recoveryCode: symbols))
        XCTAssertEqual(RecoveryKit.parse("Account ID: \(userId)"), RecoveryKit.Parsed(userId: userId, recoveryCode: nil))
        let empty = RecoveryKit.Parsed(userId: nil, recoveryCode: nil)
        XCTAssertEqual(RecoveryKit.parse(""), empty)
        XCTAssertEqual(RecoveryKit.parse("  \n\t "), empty)
        XCTAssertEqual(RecoveryKit.parse("hello, this is not a kit at all!"), empty)
    }

    func testParseRejectsBadTokens() {
        let badPadding = String(code.dropLast()) + "S"
        XCTAssertEqual(RecoveryKit.parse("\(userId)\n\(badPadding)"), RecoveryKit.Parsed(userId: userId, recoveryCode: nil))
        // A user ID glued to other letters is not a whole token.
        XCTAssertEqual(RecoveryKit.parse("x\(userId)"), RecoveryKit.Parsed(userId: nil, recoveryCode: nil))
    }

    func testParseNeverTakesTheUserIdAsTheKey() {
        // A valid user ID followed by more symbols must not be read as (part of) a key.
        XCTAssertEqual(RecoveryKit.parse("\(userId)-0000"), RecoveryKit.Parsed(userId: userId, recoveryCode: nil))
        XCTAssertEqual(RecoveryKit.parse("\(userId)-\(code)"), full)
    }

    func testKeyEndingIsTheLastFourSymbols() {
        XCTAssertEqual(RecoveryKit.ending(of: code), "MV7R")
        XCTAssertEqual(RecoveryKit.ending(of: symbols.lowercased()), "MV7R")
    }

    func testKeyEndingMatchIgnoresCaseAndSeparators() {
        let code = String(symbols.dropLast(4)) + "ABCD"
        XCTAssertTrue(RecoveryKit.matchesEnding(code, typed: "ABCD"))
        XCTAssertTrue(RecoveryKit.matchesEnding(code, typed: "abcd"))
        XCTAssertTrue(RecoveryKit.matchesEnding(code, typed: "ab-cd"))
        XCTAssertTrue(RecoveryKit.matchesEnding(code, typed: " a b c d "))
        XCTAssertFalse(RecoveryKit.matchesEnding(code, typed: "ABCE"))
        XCTAssertFalse(RecoveryKit.matchesEnding(code, typed: "BCD"))
        XCTAssertFalse(RecoveryKit.matchesEnding(code, typed: "ABCDE"))
        XCTAssertFalse(RecoveryKit.matchesEnding(code, typed: ""))
    }

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

    func testUserIdValidity() {
        XCTAssertEqual(RecoveryKit.normalizedUserId(" \(userId.uppercased())\n"), userId)
        XCTAssertTrue(RecoveryKit.isValidUserId(userId))
        XCTAssertFalse(RecoveryKit.isValidUserId(userId.uppercased()))
        XCTAssertFalse(RecoveryKit.isValidUserId(String(userId.dropLast()) + "b"))
        XCTAssertFalse(RecoveryKit.isValidUserId(String(userId.dropLast())))
        XCTAssertFalse(RecoveryKit.isValidUserId("x" + userId.dropFirst()))
        XCTAssertFalse(RecoveryKit.isValidUserId("u" + String(repeating: "1", count: 54) + "q"))
    }

    func testBrokenRecoveryCode() {
        XCTAssertFalse(RecoveryKit.isBrokenRecoveryCode(""))
        XCTAssertFalse(RecoveryKit.isBrokenRecoveryCode("7BQ2K"))
        XCTAssertFalse(RecoveryKit.isBrokenRecoveryCode(symbols))
        XCTAssertTrue(RecoveryKit.isValidRecoveryCode(symbols))
        XCTAssertTrue(RecoveryKit.isBrokenRecoveryCode("7BQ2U"))
        XCTAssertTrue(RecoveryKit.isBrokenRecoveryCode(symbols + "0"))
        XCTAssertTrue(RecoveryKit.isBrokenRecoveryCode(String(symbols.dropLast()) + "S"))
        XCTAssertFalse(RecoveryKit.isValidRecoveryCode(String(symbols.dropLast()) + "S"))
    }
}
