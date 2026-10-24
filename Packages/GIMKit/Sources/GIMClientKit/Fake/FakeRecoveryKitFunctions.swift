import Foundation

/// A pure-Swift copy of gim-core's recovery-kit functions (gim-client-sdk `crates/gim-sdk/src/recovery_kit.rs`) for
/// Linux tests and previews. Like the Rust code it works on Unicode scalars (Rust `char`s), not grapheme clusters.
/// GIMPlatform's tests compare it with the gim-core implementation.
public struct FakeRecoveryKitFunctions: RecoveryKitFunctions {
    /// Symbols of a recovery code (24 bytes in Crockford base32).
    static let recoveryCodeSymbols = 39
    /// Symbols the user types back to show they saved the kit.
    static let recoveryKeyEndingSymbols = 4
    private static let group = 4
    private static let crockford = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ".unicodeScalars)
    private static let userIdAlphabet = Set("abcdefghijklmnopqrstuvwxyz234567".utf8)

    public init() {}

    public func formatRecoveryKit(userId: String, recoveryCode: String, labels: RecoveryKitLabels) -> String {
        let symbols = Array(Self.normalizedRecoveryCode(recoveryCode).unicodeScalars)
        let grouped = stride(from: 0, to: symbols.count, by: Self.group)
            .map { String(String.UnicodeScalarView(symbols[$0..<min($0 + Self.group, symbols.count)])) }
            .joined(separator: "-")
        return "\(labels.title)\n\(labels.accountId): \(Self.trimmed(userId).lowercased())\n"
            + "\(labels.recoveryKey): \(grouped)\n\n\(labels.note)\n"
    }

    public func parseRecoveryKit(text: String) -> ParsedRecoveryKit {
        let scalars = text.unicodeScalars
        var tokens: [Range<String.UnicodeScalarView.Index>] = []
        var start: String.UnicodeScalarView.Index?
        for index in scalars.indices {
            let word = Self.isWord(scalars[index])
            if word, start == nil {
                start = index
            } else if !word, let tokenStart = start {
                tokens.append(tokenStart..<index)
                start = nil
            }
        }
        if let start {
            tokens.append(start..<scalars.endIndex)
        }
        let token = { (i: Int) in String(scalars[tokens[i]]) }
        let userIds = tokens.indices.map { Self.isUserId(token($0).lowercased()) }
        let userId = userIds.firstIndex(of: true).map { token($0).lowercased() }

        // Chains of tokens joined by a single '-' or space, split at user ids.
        var chains: [[String]] = []
        for i in tokens.indices {
            if userIds[i] {
                chains.append([])
                continue
            }
            var joined = false
            if i > 0, !userIds[i - 1] {
                let separator = scalars[tokens[i - 1].upperBound..<tokens[i].lowerBound]
                joined = separator.count == 1 && (separator.first == "-" || separator.first == " ")
            }
            if chains.isEmpty || !joined {
                chains.append([])
            }
            chains[chains.count - 1].append(token(i))
        }
        var recoveryCode: String?
        search: for chain in chains {
            for start in chain.indices {
                if let code = Self.code(in: chain, from: start) {
                    recoveryCode = code
                    break search
                }
            }
        }
        return ParsedRecoveryKit(userId: userId, recoveryCode: recoveryCode)
    }

    public func recoveryKeyEnding(recoveryCode: String) -> String {
        let symbols = Self.normalizedRecoveryCode(recoveryCode).unicodeScalars
        return String(String.UnicodeScalarView(symbols.suffix(Self.recoveryKeyEndingSymbols)))
    }

    public func matchesRecoveryKeyEnding(recoveryCode: String, typed: String) -> Bool {
        let typed = Self.normalizedRecoveryCode(typed).unicodeScalars
        return typed.count == Self.recoveryKeyEndingSymbols
            && typed.elementsEqual(recoveryKeyEnding(recoveryCode: recoveryCode).unicodeScalars)
    }

    /// The code's symbols as gim-core reads them: `-` and whitespace dropped, uppercased, `I`/`L` to `1` and `O` to
    /// `0`. Other characters are kept.
    static func normalizedRecoveryCode(_ value: String) -> String {
        var symbols = String.UnicodeScalarView()
        for scalar in value.unicodeScalars where scalar != "-" && !scalar.properties.isWhitespace {
            for upper in scalar.properties.uppercaseMapping.unicodeScalars {
                switch upper {
                case "I", "L": symbols.append("1")
                case "O": symbols.append("0")
                default: symbols.append(upper)
                }
            }
        }
        return String(symbols)
    }

    /// Rust `char::is_alphabetic() || char::is_numeric()`.
    private static func isWord(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .decimalNumber, .letterNumber, .otherNumber: true
        default: scalar.properties.isAlphabetic
        }
    }

    /// Rust `str::trim`: leading and trailing White_Space dropped.
    private static func trimmed(_ value: String) -> String {
        let scalars = value.unicodeScalars
        guard let first = scalars.firstIndex(where: { !$0.properties.isWhitespace }),
            let last = scalars.lastIndex(where: { !$0.properties.isWhitespace })
        else { return "" }
        return String(scalars[first...last])
    }

    /// `"u"` + 55 symbols of lowercase base32, the last one carrying 3 zero bits: the shape of a user id.
    private static func isUserId(_ token: String) -> Bool {
        let bytes = Array(token.utf8)
        return bytes.count == 56 && bytes[0] == UInt8(ascii: "u")
            && bytes[1..<55].allSatisfy(userIdAlphabet.contains) && "aiqy".utf8.contains(bytes[55])
    }

    private static func isValidCode(_ symbols: String) -> Bool {
        let scalars = Array(symbols.unicodeScalars)
        guard scalars.count == recoveryCodeSymbols, let last = scalars.last.flatMap(crockford.firstIndex(of:)) else {
            return false
        }
        return last % 8 == 0 && scalars.allSatisfy(crockford.contains)
    }

    /// The valid code made of `chain`'s tokens from `start` holding exactly `recoveryCodeSymbols` characters, if any.
    private static func code(in chain: [String], from start: Int) -> String? {
        var length = 0
        for end in start..<chain.count {
            length += chain[end].unicodeScalars.count
            if length > recoveryCodeSymbols { return nil }
            if length == recoveryCodeSymbols {
                let symbols = normalizedRecoveryCode(chain[start...end].joined())
                return isValidCode(symbols) ? symbols : nil
            }
        }
        return nil
    }
}
