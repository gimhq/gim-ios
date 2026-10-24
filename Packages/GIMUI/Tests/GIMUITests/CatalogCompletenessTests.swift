import Foundation
import XCTest

/// Checks every GIMUI and app String Catalog is fully translated, that every key the code looks up exists, and that
/// no user-visible literal bypasses the catalogs. `CatalogAudit` is duplicated verbatim in
/// GIMKit/Tests/GIMFeaturesTests/Common/CatalogCompletenessTests.swift; keep both copies identical.
final class CatalogCompletenessTests: XCTestCase {
    /// The repository root, four levels above this file's directory.
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private static var sources: URL { repoRoot.appendingPathComponent("Packages/GIMUI/Sources/GIMUI") }
    private static var resources: URL { sources.appendingPathComponent("Resources") }
    private static var app: URL { repoRoot.appendingPathComponent("GIM") }

    func testEveryKeyIsTranslatedWithMatchingPlaceholders() throws {
        let catalogs =
            CatalogAudit.catalogs(in: Self.resources)
            + CatalogAudit.catalogs(in: Self.app.appendingPathComponent("Resources"))
        XCTAssertGreaterThan(catalogs.count, 1, "no catalogs found under \(Self.repoRoot.path)")
        XCTAssertTrue(
            catalogs.contains { $0.lastPathComponent == "InfoPlist.xcstrings" }, "InfoPlist.xcstrings not found")
        for catalog in catalogs {
            for issue in try CatalogAudit.catalogIssues(file: catalog) { XCTFail(issue) }
        }
    }

    func testEveryCodeKeyExistsInItsTable() throws {
        let tables = try CatalogAudit.tables(in: Self.resources)
        let files = CatalogAudit.swiftFiles(under: Self.sources)
        XCTAssertGreaterThan(files.count, 0)
        for issue in try CatalogAudit.codeKeyIssues(files: files, tables: tables) { XCTFail(issue) }
    }

    func testNoUserVisibleLiteralOutsideTheCatalogs() throws {
        let files =
            CatalogAudit.swiftFiles(under: Self.repoRoot.appendingPathComponent("Packages/GIMUI/Sources"))
            + CatalogAudit.swiftFiles(under: Self.app, excluding: Self.app.appendingPathComponent("UITests"))
        XCTAssertGreaterThan(files.count, 0)
        for issue in try CatalogAudit.literalIssues(files: files) { XCTFail(issue) }
    }
    func testAuditFlagsABrokenCatalog() {
        let issues = CatalogAudit.catalogIssues(name: "Broken.xcstrings", json: CatalogAudit.brokenSample)
        XCTAssertEqual(issues, CatalogAudit.brokenSampleIssues)
    }

    func testPlaceholdersAreComparedByTypeAllowingReordering() {
        XCTAssertEqual(CatalogAudit.specifiers("%1$@ sent %2$lld"), CatalogAudit.specifiers("%lld von %@"))
        XCTAssertEqual(CatalogAudit.specifiers("%d%% of %ld"), ["integer", "integer"])
        XCTAssertNotEqual(CatalogAudit.specifiers("%@"), CatalogAudit.specifiers("%lld"))
    }
}

// MARK: - Shared audit (identical in GIMKit and GIMUI test targets)

private enum CatalogAudit {
    static let languages = ["en", "es", "zh-Hans", "zh-Hant"]

    // MARK: Catalogs

    static func catalogs(in directory: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasSuffix(".xcstrings") }.sorted().map { directory.appendingPathComponent($0) }
    }

    /// Table name -> keys, for every catalog in `directory`.
    static func tables(in directory: URL) throws -> [String: Set<String>] {
        var tables: [String: Set<String>] = [:]
        for catalog in catalogs(in: directory) {
            let json = try JSONSerialization.jsonObject(with: Data(contentsOf: catalog))
            let strings = (json as? [String: Any])?["strings"] as? [String: Any] ?? [:]
            tables[catalog.deletingPathExtension().lastPathComponent] = Set(strings.keys)
        }
        return tables
    }

    static func catalogIssues(file: URL) throws -> [String] {
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: file))
        return catalogIssues(name: file.lastPathComponent, json: json)
    }

    static func catalogIssues(name: String, json: Any) -> [String] {
        guard let strings = (json as? [String: Any])?["strings"] as? [String: Any] else {
            return ["\(name): no \"strings\" object"]
        }
        var issues: [String] = []
        for key in strings.keys.sorted() {
            let entry = strings[key] as? [String: Any] ?? [:]
            if entry["extractionState"] as? String == "stale" {
                issues.append("\(name): \"\(key)\": extractionState is stale")
            }
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            let english = (localizations["en"] as? [String: Any]).flatMap(units)
            let reference = english?.first { $0.variant == "" || $0.variant == "other" }?.unit?["value"] as? String
            for language in languages {
                let place = "\(name): \"\(key)\" [\(language)]"
                guard let localization = localizations[language] as? [String: Any] else {
                    issues.append("\(place): missing")
                    continue
                }
                guard let units = units(localization) else {
                    issues.append("\(place): neither a stringUnit nor plural variations")
                    continue
                }
                if localization["variations"] != nil, !units.contains(where: { $0.variant == "other" }) {
                    issues.append("\(place): plural variations without \"other\"")
                }
                for (variant, unit) in units {
                    let label = variant.isEmpty ? place : "\(place) plural \(variant)"
                    let state = unit?["state"] as? String ?? "missing"
                    guard state == "translated", let value = unit?["value"] as? String, !value.isEmpty else {
                        issues.append("\(label): state \(state) or empty value")
                        continue
                    }
                    if let reference, specifiers(value) != specifiers(reference) {
                        issues.append(
                            "\(label): placeholders \(specifiers(value)) differ from en \(specifiers(reference))")
                    }
                }
            }
        }
        return issues
    }

    private static func units(_ localization: [String: Any]) -> [(variant: String, unit: [String: Any]?)]? {
        if let unit = localization["stringUnit"] as? [String: Any] { return [("", unit)] }
        guard let plural = (localization["variations"] as? [String: Any])?["plural"] as? [String: Any] else {
            return nil
        }
        return plural.keys.sorted().map { ($0, (plural[$0] as? [String: Any])?["stringUnit"] as? [String: Any]) }
    }

    /// The format specifiers in `value` as a sorted multiset of argument types; `%%` is ignored.
    static func specifiers(_ value: String) -> [String] {
        let pattern = #"%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j)?([@dDiuUxXoOfFeEgGaAcCsSp%])"#
        return matches(pattern, in: value).compactMap { match -> String? in
            switch group(1, of: match, in: value) {
            case "%": nil
            case "@": "object"
            case "d", "D", "i", "u", "U", "x", "X", "o", "O": "integer"
            case "f", "F", "e", "E", "g", "G", "a", "A": "double"
            case "c", "C": "character"
            case "s", "S": "cstring"
            default: "pointer"
            }
        }.sorted()
    }

    // MARK: Sources

    static func swiftFiles(under directory: URL, excluding excluded: URL? = nil) -> [URL] {
        let enumerator = FileManager.default.enumerator(atPath: directory.path)
        var files: [URL] = []
        while let path = enumerator?.nextObject() as? String {
            let url = directory.appendingPathComponent(path)
            if let excluded, url.path.hasPrefix(excluded.path + "/") { continue }
            if path.hasSuffix(".swift") { files.append(url) }
        }
        return files.sorted { $0.path < $1.path }
    }

    /// A Swift string literal on one line; group 1 is its body. Interpolations may nest one level of parentheses.
    private static let literal = #""((?:[^"\\\n]|\\\((?:[^()]|\([^()]*\))*\)|\\.)*)""#
    private static let interpolation = #"\\\((?:[^()]|\([^()]*\))*\)"#
    private static let anySpecifier = #"%(?:\d+\$)?[a-z@]+"#

    /// Every literal first argument of a table lookup must match a key of that table.
    static func codeKeyIssues(files: [URL], tables: [String: Set<String>]) throws -> [String] {
        let lookups = [
            #"\bText\(\s*"# + literal + #"\s*,\s*tableName:\s*"(\w+)""#,
            #"\bString\(\s*localized:\s*"# + literal + #"\s*,\s*table:\s*"(\w+)""#,
            #"\bLocalizedStringResource\(\s*"# + literal + #"\s*,\s*table:\s*"(\w+)""#,
            #"\bNSLocalizedString\(\s*"# + literal + #"\s*,\s*tableName:\s*"(\w+)""#,
        ]
        var issues: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for lookup in lookups {
                for match in matches(lookup, in: text) {
                    let body = group(1, of: match, in: text)
                    let table = group(2, of: match, in: text)
                    let place = "\(file.path):\(line(of: match.range.location, in: text))"
                    guard let keys = tables[table] else {
                        issues.append("\(place): table \(table) not found for \"\(body)\"")
                        continue
                    }
                    let key = try NSRegularExpression(pattern: "^" + keyPattern(body) + "$")
                    if !keys.contains(where: { key.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }
                    ) {
                        issues.append("\(place): \"\(body)\" is not a key of table \(table)")
                    }
                }
            }
        }
        return issues
    }

    /// The literal body as a regex: text is matched exactly, each interpolation matches any format specifier.
    private static func keyPattern(_ body: String) -> String {
        var pattern = ""
        var rest = body[...]
        for match in matches(interpolation, in: body) {
            let range = Range(match.range, in: body)!
            pattern += NSRegularExpression.escapedPattern(
                for: unescape(String(body[rest.startIndex..<range.lowerBound])))
            pattern += anySpecifier
            rest = body[range.upperBound...]
        }
        return pattern + NSRegularExpression.escapedPattern(for: unescape(String(rest)))
    }

    private static func unescape(_ text: String) -> String {
        var result = ""
        var iterator = text.makeIterator()
        while let character = iterator.next() {
            guard character == "\\", let next = iterator.next() else {
                result.append(character)
                continue
            }
            switch next {
            case "n": result.append("\n")
            case "t": result.append("\t")
            case "u":
                var hex = ""
                while let digit = iterator.next(), digit != "}" {
                    if digit != "{" { hex.append(digit) }
                }
                if let scalar = UInt32(hex, radix: 16).flatMap(Unicode.Scalar.init) { result.append(Character(scalar)) }
            default: result.append(next)
            }
        }
        return result
    }

    private static let userVisibleAPIs = [
        "Text(", "Label(", "Button(", "Link(", "Toggle(", "Picker(", "Section(", "Menu(", "TextField(",
        "SecureField(", "LabeledContent(", "ContentUnavailableView(", "navigationTitle(", ".alert(",
        "confirmationDialog(", "accessibilityLabel(", "accessibilityHint(", "accessibilityValue(", "help(",
        "prompt: ", "placeholder: ", ".text = ", ".title = ", "setTitle(", "UIAlertController(title: ",
        "UIAlertAction(title: ", "accessibilityLabel = ", "accessibilityHint = ",
    ]

    /// A string literal passed straight to a user-visible API, unless the same call looks it up in a table.
    static func literalIssues(files: [URL]) throws -> [String] {
        let apis = userVisibleAPIs.map { api in
            let escaped = api.replacingOccurrences(of: ".", with: #"\."#).replacingOccurrences(of: "(", with: #"\("#)
                .replacingOccurrences(of: " ", with: #"\s*"#)
            return api.first!.isLetter ? #"(?<!\w)"# + escaped : escaped
        }
        let pattern = "(" + apis.joined(separator: "|") + #")\s*"# + literal
        var issues: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let utf16 = Array(text.utf16)
            for match in matches(pattern, in: text) {
                let start = match.range.location
                let lineStart = (utf16[..<start].lastIndex(of: 10) ?? -1) + 1
                if String(decoding: utf16[lineStart..<start], as: UTF16.self)
                    .trimmingCharacters(in: .whitespaces).hasPrefix("//")
                {
                    continue
                }
                let body = group(2, of: match, in: text)
                if body.isEmpty || !matches("^(?:" + interpolation + ")+$", in: body).isEmpty { continue }
                let api = group(1, of: match, in: text)
                let call = extent(of: start, in: utf16, isCall: api.contains("("))
                if !matches(#"\btableName:|\btable:|bundle:\s*\.module"#, in: call).isEmpty { continue }
                let snippet = (text as NSString).substring(with: match.range)
                issues.append("\(file.path):\(line(of: start, in: text)): literal outside the catalogs: \(snippet)")
            }
        }
        return issues
    }

    /// `String(format:)` with words in the literal and `NSLocalizedString` without a table bypass the catalogs.
    static func formatIssues(files: [URL]) throws -> [String] {
        var issues: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let utf16 = Array(text.utf16)
            for match in matches(#"\bString\(\s*format:\s*"# + literal, in: text) {
                let body = group(1, of: match, in: text).replacingOccurrences(
                    of: anySpecifier, with: "", options: .regularExpression)
                if body.rangeOfCharacter(from: .letters) != nil {
                    issues.append("\(file.path):\(line(of: match.range.location, in: text)): String(format:) literal")
                }
            }
            for match in matches(#"\bNSLocalizedString\("#, in: text)
            where !extent(of: match.range.location, in: utf16, isCall: true).contains("tableName:") {
                issues.append(
                    "\(file.path):\(line(of: match.range.location, in: text)): NSLocalizedString without table")
            }
        }
        return issues
    }

    /// The call starting at `start` up to its balanced closing parenthesis, or the rest of the line.
    private static func extent(of start: Int, in utf16: [UInt16], isCall: Bool) -> String {
        var end = utf16[start...].firstIndex(of: 10) ?? utf16.count
        if isCall, let open = utf16[start...].firstIndex(of: 40) {
            var depth = 0
            var inString = false
            var index = open
            scan: while index < utf16.count {
                switch (inString, utf16[index]) {
                case (true, 92): index += 1
                case (true, 34), (false, 34): inString.toggle()
                case (false, 40): depth += 1
                case (false, 41):
                    depth -= 1
                    if depth == 0 {
                        end = index + 1
                        break scan
                    }
                default: break
                }
                index += 1
            }
        }
        return String(decoding: utf16[start..<end], as: UTF16.self)
    }

    // MARK: Regex helpers

    private static func matches(_ pattern: String, in text: String) -> [NSTextCheckingResult] {
        let regex = try! NSRegularExpression(pattern: pattern)
        return regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }

    private static func group(_ index: Int, of match: NSTextCheckingResult, in text: String) -> String {
        let range = match.range(at: index)
        return range.location == NSNotFound ? "" : (text as NSString).substring(with: range)
    }

    private static func line(of location: Int, in text: String) -> Int {
        (text as NSString).substring(to: location).filter { $0 == "\n" }.count + 1
    }

    // MARK: Self-test sample

    static var brokenSample: Any {
        func unit(_ value: String, _ state: String = "translated") -> [String: Any] {
            ["stringUnit": ["state": state, "value": value]]
        }
        return [
            "strings": [
                "%lld new": [
                    "localizations": [
                        "en": unit("%lld new"),
                        "es": ["variations": ["plural": ["one": unit("%lld nuevo")]]],
                        "zh-Hans": unit("%@ 新"),
                        "zh-Hant": unit("新", "needs_review"),
                    ]
                ],
                "Old": [
                    "extractionState": "stale",
                    "localizations": ["en": unit("Old"), "es": unit("Viejo"), "zh-Hans": unit("旧")],
                ],
            ]
        ]
    }

    static let brokenSampleIssues = [
        #"Broken.xcstrings: "%lld new" [es]: plural variations without "other""#,
        #"Broken.xcstrings: "%lld new" [zh-Hans]: placeholders ["object"] differ from en ["integer"]"#,
        #"Broken.xcstrings: "%lld new" [zh-Hant]: state needs_review or empty value"#,
        #"Broken.xcstrings: "Old": extractionState is stale"#,
        #"Broken.xcstrings: "Old" [zh-Hant]: missing"#,
    ]
}
