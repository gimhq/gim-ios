import Foundation

/// The recovery kit: the user ID and recovery code written together, so one copy or file restores the account.
/// Same text format and label-independent parser as Android and the gim-client-sdk (formatRecoveryKit,
/// parseRecoveryKit, recoveryKeyEnding, matchesRecoveryKeyEnding).
public enum RecoveryKit {
    /// The localized words of the kit text (SDK: RecoveryKitLabels).
    public struct Labels: Sendable, Equatable {
        public var title: String
        public var accountId: String
        public var recoveryKey: String
        public var note: String

        public init(title: String, accountId: String, recoveryKey: String, note: String) {
            self.title = title
            self.accountId = accountId
            self.recoveryKey = recoveryKey
            self.note = note
        }
    }

    /// What `parse(_:)` found: the normalized, valid user ID and recovery code symbols, or nil for each
    /// (SDK: ParsedRecoveryKit).
    public struct Parsed: Sendable, Equatable {
        public let userId: String?
        public let recoveryCode: String?

        public init(userId: String?, recoveryCode: String?) {
            self.userId = userId
            self.recoveryCode = recoveryCode
        }
    }

    /// 24 bytes in Crockford base32.
    public static let recoveryCodeSymbols = 39
    public static let recoveryCodeGroup = 4
    public static let endingSymbols = 4

    private static let crockford: [Character] = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    // MARK: Kit text

    /// The kit text: title, user ID line, recovery code line (grouped), a blank line and the note
    /// (SDK: formatRecoveryKit).
    public static func format(userId: String, recoveryCode: String, labels: Labels) -> String {
        [
            labels.title,
            "\(labels.accountId): \(normalizedUserId(userId))",
            "\(labels.recoveryKey): \(groupedRecoveryCode(normalizedRecoveryCode(recoveryCode)))",
            "",
            labels.note,
        ].joined(separator: "\n") + "\n"
    }

    /// Finds the user ID and recovery code in `text` without relying on the labels, so a kit in any language or
    /// copied by hand still parses (SDK: parseRecoveryKit). Tokens are runs of letters and digits; the code may be
    /// one token or tokens joined by single `-` or spaces. The user ID token is never part of the code.
    public static func parse(_ text: String) -> Parsed {
        // Maximal runs of letters and digits, as substrings of `text` so the separators between them can be read.
        let tokens = text.split { !($0.isLetter || $0.isNumber) }
        let isUserId = tokens.map { UserID.isValid(String($0)) }
        let userId = UserID.firstValid(in: text)

        // Chains of tokens joined by a single '-' or space, split at the user ID.
        var chains: [[Substring]] = []
        for (index, token) in tokens.enumerated() {
            if isUserId[index] {
                chains.append([])
                continue
            }
            let joined: Bool
            if index == 0 || isUserId[index - 1] {
                joined = false
            } else {
                let separator = text[tokens[index - 1].endIndex..<token.startIndex]
                joined = separator == "-" || separator == " "
            }
            if chains.isEmpty || !joined {
                chains.append([])
            }
            chains[chains.count - 1].append(token)
        }
        var recoveryCode: String?
        for chain in chains where recoveryCode == nil {
            for start in chain.indices {
                if let code = code(in: chain, from: start) {
                    recoveryCode = code
                    break
                }
            }
        }
        return Parsed(userId: userId, recoveryCode: recoveryCode)
    }

    /// The valid code made of `chain`'s tokens from `start` holding exactly `recoveryCodeSymbols` characters, if any.
    private static func code(in chain: [Substring], from start: Int) -> String? {
        var length = 0
        for end in start..<chain.count {
            length += chain[end].count
            if length > recoveryCodeSymbols { return nil }
            if length == recoveryCodeSymbols {
                let symbols = normalizedRecoveryCode(chain[start...end].joined())
                return isValidRecoveryCode(symbols) ? symbols : nil
            }
        }
        return nil
    }

    // MARK: Ending check

    /// The last four symbols of the recovery code, which the user types back to show they saved the kit
    /// (SDK: recoveryKeyEnding).
    public static func ending(of recoveryCode: String) -> String {
        String(normalizedRecoveryCode(recoveryCode).suffix(endingSymbols))
    }

    /// `typed` is the code's ending: four symbols, ignoring case, `-` and whitespace like
    /// `normalizedRecoveryCode(_:)` (SDK: matchesRecoveryKeyEnding).
    public static func matchesEnding(_ recoveryCode: String, typed: String) -> Bool {
        let symbols = normalizedRecoveryCode(typed)
        return symbols.count == endingSymbols && symbols == ending(of: recoveryCode)
    }

    // MARK: User ID and recovery code input

    /// What the user pasted or typed, trimmed and lowercased; same as `UserID.normalized(_:)`.
    public static func normalizedUserId(_ value: String) -> String {
        UserID.normalized(value)
    }

    /// A whole user ID after normalization; same as `UserID.isValid(_:)`.
    public static func isValidUserId(_ value: String) -> Bool {
        UserID.isValid(value)
    }

    /// The recovery code's symbols as gim-core parses them: `-` and whitespace dropped, uppercased, `I`/`L` -> `1`
    /// and `O` -> `0`. Other characters are kept so they can be flagged.
    public static func normalizedRecoveryCode(_ value: String) -> String {
        String(
            value.filter { $0 != "-" && !$0.isWhitespace }.uppercased().map { character -> Character in
                switch character {
                case "I", "L": "1"
                case "O": "0"
                default: character
                }
            })
    }

    /// `symbols` (from `normalizedRecoveryCode(_:)`) is a whole code: 39 symbols, the last one's 3 padding bits zero.
    public static func isValidRecoveryCode(_ symbols: String) -> Bool {
        guard symbols.count == recoveryCodeSymbols, let last = symbols.last, let index = crockford.firstIndex(of: last)
        else { return false }
        return symbols.allSatisfy(crockford.contains) && index % 8 == 0
    }

    /// `symbols` cannot become a valid code by typing more: a foreign character, too long, or bad padding.
    public static func isBrokenRecoveryCode(_ symbols: String) -> Bool {
        symbols.contains { !crockford.contains($0) } || symbols.count > recoveryCodeSymbols
            || (symbols.count == recoveryCodeSymbols && !isValidRecoveryCode(symbols))
    }

    /// Groups `symbols` in blocks of four separated by `-`, as gim-core displays the code.
    public static func groupedRecoveryCode(_ symbols: String) -> String {
        let characters = Array(symbols)
        return stride(from: 0, to: characters.count, by: recoveryCodeGroup)
            .map { String(characters[$0..<min($0 + recoveryCodeGroup, characters.count)]) }
            .joined(separator: "-")
    }
}
