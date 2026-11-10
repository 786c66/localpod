import Foundation

/// Explicit localization seam for the package. Keeping lookups in one place
/// makes it possible to resolve strings against a specific locale in tests,
/// independent of the host Mac or simulator language.
public enum LocalPodLocalization {
    public static func string(_ key: String, locale: Locale? = nil) -> String {
        guard let locale else {
            return String(localized: String.LocalizationValue(key), bundle: .module)
        }
        // `String(localized:locale:)` still selects the process-preferred
        // localization for table lookup in some Foundation versions. Resolve
        // the matching .lproj bundle explicitly so tests are deterministic.
        if let identifier = Bundle.preferredLocalizations(
            from: Bundle.module.localizations,
            forPreferences: [locale.identifier]
        ).first,
           let lprojURL = Bundle.module.url(
               forResource: identifier,
               withExtension: "lproj"
           ),
           let localizedBundle = Bundle(url: lprojURL) {
            return localizedBundle.localizedString(
                forKey: key,
                value: nil,
                table: nil
            )
        }
        return String(
            localized: String.LocalizationValue(key),
            bundle: .module,
            locale: locale
        )
    }

    public static func format(
        _ key: String,
        locale: Locale? = nil,
        _ arguments: CVarArg...
    ) -> String {
        let resolvedLocale = locale ?? .current
        return String(
            format: string(key, locale: resolvedLocale),
            locale: resolvedLocale,
            arguments: arguments
        )
    }
}
