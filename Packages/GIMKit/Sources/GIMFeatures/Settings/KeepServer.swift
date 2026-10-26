import Foundation
import Observation

/// The user's choice of keep server, stored per account in the app's defaults (`KeepServer.load` / `store`).
public enum KeepServerSetting: Sendable, Hashable {
    /// Nothing chosen: the default keep server (`KeepServer.defaultUrl`).
    case automatic
    /// A keep server the user typed, normalised.
    case custom(String)
    /// No keep server: privacy settings are not backed up and reports fail.
    case off
}

/// The gim keep server (gim-keep): backs up the privacy settings (encrypted) and receives reports. On by default with
/// `builtInUrl`; a launch argument or Info.plist value (`defaultUrlKey`) replaces that default, and the user's stored
/// `KeepServerSetting` wins over both. A client gets the result as `ClientConfig.keepServerUrl` when it is created.
public enum KeepServer {
    /// The production keep server: the last fallback of `defaultUrl`.
    public static let builtInUrl = "https://keep.g.im"
    /// Launch argument (`-GIMDefaultKeepServerURL <url>`) and Info.plist key (`GIM_DEFAULT_KEEP_SERVER_URL` build
    /// setting) for the default keep server; `offValue` turns the keep server off by default (UI tests).
    public static let defaultUrlKey = "GIMDefaultKeepServerURL"
    /// Defaults key of the stored `KeepServerSetting`.
    public static let settingKey = "GIMKeepServer"
    /// The `defaultUrlKey` value and the stored value for `.off`.
    public static let offValue = "off"

    /// Why a keep server URL is not accepted; `text` gives the localized message.
    public enum UrlError: Sendable, Hashable {
        case empty
        /// Not an http(s) URL with a host.
        case notAFullAddress
        /// An `http://` URL whose host is not on the local network.
        case notSecure

        /// The localized message.
        public var text: String {
            switch self {
            case .empty: OnboardingValidation.ServerUrlError.empty.text
            case .notAFullAddress: OnboardingValidation.ServerUrlError.notAFullAddress.text
            case .notSecure:
                NSLocalizedString(
                    "Use an https:// address. http:// only works on your local network.", tableName: "FeaturesHubs",
                    bundle: FeaturesLocalization.bundle,
                    value: "Use an https:// address. http:// only works on your local network.", comment: "")
            }
        }
    }

    /// `nil` when the normalised URL is an https URL with a host, or an http URL whose host is local: `localhost`,
    /// `*.local`, a loopback, private or link-local IPv4 address, or `::1`.
    public static func urlErrorKind(_ raw: String) -> UrlError? {
        if let error = OnboardingValidation.serverUrlErrorKind(raw) {
            return error == .empty ? .empty : .notAFullAddress
        }
        let components = URLComponents(string: OnboardingValidation.normalizedServerUrl(raw))
        guard components?.scheme?.lowercased() == "http" else { return nil }
        return isLocalHost(components?.host ?? "") ? nil : .notSecure
    }

    /// The default keep server: the launch argument, else the bundled value, else `builtInUrl`. The first of the two
    /// that is `offValue` gives `nil` (no keep server); empty or invalid values are skipped.
    public static func defaultUrl(argument: String?, bundled: String?) -> String? {
        for candidate in [argument, bundled] {
            guard let candidate else { continue }
            let value = OnboardingValidation.normalizedServerUrl(candidate)
            if value.lowercased() == offValue { return nil }
            if urlErrorKind(value) == nil { return value }
        }
        return builtInUrl
    }

    /// The keep server for `setting`, for `ClientConfig.keepServerUrl`; `nil` is none.
    public static func url(for setting: KeepServerSetting, defaultUrl: String?) -> String? {
        switch setting {
        case .automatic: defaultUrl
        case .custom(let url): url
        case .off: nil
        }
    }

    /// The stored setting; `.automatic` when none or an invalid one is stored.
    public static func load(from defaults: UserDefaults) -> KeepServerSetting {
        guard let value = defaults.string(forKey: settingKey) else { return .automatic }
        if value == offValue { return .off }
        return urlErrorKind(value) == nil ? .custom(value) : .automatic
    }

    /// Stores `setting`; `.automatic` removes the stored value.
    public static func store(_ setting: KeepServerSetting, in defaults: UserDefaults) {
        switch setting {
        case .automatic: defaults.removeObject(forKey: settingKey)
        case .custom(let url): defaults.set(url, forKey: settingKey)
        case .off: defaults.set(offValue, forKey: settingKey)
        }
    }

    /// The default keep server from the launch argument in `defaults` (its argument domain) and `bundled`.
    public static func defaultUrl(defaults: UserDefaults, bundled: String?) -> String? {
        defaultUrl(argument: defaults.string(forKey: defaultUrlKey), bundled: bundled)
    }

    /// The keep server for a new client: the setting stored in `defaults` applied to `defaultUrl(defaults:bundled:)`.
    public static func resolvedUrl(defaults: UserDefaults, bundled: String?) -> String? {
        url(for: load(from: defaults), defaultUrl: defaultUrl(defaults: defaults, bundled: bundled))
    }

    private static func isLocalHost(_ rawHost: String) -> Bool {
        let host = rawHost.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host == "localhost" || host.hasSuffix(".local") || host == "::1" { return true }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        let octets = parts.compactMap { UInt8($0) }
        guard parts.count == 4, octets.count == 4 else { return false }
        switch (octets[0], octets[1]) {
        case (10, _), (127, _), (192, 168), (169, 254): return true
        case (172, let second): return (16...31).contains(second)
        default: return false
        }
    }
}

/// Settings → Keep server: on or off, the address (change, reset to the default). Stores the choice with
/// `KeepServer.store`; clients created afterwards use it, the running one keeps `activeUrl`.
@MainActor
@Observable
public final class KeepServerViewModel {
    public private(set) var setting: KeepServerSetting
    /// The address field.
    public var draft: String
    /// Why the last `save()` was refused; cleared by the next change.
    public private(set) var errorKind: KeepServer.UrlError?
    /// The keep server used when nothing is chosen; `nil` is none.
    public let defaultUrl: String?
    /// The keep server of the running client.
    public let activeUrl: String?

    private let defaults: UserDefaults

    public init(defaults: UserDefaults, defaultUrl: String?, activeUrl: String?) {
        self.defaults = defaults
        self.defaultUrl = defaultUrl
        self.activeUrl = activeUrl
        let setting = KeepServer.load(from: defaults)
        self.setting = setting
        draft = KeepServer.url(for: setting, defaultUrl: defaultUrl) ?? defaultUrl ?? KeepServer.builtInUrl
    }

    /// The chosen keep server; `nil` is none.
    public var url: String? { KeepServer.url(for: setting, defaultUrl: defaultUrl) }
    public var isOn: Bool { url != nil }
    public var isDefault: Bool { setting == .automatic }
    /// Whether the choice differs from the running client's keep server, so it applies after a restart.
    public var needsRestart: Bool { url != activeUrl }

    /// Turns the keep server on (the default, or `KeepServer.builtInUrl` when the default is none) or off.
    public func setOn(_ on: Bool) {
        guard on != isOn else { return }
        if on {
            apply(defaultUrl == nil ? .custom(KeepServer.builtInUrl) : .automatic)
        } else {
            apply(.off)
        }
    }

    /// Uses the address in `draft`; the default address is stored as `.automatic`. Returns `false` and sets
    /// `errorKind` when the address is not accepted.
    @discardableResult
    public func save() -> Bool {
        if let error = KeepServer.urlErrorKind(draft) {
            errorKind = error
            return false
        }
        let url = OnboardingValidation.normalizedServerUrl(draft)
        apply(url == defaultUrl ? .automatic : .custom(url))
        return true
    }

    public func resetToDefault() {
        apply(.automatic)
    }

    private func apply(_ setting: KeepServerSetting) {
        self.setting = setting
        KeepServer.store(setting, in: defaults)
        errorKind = nil
        if let url { draft = url }
    }
}
