import Foundation
import XCTest

@testable import GIMClientKit

/// Ports the tests of gim-client-sdk `crates/gim-sdk/src/recovery_kit.rs` (and the iOS GIMFeatures port), so the
/// pure-Swift copy behaves like gim-core.
final class FakeRecoveryKitFunctionsTests: XCTestCase {
    private let kit = FakeRecoveryKitFunctions()
    private let userId = "u" + String(repeating: "abcdefghijklmnopqrstuvwxyz234567", count: 2).prefix(54) + "q"
    private let code = "7BQ2-K9MX-4TVA-0HZR-PC63-W8NE-1SJD-5GFY-QK2M-V7R"
    private var symbols: String { code.replacingOccurrences(of: "-", with: "") }
    private var full: ParsedRecoveryKit { ParsedRecoveryKit(userId: userId, recoveryCode: symbols) }
    private let english = RecoveryKitLabels(
        title: "Recovery kit", accountId: "Account ID", recoveryKey: "Recovery key", note: "Keep this safe.")

    private func parse(_ text: String) -> ParsedRecoveryKit {
        kit.parseRecoveryKit(text: text)
    }

    private func format(_ userId: String, _ code: String, _ labels: RecoveryKitLabels) -> String {
        kit.formatRecoveryKit(userId: userId, recoveryCode: code, labels: labels)
    }

    func testFormatWritesTheKitLines() {
        XCTAssertEqual(
            format(" \(userId.uppercased()) ", symbols.lowercased(), english),
            "Recovery kit\nAccount ID: \(userId)\nRecovery key: \(code)\n\nKeep this safe.\n")
    }

    func testFormatThenParseRoundTrips() {
        for code in [code, symbols] {
            XCTAssertEqual(parse(format(userId, code, english)), full)
        }
    }

    func testParseIgnoresTheLabels() {
        let spanish = RecoveryKitLabels(
            title: "Kit de recuperación", accountId: "ID de cuenta", recoveryKey: "Clave de recuperación",
            note: "Guárdalo.")
        let chinese = RecoveryKitLabels(title: "恢复工具包", accountId: "账户 ID", recoveryKey: "恢复密钥", note: "请妥善保管。")
        for labels in [spanish, chinese] {
            XCTAssertEqual(parse(format(userId, code, labels)), full)
        }
        XCTAssertEqual(parse("账户 ID：\(userId)\n恢复密钥：\(code)\n"), full)
    }

    func testParseAcceptsLowercaseAndSpacedKeys() {
        XCTAssertEqual(parse("Account ID: \(userId)\nRecovery key: \(code.lowercased())\n"), full)
        let spaced = code.replacingOccurrences(of: "-", with: " ")
        XCTAssertEqual(parse("Account ID: \(userId)\nRecovery key: \(spaced)\n"), full)
        XCTAssertEqual(parse("\(userId) \(symbols)"), full)
    }

    func testParseAcceptsHandCopiedAmbiguousLetters() {
        let copied =
            code
            .replacingOccurrences(of: "0HZR", with: "OHZR")
            .replacingOccurrences(of: "1SJD", with: "lSJD")
            .replacingOccurrences(of: "PC63", with: "pc63")
        XCTAssertEqual(parse("\(userId)\n\(copied)"), full)
    }

    func testParseFindsTheKitInSurroundingText() {
        let kit = format(userId, code, english).replacingOccurrences(of: "\n", with: "\r\n")
        let spaced = code.replacingOccurrences(of: "-", with: " ")
        XCTAssertEqual(parse("Hi,\r\n\r\nhere is my kit:\r\n\r\n\(kit)\r\nmy key is \(spaced) again.\r\n"), full)
        XCTAssertEqual(parse("Account ID: \(userId.uppercased())\r\nRecovery key: \(code)\r\n"), full)
    }

    func testParseReturnsWhateverPartIsThere() {
        XCTAssertEqual(parse("my key is \(code)"), ParsedRecoveryKit(userId: nil, recoveryCode: symbols))
        XCTAssertEqual(parse("Account ID: \(userId)"), ParsedRecoveryKit(userId: userId, recoveryCode: nil))
        for empty in ["", "  \n\t ", "hello, this is not a kit at all!"] {
            XCTAssertEqual(parse(empty), ParsedRecoveryKit(userId: nil, recoveryCode: nil), empty)
        }
    }

    func testParseRejectsBadTokens() {
        let badPadding = String(code.dropLast()) + "S"
        XCTAssertEqual(parse("\(userId)\n\(badPadding)"), ParsedRecoveryKit(userId: userId, recoveryCode: nil))
        // A user id glued to other letters is not a whole token.
        XCTAssertEqual(parse("x\(userId)"), ParsedRecoveryKit(userId: nil, recoveryCode: nil))
        // `U` is not a Crockford symbol.
        let foreign = String(code.dropFirst()) + "U"
        XCTAssertEqual(parse(foreign), ParsedRecoveryKit(userId: nil, recoveryCode: nil))
    }

    func testParseNeverTakesTheUserIdAsTheKey() {
        XCTAssertEqual(parse("\(userId)-0000"), ParsedRecoveryKit(userId: userId, recoveryCode: nil))
        XCTAssertEqual(parse("\(userId)-\(code)"), full)
    }

    func testKeyEndingCountsUnicodeScalarsAsGimCoreDoes() {
        // gim-core counts Rust `char`s (Unicode scalars), not grapheme clusters: a combining accent is a symbol.
        XCTAssertEqual(kit.recoveryKeyEnding(recoveryCode: "ABCDE\u{301}"), "CDE\u{301}")
    }

    func testKeyEndingIsTheLastFourSymbols() {
        XCTAssertEqual(kit.recoveryKeyEnding(recoveryCode: code), "MV7R")
        XCTAssertEqual(kit.recoveryKeyEnding(recoveryCode: symbols.lowercased()), "MV7R")
        XCTAssertEqual(kit.recoveryKeyEnding(recoveryCode: "a-b"), "AB")
    }

    func testKeyEndingMatchIgnoresCaseAndSeparators() {
        let code = String(symbols.dropLast(4)) + "ABCD"
        for typed in ["ABCD", "abcd", "ab-cd", " a b c d "] {
            XCTAssertTrue(kit.matchesRecoveryKeyEnding(recoveryCode: code, typed: typed), typed)
        }
        for typed in ["ABCE", "BCD", "ABCDE", ""] {
            XCTAssertFalse(kit.matchesRecoveryKeyEnding(recoveryCode: code, typed: typed), typed)
        }
    }
}
