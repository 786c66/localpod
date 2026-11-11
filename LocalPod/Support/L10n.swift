import Foundation
import LocalPodKit

/// Helpers for user-facing strings that are assembled in Swift instead of
/// declared inline in a SwiftUI view. SwiftUI literal keys live in
/// `Localizable.strings` as the Chinese source text; semantic keys used here
/// are translated in the same table.
enum L10n {
    static func string(_ key: String) -> String {
        String(localized: String.LocalizationValue(key))
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: string(key),
            locale: .current,
            arguments: arguments
        )
    }

    /// Trash retention in whole days, for the delete-confirmation and trash
    /// footer copy. `retentionInterval` is MainActor-isolated; the value is a
    /// compile-time constant in days, so mirror it here as a plain constant.
    static let trashRetentionDays = 30
}
