import Foundation

/// Version lines of the About screen.
public struct AboutInfo: Sendable, Hashable {
    /// "CFBundleShortVersionString (CFBundleVersion)", e.g. "0.1.0 (1)"; "" when the bundle has neither.
    public var appVersion: String
    /// The trimmed contents of the bundled "GIM_CORE_VERSION" file; `nil` when absent or empty.
    public var coreVersion: String?

    public init(appVersion: String, coreVersion: String?) {
        self.appVersion = appVersion
        self.coreVersion = coreVersion
    }

    public static func read(from bundle: Bundle) -> AboutInfo {
        let info = bundle.infoDictionary ?? [:]
        let core = bundle.url(forResource: "GIM_CORE_VERSION", withExtension: nil)
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            .flatMap(coreVersion(fromFileContents:))
        return AboutInfo(
            appVersion: appVersion(
                shortVersion: info["CFBundleShortVersionString"] as? String, build: info["CFBundleVersion"] as? String),
            coreVersion: core)
    }

    static func appVersion(shortVersion: String?, build: String?) -> String {
        guard let shortVersion else { return "" }
        guard let build else { return shortVersion }
        return "\(shortVersion) (\(build))"
    }

    static func coreVersion(fromFileContents text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
