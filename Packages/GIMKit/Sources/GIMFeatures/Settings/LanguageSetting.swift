import Foundation

/// The language the app currently runs in, for the Settings language row.
public enum LanguageSetting {
    /// The bundle's first preferred localization, else the current locale identifier.
    public static func currentLanguageIdentifier(bundle: Bundle = .main) -> String {
        bundle.preferredLocalizations.first ?? Locale.current.identifier
    }

    /// The language's name in that language ("English", "Deutsch"), first letter capitalized; `identifier` when
    /// Foundation has no name for it.
    public static func name(forLanguage identifier: String) -> String {
        let locale = Locale(identifier: identifier)
        guard let name = locale.localizedString(forIdentifier: identifier), !name.isEmpty else { return identifier }
        return name.prefix(1).uppercased(with: locale) + name.dropFirst()
    }

    public static func currentLanguageName(bundle: Bundle = .main) -> String {
        name(forLanguage: currentLanguageIdentifier(bundle: bundle))
    }
}
